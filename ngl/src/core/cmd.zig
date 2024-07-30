const std = @import("std");
const assert = std.debug.assert;

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Queue = ngl.Queue;
const Format = ngl.Format;
const SampleCount = ngl.SampleCount;
const Buffer = ngl.Buffer;
const Image = ngl.Image;
const ImageView = ngl.ImageView;
const CompareOp = ngl.CompareOp;
const Stage = ngl.Stage;
const Access = ngl.Access;
const Shader = ngl.Shader;
const ShaderLayout = ngl.ShaderLayout;
const DescriptorSet = ngl.DescriptorSet;
const QueryPool = ngl.QueryPool;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const CommandPool = struct {
    impl: Impl.CommandPool,

    pub const Desc = struct {
        queue: *Queue,
    };

    pub const ResetMode = union(enum) {
        /// Don't release resources back to the system.
        keep,
        /// Do release resources back to the system.
        release: std.mem.Allocator,
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
        assert(desc.count > 0);
        if (@typeInfo(CommandBuffer).Struct.fields.len > 1)
            @compileError("Uninitialized field(s)");

        const cmd_bufs = try allocator.alloc(CommandBuffer, desc.count);
        errdefer allocator.free(cmd_bufs);
        try Impl.get().allocCommandBuffers(allocator, device.impl, self.impl, desc, cmd_bufs);
        return cmd_bufs;
    }

    /// Invalidates all command buffers allocated from `self`.
    pub fn reset(self: *Self, device: *Device, mode: ResetMode) Error!void {
        try Impl.get().resetCommandPool(device.impl, self.impl, mode);
    }

    /// Need not be called before `self` is deinitialized.
    pub fn free(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        command_buffers: []const *CommandBuffer,
    ) void {
        Impl.get().freeCommandBuffers(allocator, device.impl, self.impl, command_buffers);
        for (command_buffers) |cmd_buf|
            cmd_buf.* = undefined;
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

    /// The command buffer must not be recording or pending execution.
    /// It must be paired with `Cmd.end`.
    /// One must ensure that the command pool which `self` was
    /// allocated from is reset before beginning again.
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
            /// If `true`, the command buffer is invalidated
            /// after execution. Otherwise, it may be
            /// re-submitted when it completes execution.
            one_time_submit: bool,
            /// This field applies only to secondary command
            /// buffers. It must be `null` when beginning a
            /// primary command buffer, and must be non-null
            /// when beginning a secondary command buffer.
            inheritance: ?struct {
                /// Constrains the secondary command buffer
                /// to a specific render pass.
                /// If set to `null`, then it must only be
                /// executed from outside of render passes.
                rendering_continue: ?struct {
                    color_formats: []const Format,
                    depth_format: ?Format,
                    stencil_format: ?Format,
                    samples: SampleCount,
                    view_mask: u32 = 0,
                },
                /// `Feature.core.query.inherited`.
                /// If set to `null`, then there must not be
                /// any queries active when the secondary
                /// command buffer executes.
                query_continue: ?struct {
                    occlusion: bool,
                    control: QueryControl,
                },
            },
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn setShaders(self: *Cmd, types: []const Shader.Type, shaders: []const ?*Shader) void {
            Impl.get().setShaders(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                types,
                shaders,
            );
        }

        pub const BindPoint = enum {
            graphics,
            compute,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn setDescriptors(
            self: *Cmd,
            bind_point: BindPoint,
            shader_layout: *ShaderLayout,
            first_set: u32,
            descriptor_sets: []const *DescriptorSet,
        ) void {
            return Impl.get().setDescriptors(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                bind_point,
                shader_layout.impl,
                first_set,
                descriptor_sets,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn setPushConstants(
            self: *Cmd,
            shader_layout: *ShaderLayout,
            shader_mask: Shader.Type.Flags,
            offset: u16,
            constants: []align(4) const u8,
        ) void {
            Impl.get().setPushConstants(
                self.device.impl,
                self.command_buffer.impl,
                shader_layout.impl,
                shader_mask,
                offset,
                constants,
            );
        }

        pub const VertexInputBinding = struct {
            binding: u32,
            stride: u32,
            step_rate: union(enum) {
                vertex,
                instance: u1, // TODO: Must be `1` currently.
            },
        };

        pub const VertexInputAttribute = struct {
            location: u32,
            binding: u32,
            format: Format,
            offset: u32,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setVertexInput(
            self: *Cmd,
            bindings: []const VertexInputBinding,
            attributes: []const VertexInputAttribute,
        ) void {
            Impl.get().setVertexInput(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                bindings,
                attributes,
            );
        }

        pub const PrimitiveTopology = enum {
            point_list,
            line_list,
            line_strip,
            triangle_list,
            triangle_strip,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setPrimitiveTopology(self: *Cmd, topology: PrimitiveTopology) void {
            Impl.get().setPrimitiveTopology(self.device.impl, self.command_buffer.impl, topology);
        }

        pub const IndexType = enum {
            u16,
            u32,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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

        pub const Viewport = struct {
            x: f32,
            y: f32,
            width: f32,
            height: f32,
            znear: f32,
            zfar: f32,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setViewports(self: *Cmd, viewports: []const Viewport) void {
            Impl.get().setViewports(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                viewports,
            );
        }

        pub const ScissorRect = struct {
            x: u32,
            y: u32,
            width: u32,
            height: u32,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setScissorRects(self: *Cmd, scissor_rects: []const ScissorRect) void {
            Impl.get().setScissorRects(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                scissor_rects,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setRasterizationEnable(self: *Cmd, enable: bool) void {
            Impl.get().setRasterizationEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        pub const PolygonMode = enum {
            fill,
            line,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setPolygonMode(self: *Cmd, polygon_mode: PolygonMode) void {
            Impl.get().setPolygonMode(self.device.impl, self.command_buffer.impl, polygon_mode);
        }

        pub const CullMode = enum {
            none,
            front,
            back,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setCullMode(self: *Cmd, cull_mode: CullMode) void {
            Impl.get().setCullMode(self.device.impl, self.command_buffer.impl, cull_mode);
        }

        pub const FrontFace = enum {
            clockwise,
            counter_clockwise,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setFrontFace(self: *Cmd, front_face: FrontFace) void {
            Impl.get().setFrontFace(self.device.impl, self.command_buffer.impl, front_face);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setSampleCount(self: *Cmd, sample_count: SampleCount) void {
            Impl.get().setSampleCount(self.device.impl, self.command_buffer.impl, sample_count);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setSampleMask(self: *Cmd, sample_mask: u64) void {
            Impl.get().setSampleMask(self.device.impl, self.command_buffer.impl, sample_mask);
        }

        /// `Feature.core.rasterization.alpha_to_one`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setAlphaToOneEnable(self: *Cmd, enable: bool) void {
            Impl.get().setAlphaToOneEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setDepthBiasEnable(self: *Cmd, enable: bool) void {
            Impl.get().setDepthBiasEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setDepthBias(self: *Cmd, value: f32, slope: f32, clamp: f32) void {
            Impl.get().setDepthBias(
                self.device.impl,
                self.command_buffer.impl,
                value,
                slope,
                clamp,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setDepthTestEnable(self: *Cmd, enable: bool) void {
            Impl.get().setDepthTestEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setDepthCompareOp(self: *Cmd, compare_op: CompareOp) void {
            Impl.get().setDepthCompareOp(self.device.impl, self.command_buffer.impl, compare_op);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setDepthWriteEnable(self: *Cmd, enable: bool) void {
            Impl.get().setDepthWriteEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setStencilTestEnable(self: *Cmd, enable: bool) void {
            Impl.get().setStencilTestEnable(self.device.impl, self.command_buffer.impl, enable);
        }

        pub const StencilFace = enum {
            front,
            back,
            front_and_back,
        };

        pub const StencilOp = enum {
            keep,
            zero,
            replace,
            increment_clamp,
            decrement_clamp,
            invert,
            increment_wrap,
            decrement_wrap,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setStencilOp(
            self: *Cmd,
            stencil_face: StencilFace,
            fail_op: StencilOp,
            pass_op: StencilOp,
            depth_fail_op: StencilOp,
            compare_op: CompareOp,
        ) void {
            Impl.get().setStencilOp(
                self.device.impl,
                self.command_buffer.impl,
                stencil_face,
                fail_op,
                pass_op,
                depth_fail_op,
                compare_op,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setStencilReadMask(self: *Cmd, stencil_face: StencilFace, mask: u32) void {
            Impl.get().setStencilReadMask(
                self.device.impl,
                self.command_buffer.impl,
                stencil_face,
                mask,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setStencilWriteMask(self: *Cmd, stencil_face: StencilFace, mask: u32) void {
            Impl.get().setStencilWriteMask(
                self.device.impl,
                self.command_buffer.impl,
                stencil_face,
                mask,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setStencilReference(self: *Cmd, stencil_face: StencilFace, reference: u32) void {
            Impl.get().setStencilReference(
                self.device.impl,
                self.command_buffer.impl,
                stencil_face,
                reference,
            );
        }

        pub const ColorAttachmentIndex = u3;
        pub const max_color_attachment = 1 + @as(comptime_int, ~@as(ColorAttachmentIndex, 0));

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setColorBlendEnable(
            self: *Cmd,
            first_attachment: ColorAttachmentIndex,
            enable: []const bool,
        ) void {
            Impl.get().setColorBlendEnable(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                first_attachment,
                enable,
            );
        }

        pub const Blend = struct {
            color_source_factor: Factor = .one,
            color_dest_factor: Factor = .zero,
            color_op: Op = .add,
            alpha_source_factor: Factor = .one,
            alpha_dest_factor: Factor = .zero,
            alpha_op: Op = .add,

            pub const Factor = enum {
                zero,
                one,
                source_color,
                one_minus_source_color,
                dest_color,
                one_minus_dest_color,
                source_alpha,
                one_minus_source_alpha,
                dest_alpha,
                one_minus_dest_alpha,
                constant_color,
                one_minus_constant_color,
                constant_alpha,
                one_minus_constant_alpha,
                source_alpha_saturate,
            };

            pub const Op = enum {
                add,
                subtract,
                reverse_subtract,
                min,
                max,
            };
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setColorBlend(
            self: *Cmd,
            first_attachment: ColorAttachmentIndex,
            blend: []const Blend,
        ) void {
            Impl.get().setColorBlend(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                first_attachment,
                blend,
            );
        }

        pub const ColorMask = union(enum) {
            all,
            mask: packed struct {
                r: bool = false,
                g: bool = false,
                b: bool = false,
                a: bool = false,
            },
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setColorWrite(
            self: *Cmd,
            first_attachment: ColorAttachmentIndex,
            write_masks: []const ColorMask,
        ) void {
            Impl.get().setColorWrite(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                first_attachment,
                write_masks,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn setBlendConstants(self: *Cmd, constants: [4]f32) void {
            Impl.get().setBlendConstants(self.device.impl, self.command_buffer.impl, constants);
        }

        pub const LoadOp = enum {
            load,
            clear,
            dont_care,
        };

        pub const StoreOp = enum {
            store,
            dont_care,
            // TODO
            //none,
        };

        pub const ClearValue = union(enum) {
            color_f32: [4]f32,
            color_i32: [4]i32,
            color_u32: [4]u32,
            depth_stencil: struct { f32, u32 },
        };

        pub const ResolveMode = enum {
            average,
            sample_zero,
            min,
            max,

            pub const Flags = ngl.Flags(ResolveMode);
        };

        pub const Rendering = struct {
            colors: []const Attachment,
            depth: ?Attachment,
            stencil: ?Attachment,
            render_area: struct {
                x: u32 = 0,
                y: u32 = 0,
                width: u32,
                height: u32,
            },
            layers: u32,
            view_mask: u32 = 0,
            contents: Contents,

            pub const Attachment = struct {
                view: *ImageView,
                layout: Image.Layout,
                load_op: LoadOp,
                store_op: StoreOp,
                clear_value: ?ClearValue,
                resolve: ?struct {
                    view: *ImageView,
                    layout: Image.Layout,
                    mode: ResolveMode,
                },
            };

            pub const Contents = enum {
                /// Calling `executeCommands` is disallowed.
                @"inline",
                /// Calling any commands other than
                /// `executeCommands` and `endRendering` is
                /// disallowed.
                replay,
            };
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn beginRendering(self: *Cmd, rendering: Rendering) void {
            Impl.get().beginRendering(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                rendering,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✘ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
        pub fn endRendering(self: *Cmd) void {
            Impl.get().endRendering(self.device.impl, self.command_buffer.impl);
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✘ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✘ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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

        /// The layout of indirect draws.
        pub const DrawIndirectCommand = extern struct {
            vertex_count: u32,
            instance_count: u32,
            first_vertex: u32,
            /// Must be zero if `Feature.core.draw.indirect_first_instance`
            /// isn't supported.
            first_instance: u32,
        };

        /// `Feature.core.draw.indirect_command`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✘ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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

        /// The layout of indexed indirect draws.
        pub const DrawIndexedIndirectCommand = extern struct {
            index_count: u32,
            instance_count: u32,
            first_index: u32,
            vertex_offset: i32,
            /// Must be zero if `Feature.core.draw.indirect_first_instance`
            /// isn't supported.
            first_instance: u32,
        };

        /// `Feature.core.draw.indexed_indirect_command`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✘ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✘ Compute queue
        /// ✘ Transfer queue
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

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✘ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
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

        /// The layout of indirect dispatches.
        pub const DispatchIndirectCommand = extern struct {
            group_count_x: u32,
            group_count_y: u32,
            group_count_z: u32,
        };

        /// `Feature.core.dispatch.indirect_command`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✘ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn dispatchIndirect(self: *Cmd, buffer: *Buffer, offset: u64) void {
            Impl.get().dispatchIndirect(
                self.device.impl,
                self.command_buffer.impl,
                buffer.impl,
                offset,
            );
        }

        /// Cleared range must be aligned to 4 bytes.
        /// Executes in `Stage.clear`.
        ///
        /// BUG: Currently, this command may require a graphics or
        /// compute queue.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ⚠ Transfer queue
        pub fn clearBuffer(self: *Cmd, buffer: *Buffer, offset: u64, size: u64, value: u8) void {
            Impl.get().clearBuffer(
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

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
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

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
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

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
        pub fn copyBufferToImage(self: *Cmd, copies: []const BufferImageCopy) void {
            Impl.get().copyBufferToImage(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
        pub fn copyImageToBuffer(self: *Cmd, copies: []const BufferImageCopy) void {
            Impl.get().copyImageToBuffer(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                copies,
            );
        }

        /// It must be called before a newly created query pool is
        /// used in other query-related commands.
        /// It must also be called between uses of the same query.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn resetQueryPool(
            self: *Cmd,
            query_pool: *QueryPool,
            first_query: u32,
            query_count: u32,
        ) void {
            Impl.get().resetQueryPool(
                self.device.impl,
                self.command_buffer.impl,
                query_pool.impl,
                first_query,
                query_count,
            );
        }

        pub const QueryControl = struct {
            /// Must be `false` if `Feature.core.query.occlusion_precise`
            /// isn't supported or the query type isn't `.occlusion`.
            precise: bool = false,
        };

        /// If called outside of a render pass, then it must also end
        /// outside of a render pass, and must not span across multiple
        /// render passes.
        /// The type of the query must not be `.timestamp`.
        /// It must be paired with `endQuery`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn beginQuery(
            self: *Cmd,
            query_pool: *QueryPool,
            query: u32,
            control: QueryControl,
        ) void {
            Impl.get().beginQuery(
                self.device.impl,
                self.command_buffer.impl,
                query_pool.type,
                query_pool.impl,
                query,
                control,
            );
        }

        /// It must be scoped as described in `beginQuery`.
        /// It's not valid to call it in a different command buffer
        /// than that of the corresponding `beginQuery`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn endQuery(self: *Cmd, query_pool: *QueryPool, query: u32) void {
            Impl.get().endQuery(
                self.device.impl,
                self.command_buffer.impl,
                query_pool.type,
                query_pool.impl,
                query,
            );
        }

        /// The type of the query must be `.timestamp`.
        ///
        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
        pub fn writeTimestamp(self: *Cmd, stage: Stage, query_pool: *QueryPool, query: u32) void {
            Impl.get().writeTimestamp(
                self.device.impl,
                self.command_buffer.impl,
                stage,
                query_pool.impl,
                query,
            );
        }

        pub const QueryResult = struct {
            /// Wait that query results be available.
            wait: bool = true,
            /// Store whether results are available for each query
            /// (alongside the results themselves).
            with_availability: bool = false,
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✘ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✘ Transfer queue
        pub fn copyQueryPoolResults(
            self: *Cmd,
            query_pool: *QueryPool,
            first_query: u32,
            query_count: u32,
            dest: *Buffer,
            dest_offset: u64,
            result: QueryResult,
        ) void {
            Impl.get().copyQueryPoolResults(
                self.device.impl,
                self.command_buffer.impl,
                query_pool.type,
                query_pool.impl,
                first_query,
                query_count,
                dest.impl,
                dest_offset,
                result,
            );
        }

        pub const Dependency = enum {
            by_region,
            view_local,
            device_group,

            pub const Flags = ngl.Flags(Dependency);
        };

        /// `global`, `buffer` and `image` must not all be empty.
        pub const Barrier = struct {
            global: []const GlobalBarrier = &.{},
            buffer: []const BufferBarrier = &.{},
            image: []const ImageBarrier = &.{},
            dependency_mask: Dependency.Flags = .{},

            pub const GlobalBarrier = struct {
                source_stage_mask: Stage.Flags,
                source_access_mask: Access.Flags,
                dest_stage_mask: Stage.Flags,
                dest_access_mask: Access.Flags,
            };

            pub const BufferBarrier = struct {
                source_stage_mask: Stage.Flags,
                source_access_mask: Access.Flags,
                dest_stage_mask: Stage.Flags,
                dest_access_mask: Access.Flags,
                queue_transfer: ?struct {
                    source: *Queue,
                    dest: *Queue,
                },
                buffer: *Buffer,
                offset: u64,
                size: u64,
            };

            pub const ImageBarrier = struct {
                source_stage_mask: Stage.Flags,
                source_access_mask: Access.Flags,
                dest_stage_mask: Stage.Flags,
                dest_access_mask: Access.Flags,
                queue_transfer: ?struct {
                    source: *Queue,
                    dest: *Queue,
                },
                old_layout: Image.Layout,
                new_layout: Image.Layout,
                image: *Image,
                range: Image.Range,
            };
        };

        /// ✔ Primary command buffer
        /// ✔ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
        pub fn barrier(self: *Cmd, barriers: []const Barrier) void {
            Impl.get().barrier(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                barriers,
            );
        }

        /// The secondary command buffers must have been ended and
        /// must not be empty. They must not be reused until
        /// `self.command_buffer` itself completes execution or is
        /// invalidated by `CommandPool.reset`.
        ///
        /// ✔ Primary command buffer
        /// ✘ Secondary command buffer
        /// ✔ Global scope
        /// ✔ Render pass scope
        /// ✔ Graphics queue
        /// ✔ Compute queue
        /// ✔ Transfer queue
        pub fn executeCommands(self: *Cmd, secondary_command_buffers: []const *CommandBuffer) void {
            Impl.get().executeCommands(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
                secondary_command_buffers,
            );
        }

        /// Finishes recording and invalidates `self`.
        /// One must ensure that `endRendering` and `endQuery`
        /// have been called for any active render pass and
        /// query, respectively.
        /// If `end` returns an error, then the command buffer
        /// is in an invalid state and must not be submitted
        /// for execution.
        /// Note that this isn't a command.
        pub fn end(self: *Cmd) Error!void {
            defer self.* = undefined;
            try Impl.get().endCommandBuffer(
                self.allocator,
                self.device.impl,
                self.command_buffer.impl,
            );
        }
    };
};
