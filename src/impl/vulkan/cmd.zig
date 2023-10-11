const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;
const Queue = @import("init.zig").Queue;
const Buffer = @import("res.zig").Buffer;
const RenderPass = @import("pass.zig").RenderPass;
const FrameBuffer = @import("pass.zig").FrameBuffer;
const PipelineLayout = @import("desc.zig").PipelineLayout;
const DescriptorSet = @import("desc.zig").DescriptorSet;
const Pipeline = @import("state.zig").Pipeline;

pub const CommandPool = struct {
    handle: c.VkCommandPool,

    pub inline fn cast(impl: Impl.CommandPool) *CommandPool {
        return impl.ptr(CommandPool);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.CommandPool.Desc,
    ) Error!Impl.CommandPool {
        const dev = Device.cast(device);
        const queue = Queue.cast(desc.queue.impl);

        var ptr = try allocator.create(CommandPool);
        errdefer allocator.destroy(ptr);

        var cmd_pool: c.VkCommandPool = undefined;
        try check(dev.vkCreateCommandPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0, // TODO: Maybe expose this
            .queueFamilyIndex = queue.family,
        }, null, &cmd_pool));

        ptr.* = .{ .handle = cmd_pool };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_pool: Impl.CommandPool,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);

        var handles = try allocator.alloc(c.VkCommandBuffer, desc.count);
        defer allocator.free(handles);

        const alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = cmd_pool.handle,
            .level = switch (desc.level) {
                .primary => c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .secondary => c.VK_COMMAND_BUFFER_LEVEL_SECONDARY,
            },
            .commandBufferCount = desc.count,
        };

        try check(dev.vkAllocateCommandBuffers(&alloc_info, handles.ptr));
        errdefer dev.vkFreeCommandBuffers(cmd_pool.handle, desc.count, handles.ptr);

        for (command_buffers, handles) |*cmd_buf, handle|
            cmd_buf.impl = .{ .val = @bitCast(CommandBuffer{ .handle = handle }) };
    }

    pub fn reset(_: *anyopaque, device: Impl.Device, command_pool: Impl.CommandPool) Error!void {
        // TODO: Maybe expose flags
        const flags: c.VkCommandPoolResetFlags = 0;
        return check(Device.cast(device).vkResetCommandPool(cast(command_pool).handle, flags));
    }

    pub fn free(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_pool: Impl.CommandPool,
        command_buffers: []const *ngl.CommandBuffer,
    ) void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);
        const n = command_buffers.len;

        var handles = allocator.alloc(c.VkCommandBuffer, n) catch {
            for (command_buffers) |cmd_buf| {
                const handle = [1]c.VkCommandBuffer{CommandBuffer.cast(cmd_buf.impl).handle};
                dev.vkFreeCommandBuffers(cmd_pool.handle, 1, &handle);
            }
            return;
        };
        defer allocator.free(handles);

        for (handles, command_buffers) |*handle, cmd_buf|
            handle.* = CommandBuffer.cast(cmd_buf.impl).handle;
        dev.vkFreeCommandBuffers(cmd_pool.handle, @intCast(n), handles.ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_pool: Impl.CommandPool,
    ) void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);
        dev.vkDestroyCommandPool(cmd_pool.handle, null);
        allocator.destroy(cmd_pool);
    }
};

pub const CommandBuffer = packed struct {
    handle: c.VkCommandBuffer,

    pub inline fn cast(impl: Impl.CommandBuffer) CommandBuffer {
        return @bitCast(impl.val);
    }

    pub fn begin(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        desc: ngl.CommandBuffer.Cmd.Desc,
    ) Error!void {
        const flags = blk: {
            var flags: c.VkCommandBufferUsageFlags = 0;
            if (desc.one_time_submit)
                flags |= c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
            if (desc.secondary != null and desc.secondary.?.render_pass_continue)
                flags |= c.VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;
            // Disallow simultaneous use
            break :blk flags;
        };

        const inher_info = if (desc.secondary) |x| &c.VkCommandBufferInheritanceInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
            .pNext = null,
            .renderPass = RenderPass.cast(x.render_pass.impl).handle,
            .subpass = x.subpass,
            .framebuffer = FrameBuffer.cast(x.frame_buffer.impl).handle,
            // TODO: Expose these
            .occlusionQueryEnable = c.VK_FALSE,
            .queryFlags = 0,
            .pipelineStatistics = 0,
        } else null;

        return check(Device.cast(device).vkBeginCommandBuffer(cast(command_buffer).handle, &.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = flags,
            .pInheritanceInfo = inher_info,
        }));
    }

    pub fn setPipeline(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        @"type": ngl.Pipeline.Type,
        pipeline: Impl.Pipeline,
    ) void {
        return Device.cast(device).vkCmdBindPipeline(
            cast(command_buffer).handle,
            conv.toVkPipelineBindPoint(@"type"),
            Pipeline.cast(pipeline).handle,
        );
    }

    pub fn setDescriptors(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        pipeline_type: ngl.Pipeline.Type,
        pipeline_layout: Impl.PipelineLayout,
        first_set: u32,
        descriptor_sets: []const *ngl.DescriptorSet,
    ) void {
        var desc_set: [1]c.VkDescriptorSet = undefined;
        var desc_sets = if (descriptor_sets.len > 1) allocator.alloc(
            c.VkDescriptorSet,
            descriptor_sets.len,
        ) catch {
            for (0..descriptor_sets.len) |i|
                setDescriptors(
                    undefined,
                    allocator,
                    device,
                    command_buffer,
                    pipeline_type,
                    pipeline_layout,
                    @intCast(first_set + i),
                    descriptor_sets[i .. i + 1],
                );
            return;
        } else &desc_set;
        defer if (desc_sets.len > 1) allocator.free(desc_sets);

        for (desc_sets, descriptor_sets) |*handle, set|
            handle.* = DescriptorSet.cast(set.impl).handle;

        Device.cast(device).vkCmdBindDescriptorSets(
            cast(command_buffer).handle,
            conv.toVkPipelineBindPoint(pipeline_type),
            PipelineLayout.cast(pipeline_layout).handle,
            first_set,
            @intCast(desc_sets.len),
            desc_sets.ptr,
            0,
            null,
        );
    }

    pub fn setPushConstants(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        pipeline_layout: Impl.PipelineLayout,
        stage_mask: ngl.ShaderStage.Flags,
        offset: u16,
        constants: []align(4) const u8,
    ) void {
        Device.cast(device).vkCmdPushConstants(
            cast(command_buffer).handle,
            PipelineLayout.cast(pipeline_layout).handle,
            conv.toVkShaderStageFlags(stage_mask),
            offset,
            @intCast(constants.len),
            constants.ptr,
        );
    }

    pub fn setIndexBuffer(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        index_type: ngl.CommandBuffer.Cmd.IndexType,
        buffer: Impl.Buffer,
        offset: u64,
        _: u64, // Requires newer command
    ) void {
        Device.cast(device).vkCmdBindIndexBuffer(
            cast(command_buffer).handle,
            Buffer.cast(buffer).handle,
            offset,
            conv.toVkIndexType(index_type),
        );
    }

    pub fn setVertexBuffers(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        first_binding: u32,
        buffers: []const *ngl.Buffer,
        offsets: []const u64,
        _: []const u64, // Requires newer command
    ) void {
        const n = 16;
        var stk_bufs: [n]c.VkBuffer = undefined;
        var bufs = if (buffers.len > n) allocator.alloc(c.VkBuffer, buffers.len) catch {
            var i: usize = 0;
            while (i < buffers.len) : (i += n) {
                const j = @min(i + n, buffers.len);
                setVertexBuffers(
                    undefined,
                    allocator,
                    device,
                    command_buffer,
                    @intCast(first_binding + i),
                    buffers[i..j],
                    offsets[i..j],
                    undefined,
                );
            }
            return;
        } else stk_bufs[0..buffers.len];
        defer if (bufs.len > n) allocator.free(bufs);

        for (bufs, buffers) |*handle, buf|
            handle.* = Buffer.cast(buf.impl).handle;

        Device.cast(device).vkCmdBindVertexBuffers(
            cast(command_buffer).handle,
            first_binding,
            @intCast(buffers.len),
            bufs.ptr,
            offsets.ptr,
        );
    }

    pub fn setViewport(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        viewport: ngl.Viewport,
    ) void {
        const dev = Device.cast(device);
        const cmd_buf = cast(command_buffer);

        const vport: [1]c.VkViewport = .{.{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = viewport.height,
            .minDepth = viewport.near,
            .maxDepth = viewport.far,
        }};

        const sciss: [1]c.VkRect2D = .{if (viewport.scissor) |x| .{
            .offset = .{
                .x = @min(x.x, std.math.maxInt(i32)),
                .y = @min(x.y, std.math.maxInt(i32)),
            },
            .extent = .{
                .width = x.width,
                .height = x.height,
            },
        } else .{
            .offset = .{
                .x = @intFromFloat(@min(@fabs(viewport.x), std.math.maxInt(i32))),
                .y = @intFromFloat(@min(@fabs(viewport.y), std.math.maxInt(i32))),
            },
            .extent = .{
                .width = @intFromFloat(@min(@fabs(viewport.width), std.math.maxInt(u32))),
                .height = @intFromFloat(@min(@fabs(viewport.height), std.math.maxInt(u32))),
            },
        }};

        dev.vkCmdSetViewport(cmd_buf.handle, 0, 1, &vport);
        dev.vkCmdSetScissor(cmd_buf.handle, 0, 1, &sciss);
    }

    pub fn setStencilReference(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stencil_face: ngl.CommandBuffer.Cmd.StencilFace,
        reference: u32,
    ) void {
        Device.cast(device).vkCmdSetStencilReference(
            cast(command_buffer).handle,
            conv.toVkStencilFaceFlags(stencil_face),
            reference,
        );
    }

    pub fn setBlendConstants(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        constants: [4]f32,
    ) void {
        Device.cast(device).vkCmdSetBlendConstants(cast(command_buffer).handle, &constants);
    }

    pub fn beginRenderPass(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        render_pass_begin: ngl.CommandBuffer.Cmd.RenderPassBegin,
        subpass_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
    ) void {
        const n = 16;
        var stk_clears: [n]c.VkClearValue = undefined;
        var clears = if (render_pass_begin.clear_values.len > n) allocator.alloc(
            c.VkClearValue,
            render_pass_begin.clear_values.len,
        ) catch {
            // TODO: Handle this somehow
            @panic("OOM");
        } else stk_clears[0..render_pass_begin.clear_values.len];
        defer if (clears.len > n) allocator.free(clears);

        for (clears, render_pass_begin.clear_values) |*vk_clear, clear|
            vk_clear.* = if (clear) |x| conv.toVkClearValue(x) else undefined;

        const render_area: c.VkRect2D = .{
            .offset = .{
                .x = @min(render_pass_begin.render_area.x, std.math.maxInt(i32)),
                .y = @min(render_pass_begin.render_area.y, std.math.maxInt(i32)),
            },
            .extent = .{
                .width = render_pass_begin.render_area.width,
                .height = render_pass_begin.render_area.height,
            },
        };

        Device.cast(device).vkCmdBeginRenderPass(cast(command_buffer).handle, &.{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = RenderPass.cast(render_pass_begin.render_pass.impl).handle,
            .framebuffer = FrameBuffer.cast(render_pass_begin.frame_buffer.impl).handle,
            .renderArea = render_area,
            .clearValueCount = @as(u32, @intCast(clears.len)),
            .pClearValues = clears.ptr,
        }, conv.toVkSubpassContents(subpass_begin.contents));
    }

    pub fn nextSubpass(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        next_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
        _: ngl.CommandBuffer.Cmd.SubpassEnd,
    ) void {
        Device.cast(device).vkCmdNextSubpass(
            cast(command_buffer).handle,
            conv.toVkSubpassContents(next_begin.contents),
        );
    }

    pub fn endRenderPass(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        _: ngl.CommandBuffer.Cmd.SubpassEnd,
    ) void {
        Device.cast(device).vkCmdEndRenderPass(cast(command_buffer).handle);
    }

    pub fn draw(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        Device.cast(device).vkCmdDraw(
            cast(command_buffer).handle,
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
        );
    }

    pub fn drawIndexed(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        Device.cast(device).vkCmdDrawIndexed(
            cast(command_buffer).handle,
            index_count,
            instance_count,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    pub fn drawIndirect(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        buffer: Impl.Buffer,
        offset: u64,
        draw_count: u32,
        stride: u32,
    ) void {
        Device.cast(device).vkCmdDrawIndirect(
            cast(command_buffer).handle,
            Buffer.cast(buffer).handle,
            offset,
            draw_count,
            stride,
        );
    }

    pub fn drawIndexedIndirect(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        buffer: Impl.Buffer,
        offset: u64,
        draw_count: u32,
        stride: u32,
    ) void {
        Device.cast(device).vkCmdDrawIndexedIndirect(
            cast(command_buffer).handle,
            Buffer.cast(buffer).handle,
            offset,
            draw_count,
            stride,
        );
    }

    pub fn dispatch(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        group_count_x: u32,
        group_count_y: u32,
        group_count_z: u32,
    ) void {
        Device.cast(device).vkCmdDispatch(
            cast(command_buffer).handle,
            group_count_x,
            group_count_y,
            group_count_z,
        );
    }

    pub fn dispatchIndirect(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        buffer: Impl.Buffer,
        offset: u64,
    ) void {
        Device.cast(device).vkCmdDispatchIndirect(
            cast(command_buffer).handle,
            Buffer.cast(buffer).handle,
            offset,
        );
    }

    pub fn executeCommands(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        secondary_command_buffers: []const *ngl.CommandBuffer,
    ) void {
        // Ideally, this would be the number of available cores,
        // but such value isn't known at compile time
        const n = if (builtin.single_threaded) 1 else 16;
        var stk_cmd_bufs: [n]c.VkCommandBuffer = undefined;
        var cmd_bufs = if (secondary_command_buffers.len > n) allocator.alloc(
            c.VkCommandBuffer,
            secondary_command_buffers.len,
        ) catch {
            var i: usize = 0;
            while (i < secondary_command_buffers.len) : (i += n) {
                const j = @min(i + n, secondary_command_buffers.len);
                executeCommands(
                    undefined,
                    allocator,
                    device,
                    command_buffer,
                    secondary_command_buffers[i..j],
                );
            }
            return;
        } else stk_cmd_bufs[0..secondary_command_buffers.len];
        defer if (cmd_bufs.len > n) allocator.free(cmd_bufs);

        for (cmd_bufs, secondary_command_buffers) |*handle, cmd_buf|
            handle.* = cast(cmd_buf.impl).handle;

        Device.cast(device).vkCmdExecuteCommands(
            cast(command_buffer).handle,
            @intCast(cmd_bufs.len),
            cmd_bufs.ptr,
        );
    }

    pub fn end(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
    ) Error!void {
        return check(Device.cast(device).vkEndCommandBuffer(cast(command_buffer).handle));
    }
};
