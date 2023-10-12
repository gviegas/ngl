const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Queue = ngl.Queue;
const Buffer = ngl.Buffer;
const Image = ngl.Image;
const RenderPass = ngl.RenderPass;
const FrameBuffer = ngl.FrameBuffer;
const PipelineLayout = ngl.PipelineLayout;
const DescriptorSet = ngl.DescriptorSet;
const ShaderStage = ngl.ShaderStage;
const Viewport = ngl.Viewport;
const Pipeline = ngl.Pipeline;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const CommandPool = struct {
    impl: Impl.CommandPool,

    pub const Desc = struct {
        queue: *Queue,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initCommandPool(allocator, device.impl, desc) };
    }

    /// Caller is responsible for freeing the returned slice.
    pub fn alloc(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: CommandBuffer.Desc,
    ) Error![]CommandBuffer {
        std.debug.assert(desc.count > 0);
        var cmd_bufs = try allocator.alloc(CommandBuffer, desc.count);
        errdefer allocator.free(cmd_bufs);
        // TODO: Update this when adding more fields to `CommandBuffer`
        if (@typeInfo(CommandBuffer).Struct.fields.len > 1) @compileError("Uninitialized field(s)");
        try Impl.get().allocCommandBuffers(allocator, device.impl, self.impl, desc, cmd_bufs);
        return cmd_bufs;
    }

    pub fn reset(self: *Self, device: *Device) Error!void {
        return Impl.get().resetCommandPool(device.impl, self.impl);
    }

    pub fn free(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        command_buffers: []const *CommandBuffer,
    ) void {
        Impl.get().freeCommandBuffers(allocator, device.impl, self.impl, command_buffers);
        for (command_buffers) |cmd_buf| cmd_buf.* = undefined;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitCommandPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const CommandBuffer = struct {
    impl: Impl.CommandBuffer,

    pub const Level = enum {
        primary,
        secondary,
    };

    pub const Desc = struct {
        level: Level,
        count: u32,
    };

    const Self = @This();

    /// It must be paired with `Cmd.end`.
    pub fn begin(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: Cmd.Desc,
    ) Error!Cmd {
        try Impl.get().beginCommandBuffer(allocator, device.impl, self.impl, desc);
        return .{
            .command_buffer = self,
            .device = device,
            .allocator = allocator,
        };
    }

    pub const Cmd = struct {
        command_buffer: *Self,
        device: *Device,
        allocator: std.mem.Allocator,

        pub const Desc = struct {
            one_time_submit: bool,
            // This field only applies to secondary
            // command buffers
            inheritance: ?struct {
                render_pass_continue: bool,
                render_pass: ?*RenderPass,
                subpass: RenderPass.Index,
                frame_buffer: ?*FrameBuffer,
            },
        };

        /// Pipelines of different `Pipeline.Type`s can coexist.
        pub fn setPipeline(self: *Cmd, pipeline: *Pipeline) void {
            Impl.get().setPipeline(
                self.device.impl,
                self.command_buffer.impl,
                pipeline.type,
                pipeline.impl,
            );
        }

        pub fn setDescriptors(
            self: *Cmd,
            pipeline_type: Pipeline.Type,
            pipeline_layout: *PipelineLayout,
            first_set: u32,
            descriptor_sets: []const *DescriptorSet,
        ) void {
            return Impl.get().setDescriptors(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                pipeline_type,
                pipeline_layout.impl,
                first_set,
                descriptor_sets,
            );
        }

        pub fn setPushConstants(
            self: *Cmd,
            pipeline_layout: *PipelineLayout,
            stage_mask: ShaderStage.Flags,
            offset: u16,
            constants: []align(4) const u8,
        ) void {
            Impl.get().setPushConstants(
                self.device.impl,
                self.command_buffer.impl,
                pipeline_layout.impl,
                stage_mask,
                offset,
                constants,
            );
        }

        pub const IndexType = enum {
            u16,
            u32,
        };

        pub fn setIndexBuffer(
            self: *Cmd,
            index_type: IndexType,
            buffer: *Buffer,
            offset: u64,
            size: u64,
        ) void {
            Impl.get().setIndexBuffer(
                self.device.impl,
                self.command_buffer.impl,
                index_type,
                buffer.impl,
                offset,
                size,
            );
        }

        /// The slices must have the same length.
        pub fn setVertexBuffers(
            self: *Cmd,
            first_binding: u32,
            buffers: []const *Buffer,
            offsets: []const u64,
            sizes: []const u64,
        ) void {
            Impl.get().setVertexBuffers(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                first_binding,
                buffers,
                offsets,
                sizes,
            );
        }

        /// Only valid for pipelines with unspecified viewport state.
        pub fn setViewport(self: *Cmd, viewport: Viewport) void {
            Impl.get().setViewport(self.device.impl, self.command_buffer.impl, viewport);
        }

        pub const StencilFace = enum {
            front,
            back,
            front_and_back,
        };

        /// Only valid for pipelines with unspecified stencil reference.
        pub fn setStencilReference(self: *Cmd, stencil_face: StencilFace, reference: u32) void {
            Impl.get().setStencilReference(
                self.device.impl,
                self.command_buffer.impl,
                stencil_face,
                reference,
            );
        }

        /// Only valid for pipelines with unspecified blend constants.
        pub fn setBlendConstants(self: *Cmd, constants: [4]f32) void {
            Impl.get().setBlendConstants(self.device.impl, self.command_buffer.impl, constants);
        }

        pub const ClearValue = union(enum) {
            color_f32: [4]f32,
            color_i32: [4]i32,
            color_u32: [4]u32,
            depth_stencil: struct { f32, u32 },
        };

        pub const RenderPassBegin = struct {
            render_pass: *RenderPass,
            frame_buffer: *FrameBuffer,
            render_area: struct {
                x: u32,
                y: u32,
                width: u32,
                height: u32,
            },
            // One clear value per attachment
            clear_values: []const ?ClearValue,
        };

        pub const SubpassContents = enum {
            inline_only,
            secondary_command_buffers_only,
        };

        pub const SubpassBegin = struct {
            contents: SubpassContents,
        };

        pub const SubpassEnd = struct {};

        /// It must not be called from within another render pass
        /// and it must be paired with `endRenderPass`.
        pub fn beginRenderPass(
            self: *Cmd,
            render_pass_begin: RenderPassBegin,
            subpass_begin: SubpassBegin,
        ) void {
            Impl.get().beginRenderPass(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                render_pass_begin,
                subpass_begin,
            );
        }

        /// Not used on render passes that have a single subpass.
        pub fn nextSubpass(self: *Cmd, next_begin: SubpassBegin, current_end: SubpassEnd) void {
            Impl.get().nextSubpass(
                self.device.impl,
                self.command_buffer.impl,
                next_begin,
                current_end,
            );
        }

        /// It must only be called from within the last subpass of
        /// a render pass.
        pub fn endRenderPass(self: *Cmd, subpass_end: SubpassEnd) void {
            Impl.get().endRenderPass(self.device.impl, self.command_buffer.impl, subpass_end);
        }

        pub fn draw(
            self: *Cmd,
            vertex_count: u32,
            instance_count: u32,
            first_vertex: u32,
            first_instance: u32,
        ) void {
            Impl.get().draw(
                self.device.impl,
                self.command_buffer.impl,
                vertex_count,
                instance_count,
                first_vertex,
                first_instance,
            );
        }

        pub fn drawIndexed(
            self: *Cmd,
            index_count: u32,
            instance_count: u32,
            first_index: u32,
            vertex_offset: i32,
            first_instance: u32,
        ) void {
            Impl.get().drawIndexed(
                self.device.impl,
                self.command_buffer.impl,
                index_count,
                instance_count,
                first_index,
                vertex_offset,
                first_instance,
            );
        }

        pub const DrawIndirectCommand = packed struct {
            vertex_count: u32,
            instance_count: u32,
            first_vertex: u32,
            first_instance: u32,
        };

        pub fn drawIndirect(
            self: *Cmd,
            buffer: *Buffer,
            offset: u64,
            draw_count: u32,
            stride: u32,
        ) void {
            Impl.get().drawIndirect(
                self.device.impl,
                self.command_buffer.impl,
                buffer.impl,
                offset,
                draw_count,
                stride,
            );
        }

        pub const DrawIndexedIndirectCommand = packed struct {
            index_count: u32,
            instance_count: u32,
            first_index: u32,
            vertex_offset: i32,
            first_instance: u32,
        };

        pub fn drawIndexedIndirect(
            self: *Cmd,
            buffer: *Buffer,
            offset: u64,
            draw_count: u32,
            stride: u32,
        ) void {
            Impl.get().drawIndexedIndirect(
                self.device.impl,
                self.command_buffer.impl,
                buffer.impl,
                offset,
                draw_count,
                stride,
            );
        }

        pub fn dispatch(
            self: *Cmd,
            group_count_x: u32,
            group_count_y: u32,
            group_count_z: u32,
        ) void {
            Impl.get().dispatch(
                self.device.impl,
                self.command_buffer.impl,
                group_count_x,
                group_count_y,
                group_count_z,
            );
        }

        pub const DispatchIndirectCommand = packed struct {
            group_count_x: u32,
            group_count_y: u32,
            group_count_z: u32,
        };

        pub fn dispatchIndirect(self: *Cmd, buffer: *Buffer, offset: u64) void {
            Impl.get().dispatchIndirect(
                self.device.impl,
                self.command_buffer.impl,
                buffer.impl,
                offset,
            );
        }

        /// Filled range must be 4-byte aligned.
        pub fn fillBuffer(self: *Cmd, buffer: *Buffer, offset: u64, size: ?u64, value: u8) void {
            Impl.get().fillBuffer(
                self.device.impl,
                self.command_buffer.impl,
                buffer.impl,
                offset,
                size,
                value,
            );
        }

        pub const BufferCopy = struct {
            source: *Buffer,
            dest: *Buffer,
            regions: []const Region,

            pub const Region = struct {
                source_offset: u64,
                dest_offset: u64,
                size: u64,
            };
        };

        pub fn copyBuffer(self: *Cmd, copies: []const BufferCopy) void {
            Impl.get().copyBuffer(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        pub const ImageCopy = struct {
            source: *Image,
            source_layout: Image.Layout,
            dest: *Image,
            dest_layout: Image.Layout,
            // TODO: Consider adding a `type` field to `Image`
            type: Image.Type,
            regions: []const Region,

            pub const Region = struct {
                source_aspect: Image.Aspect,
                source_level: u32,
                source_x: u32,
                source_y: u32,
                source_z_or_layer: u32,
                dest_aspect: Image.Aspect,
                dest_level: u32,
                dest_x: u32,
                dest_y: u32,
                dest_z_or_layer: u32,
                width: u32,
                height: u32,
                depth_or_layers: u32,
            };
        };

        pub fn copyImage(self: *Cmd, copies: []const ImageCopy) void {
            Impl.get().copyImage(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        pub const BufferImageCopy = struct {
            buffer: *Buffer,
            image: *Image,
            image_layout: Image.Layout,
            image_type: Image.Type,
            regions: []const Region,

            pub const Region = struct {
                buffer_offset: u64,
                buffer_row_length: u32,
                buffer_image_height: u32,
                image_aspect: Image.Aspect,
                image_level: u32,
                image_x: u32,
                image_y: u32,
                image_z_or_layer: u32,
                image_width: u32,
                image_height: u32,
                image_depth_or_layers: u32,
            };
        };

        pub fn copyBufferToImage(self: *Cmd, copies: []const BufferImageCopy) void {
            Impl.get().copyBufferToImage(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        pub fn copyImageToBuffer(self: *Cmd, copies: []const BufferImageCopy) void {
            Impl.get().copyImageToBuffer(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        /// It must only be called on a primary command buffer.
        /// The secondary command buffers must not be reused until
        /// `self.command_buffer` itself completes execution or is
        /// invalidated by `CommandPool.reset`.
        pub fn executeCommands(self: *Cmd, secondary_command_buffers: []const *CommandBuffer) void {
            Impl.get().executeCommands(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                secondary_command_buffers,
            );
        }

        /// Invalidates `self`.
        pub fn end(self: *Cmd) Error!void {
            defer self.* = undefined;
            return Impl.get().endCommandBuffer(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
            );
        }
    };
};
