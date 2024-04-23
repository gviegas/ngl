const std = @import("std");
const builtin = @import("builtin");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const dyn = @import("../common/dyn.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const Cache = @import("Cache.zig");
const Device = @import("init.zig").Device;
const Queue = @import("init.zig").Queue;
const Buffer = @import("res.zig").Buffer;
const Image = @import("res.zig").Image;
const RenderPass = @import("pass.zig").RenderPass;
const FrameBuffer = @import("pass.zig").FrameBuffer;
const PipelineLayout = @import("desc.zig").PipelineLayout;
const DescriptorSet = @import("desc.zig").DescriptorSet;
const Pipeline = @import("state.zig").Pipeline;
const getQueryLayout = @import("query.zig").getQueryLayout;
const QueryPool = @import("query.zig").QueryPool;

pub const CommandPool = struct {
    handle: c.VkCommandPool,
    allocs: std.ArrayListUnmanaged(*CommandBuffer),
    unused: std.bit_set.DynamicBitSetUnmanaged,

    pub fn cast(impl: Impl.CommandPool) *CommandPool {
        return impl.ptr(CommandPool);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.CommandPool.Desc,
    ) Error!Impl.CommandPool {
        var cmd_pool: c.VkCommandPool = undefined;
        try check(Device.cast(device).vkCreateCommandPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0, // TODO: Maybe expose this.
            .queueFamilyIndex = Queue.cast(desc.queue.impl).family,
        }, null, &cmd_pool));

        const ptr = try allocator.create(CommandPool);
        ptr.* = .{
            .handle = cmd_pool,
            .allocs = .{},
            .unused = .{},
        };
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
        const need_dyn = !dev.isFullyDynamic();

        const handles = try allocator.alloc(c.VkCommandBuffer, desc.count);
        defer allocator.free(handles);
        try check(dev.vkAllocateCommandBuffers(&.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = cmd_pool.handle,
            .level = switch (desc.level) {
                .primary => c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .secondary => c.VK_COMMAND_BUFFER_LEVEL_SECONDARY,
            },
            .commandBufferCount = desc.count,
        }, handles.ptr));
        errdefer dev.vkFreeCommandBuffers(cmd_pool.handle, desc.count, handles.ptr);

        const prev_n = cmd_pool.allocs.items.len;
        const unused_n = cmd_pool.unused.count();
        errdefer {
            cmd_pool.allocs.resize(allocator, prev_n) catch unreachable;
            cmd_pool.unused.resize(allocator, prev_n, false) catch unreachable;
        }
        if (unused_n < desc.count) {
            const needed_n = prev_n + desc.count - unused_n;
            try cmd_pool.allocs.resize(allocator, needed_n);
            try cmd_pool.unused.resize(allocator, needed_n, true);
            for (prev_n..needed_n) |i| {
                errdefer for (prev_n..i) |j| {
                    if (need_dyn) allocator.destroy(cmd_pool.allocs.items[j].dyn.?);
                    allocator.destroy(cmd_pool.allocs.items[j]);
                };
                cmd_pool.allocs.items[i] = try allocator.create(CommandBuffer);
                cmd_pool.allocs.items[i].* = .{
                    .handle = null_handle,
                    .dyn = blk: {
                        if (!need_dyn) break :blk null;
                        const dyn_ptr = allocator.create(Dynamic) catch |err| {
                            allocator.destroy(cmd_pool.allocs.items[i]);
                            return err;
                        };
                        dyn_ptr.* = Dynamic.init();
                        break :blk dyn_ptr;
                    },
                };
            }
        }

        for (command_buffers, handles) |*cmd_buf, handle| {
            const idx = cmd_pool.unused.findFirstSet().?;
            cmd_pool.unused.unset(idx);
            const ptr = cmd_pool.allocs.items[idx];
            ptr.handle = handle;
            if (need_dyn) ptr.dyn.?.clear(null, dev);
            cmd_buf.impl = .{ .val = @intFromPtr(ptr) };
        }
    }

    // TODO: Tie allocator w/ `release` mode.
    pub fn reset(
        _: *anyopaque,
        device: Impl.Device,
        command_pool: Impl.CommandPool,
        mode: ngl.CommandPool.ResetMode,
    ) Error!void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);
        const need_dyn = !dev.isFullyDynamic();

        try check(dev.vkResetCommandPool(cmd_pool.handle, switch (mode) {
            .keep => 0,
            .release => c.VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT,
        }));

        if (!need_dyn) return;

        var iter = cmd_pool.unused.iterator(.{ .kind = .unset });
        while (iter.next()) |idx|
            cmd_pool.allocs.items[idx].dyn.?.clear(null, dev);
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
        // Should be safe to assume this.
        var n: u32 = @intCast(command_buffers.len);

        if (allocator.alloc(c.VkCommandBuffer, n)) |handles| {
            for (handles, command_buffers) |*handle, cmd_buf| {
                handle.* = CommandBuffer.cast(cmd_buf.impl).handle;
                CommandBuffer.cast(cmd_buf.impl).handle = null_handle;
            }
            dev.vkFreeCommandBuffers(cmd_pool.handle, n, handles.ptr);
            allocator.free(handles);
        } else |_| {
            for (command_buffers) |cmd_buf| {
                const handle = [1]c.VkCommandBuffer{CommandBuffer.cast(cmd_buf.impl).handle};
                dev.vkFreeCommandBuffers(cmd_pool.handle, 1, &handle);
                CommandBuffer.cast(cmd_buf.impl).handle = null_handle;
            }
        }

        // `CommandBuffer` could store an index into `CommandPool`'s
        // data instead. This may be worth doing if allocating many
        // command buffers per command pool turns out to be common.
        // Should also move the whole data to the command pool in
        // this case.
        for (cmd_pool.allocs.items, 0..) |ptr, i| {
            if (cmd_pool.unused.isSet(i)) continue;
            if (ptr.handle == null_handle) {
                cmd_pool.unused.set(i);
                n -= 1;
                if (n == 0)
                    break;
            }
        }
        std.debug.assert(n == 0);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_pool: Impl.CommandPool,
    ) void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);
        const need_dyn = !dev.isFullyDynamic();

        dev.vkDestroyCommandPool(cmd_pool.handle, null);
        for (cmd_pool.allocs.items) |ptr| {
            if (need_dyn) {
                // BUG: This assumes that the same allocator is
                // used by both `CommandPool` and `CommandBuffer`
                // (need to enforce this in the client API).
                ptr.dyn.?.clear(allocator, dev);
                allocator.destroy(ptr.dyn.?);
            }
            allocator.destroy(ptr);
        }
        cmd_pool.allocs.deinit(allocator);
        cmd_pool.unused.deinit(allocator);
        allocator.destroy(cmd_pool);
    }
};

pub const CommandBuffer = struct {
    handle: c.VkCommandBuffer,
    dyn: ?*Dynamic,

    pub fn cast(impl: Impl.CommandBuffer) *CommandBuffer {
        return impl.ptr(CommandBuffer);
    }

    pub fn begin(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        desc: ngl.Cmd.Desc,
    ) Error!void {
        const flags = blk: {
            var flags: c.VkCommandBufferUsageFlags = 0;
            if (desc.one_time_submit)
                flags |= c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
            if (desc.inheritance != null and desc.inheritance.?.render_pass_continue != null)
                flags |= c.VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;
            // Disallow simultaneous use.
            break :blk flags;
        };

        const inher_info = blk: {
            const inher = desc.inheritance orelse break :blk null;
            var info = c.VkCommandBufferInheritanceInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
                .pNext = null,
                .renderPass = null_handle,
                .subpass = 0,
                .framebuffer = null_handle,
                .occlusionQueryEnable = c.VK_FALSE,
                .queryFlags = 0,
                .pipelineStatistics = 0,
            };
            if (inher.render_pass_continue) |x| {
                info.renderPass = RenderPass.cast(x.render_pass.impl).handle;
                info.subpass = x.subpass;
                info.framebuffer = FrameBuffer.cast(x.frame_buffer.impl).handle;
            }
            if (inher.query_continue) |x| {
                if (x.occlusion)
                    info.occlusionQueryEnable = c.VK_TRUE;
                if (x.control.precise)
                    info.queryFlags = c.VK_QUERY_CONTROL_PRECISE_BIT;
            }
            break :blk &info;
        };

        try check(Device.cast(device).vkBeginCommandBuffer(cast(command_buffer).handle, &.{
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

    pub fn setShaders(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        types: []const ngl.Shader.Type,
        shaders: []const ?*ngl.Shader,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.shaders.set(types, shaders)
        else {
            _ = allocator;
            _ = device;
            @panic("Not yet implemented");
        }
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
        const desc_sets = if (descriptor_sets.len > 1) allocator.alloc(
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

    pub fn setVertexInput(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        bindings: []const ngl.Cmd.VertexInputBinding,
        attributes: []const ngl.Cmd.VertexInputAttribute,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.vertex_input.set(allocator, bindings, attributes) catch |err| {
                d.err = err;
            }
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setPrimitiveTopology(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        topology: ngl.Cmd.PrimitiveTopology,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.primitive_topology.set(topology)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setIndexBuffer(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        index_type: ngl.Cmd.IndexType,
        buffer: Impl.Buffer,
        offset: u64,
        _: u64, // TODO: Requires newer command.
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
        _: []const u64, // TODO: Requires newer command.
    ) void {
        const n = 16;
        var stk_bufs: [n]c.VkBuffer = undefined;
        const bufs = if (buffers.len > n) allocator.alloc(c.VkBuffer, buffers.len) catch {
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

    pub fn setViewports(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        viewports: []const ngl.Cmd.Viewport,
    ) void {
        const n = 1;
        var stk_vports: [n]c.VkViewport = undefined;
        const vports = if (viewports.len > n) allocator.alloc(c.VkViewport, viewports.len) catch {
            var i: usize = 0;
            while (i < viewports.len) : (i += n) {
                const j = @min(i + n, viewports.len);
                setViewports(undefined, allocator, device, command_buffer, viewports[i..j]);
            }
            return;
        } else stk_vports[0..viewports.len];
        defer if (vports.len > n) allocator.free(vports);

        for (vports, viewports) |*vport, viewport|
            vport.* = .{
                .x = viewport.x,
                .y = viewport.y,
                .width = viewport.width,
                .height = viewport.height,
                .minDepth = viewport.znear,
                .maxDepth = viewport.zfar,
            };

        Device.cast(device).vkCmdSetViewport(
            cast(command_buffer).handle,
            0,
            @intCast(viewports.len),
            vports.ptr,
        );
    }

    pub fn setScissorRects(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        scissor_rects: []const ngl.Cmd.ScissorRect,
    ) void {
        const n = 1;
        var stk_rects: [n]c.VkRect2D = undefined;
        const rects = if (scissor_rects.len > n) allocator.alloc(
            c.VkRect2D,
            scissor_rects.len,
        ) catch {
            var i: usize = 0;
            while (i < scissor_rects.len) : (i += n) {
                const j = @min(i + n, scissor_rects.len);
                setScissorRects(undefined, allocator, device, command_buffer, scissor_rects[i..j]);
            }
            return;
        } else stk_rects[0..scissor_rects.len];
        defer if (rects.len > n) allocator.free(rects);

        for (rects, scissor_rects) |*rect, scissor_rect|
            rect.* = .{
                .offset = .{
                    .x = @min(scissor_rect.x, std.math.maxInt(i32)),
                    .y = @min(scissor_rect.y, std.math.maxInt(i32)),
                },
                .extent = .{
                    .width = scissor_rect.width,
                    .height = scissor_rect.height,
                },
            };

        Device.cast(device).vkCmdSetScissor(
            cast(command_buffer).handle,
            0,
            @intCast(scissor_rects.len),
            rects.ptr,
        );
    }

    pub fn setRasterizationEnable(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        enable: bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.rasterization_enable.set(enable)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setPolygonMode(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        polygon_mode: ngl.Cmd.PolygonMode,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.polygon_mode.set(polygon_mode)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setCullMode(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        cull_mode: ngl.Cmd.CullMode,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.cull_mode.set(cull_mode)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setFrontFace(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        front_face: ngl.Cmd.FrontFace,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.front_face.set(front_face)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setSampleCount(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        sample_count: ngl.SampleCount,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.sample_count.set(sample_count)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setSampleMask(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        sample_mask: u64,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.sample_mask.set(sample_mask)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setDepthBiasEnable(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        enable: bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.depth_bias_enable.set(enable)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setDepthBias(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        value: f32,
        slope: f32,
        clamp: f32,
    ) void {
        Device.cast(device).vkCmdSetDepthBias(cast(command_buffer).handle, value, clamp, slope);
    }

    pub fn setDepthTestEnable(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        enable: bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.depth_test_enable.set(enable)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setDepthCompareOp(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        compare_op: ngl.CompareOp,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.depth_compare_op.set(compare_op)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setDepthWriteEnable(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        enable: bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.depth_write_enable.set(enable)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setStencilTestEnable(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        enable: bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.stencil_test_enable.set(enable)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setStencilOp(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        fail_op: ngl.Cmd.StencilOp,
        pass_op: ngl.Cmd.StencilOp,
        depth_fail_op: ngl.Cmd.StencilOp,
        compare_op: ngl.CompareOp,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.stencil_op.set(stencil_face, fail_op, pass_op, depth_fail_op, compare_op)
        else {
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setStencilReadMask(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        mask: u32,
    ) void {
        Device.cast(device).vkCmdSetStencilCompareMask(
            cast(command_buffer).handle,
            conv.toVkStencilFaceFlags(stencil_face),
            mask,
        );
    }

    pub fn setStencilWriteMask(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        mask: u32,
    ) void {
        Device.cast(device).vkCmdSetStencilWriteMask(
            cast(command_buffer).handle,
            conv.toVkStencilFaceFlags(stencil_face),
            mask,
        );
    }

    pub fn setStencilReference(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        reference: u32,
    ) void {
        Device.cast(device).vkCmdSetStencilReference(
            cast(command_buffer).handle,
            conv.toVkStencilFaceFlags(stencil_face),
            reference,
        );
    }

    pub fn setColorBlendEnable(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        enable: []const bool,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.color_blend_enable.set(first_attachment, enable)
        else {
            _ = allocator;
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setColorBlend(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        blend: []const ngl.Cmd.Blend,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.color_blend.set(first_attachment, blend)
        else {
            _ = allocator;
            _ = device;
            @panic("Not yet implemented");
        }
    }

    pub fn setColorWrite(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        write_masks: []const ngl.Cmd.ColorMask,
    ) void {
        const cmd_buf = cast(command_buffer);

        if (cmd_buf.dyn) |d|
            d.state.color_write.set(first_attachment, write_masks)
        else {
            _ = allocator;
            _ = device;
            @panic("Not yet implemented");
        }
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
        render_pass_begin: ngl.Cmd.RenderPassBegin,
        subpass_begin: ngl.Cmd.SubpassBegin,
    ) void {
        const n = 16;
        var stk_clears: [n]c.VkClearValue = undefined;
        const clears = if (render_pass_begin.clear_values.len > n) allocator.alloc(
            c.VkClearValue,
            render_pass_begin.clear_values.len,
        ) catch {
            // TODO: Handle this somehow.
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
        next_begin: ngl.Cmd.SubpassBegin,
        _: ngl.Cmd.SubpassEnd,
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
        _: ngl.Cmd.SubpassEnd,
    ) void {
        Device.cast(device).vkCmdEndRenderPass(cast(command_buffer).handle);
    }

    pub fn beginRendering(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        rendering: ngl.Cmd.Rendering,
    ) void {
        const dev = Device.cast(device);
        const cmd_buf = cast(command_buffer);

        if (dev.hasDynamicRendering()) {
            if (cmd_buf.dyn) |d| d.rendering.set(rendering);
            // TODO...
            @panic("Not yet implemented");
        } else {
            const d = cmd_buf.dyn.?;
            d.rendering.set(rendering);
            const rp = dev.cache.getRenderPass(dev.gpa, dev, d.rendering) catch |err| {
                d.err = err;
                return;
            };
            if (d.fbo != null_handle) unreachable;
            d.fbo = Cache.createFramebuffer(dev.gpa, dev, d.rendering, rp) catch |err| {
                d.err = err;
                return;
            };

            // TODO: Make `Cache.createRenderPass/createFramebuffer`
            // put resolves at the end so this can be reduced.
            const max_clear = ngl.Cmd.max_color_attachment * 2 + 1;
            var clears: [max_clear]c.VkClearValue = undefined;
            var clear_i: u32 = 0;
            var clear_n: u32 = 0;
            for (rendering.colors) |col| {
                if (col.clear_value) |val| {
                    clears[clear_i] = conv.toVkClearValue(val);
                    clear_n = clear_i + 1;
                } else clears[clear_i] = .{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } };
                clear_i += 1;
                if (col.resolve) |_| {
                    clears[clear_i] = .{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } };
                    clear_i += 1;
                }
            }
            const dep_val = if (rendering.depth) |dep|
                if (dep.clear_value) |val|
                    val.depth_stencil[0]
                else
                    null
            else
                null;
            const sten_val = if (rendering.stencil) |sten|
                if (sten.clear_value) |val|
                    val.depth_stencil[1]
                else
                    null
            else
                null;
            if (dep_val != null or sten_val != null) {
                clears[clear_i] = .{
                    .depthStencil = .{
                        .depth = dep_val orelse 0,
                        .stencil = sten_val orelse 0,
                    },
                };
                clear_i += 1;
                clear_n = clear_i;
            }

            dev.vkCmdBeginRenderPass(
                cmd_buf.handle,
                &.{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                    .pNext = null,
                    .renderPass = rp,
                    .framebuffer = d.fbo,
                    .renderArea = .{
                        .offset = .{
                            .x = @min(rendering.render_area.x, std.math.maxInt(i32)),
                            .y = @min(rendering.render_area.y, std.math.maxInt(i32)),
                        },
                        .extent = .{
                            .width = rendering.render_area.width,
                            .height = rendering.render_area.height,
                        },
                    },
                    .clearValueCount = clear_n,
                    .pClearValues = if (clear_n > 0) &clears else null,
                },
                c.VK_SUBPASS_CONTENTS_INLINE, // TODO
            );
        }
    }

    pub fn endRendering(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
    ) void {
        const dev = Device.cast(device);
        const cmd_buf = cast(command_buffer);

        if (dev.hasDynamicRendering()) {
            if (cmd_buf.dyn) |d| d.rendering.clear(null);
            // TODO...
            @panic("Not yet implemented");
        } else {
            const d = cmd_buf.dyn.?;
            d.rendering.clear(null);
            dev.vkCmdEndRenderPass(cmd_buf.handle);
            dev.vkDestroyFramebuffer(d.fbo, null);
            d.fbo = null_handle;
        }
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

    pub fn clearBuffer(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        buffer: Impl.Buffer,
        offset: u64,
        size: ?u64,
        value: u8,
    ) void {
        const val32 =
            @as(u32, value) |
            @as(u32, value) << 8 |
            @as(u32, value) << 16 |
            @as(u32, value) << 24;

        Device.cast(device).vkCmdFillBuffer(
            cast(command_buffer).handle,
            Buffer.cast(buffer).handle,
            offset,
            size orelse c.VK_WHOLE_SIZE,
            val32,
        );
    }

    pub fn copyBuffer(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        copies: []const ngl.Cmd.BufferCopy,
    ) void {
        var region: [1]c.VkBufferCopy = undefined;
        var regions: []c.VkBufferCopy = &region;
        defer if (regions.len > 1) allocator.free(regions);

        for (copies) |x| {
            // We need to copy this many regions.
            const n = x.regions.len;

            if (n > regions.len) {
                if (regions.len == 1) {
                    if (allocator.alloc(c.VkBufferCopy, n)) |new| {
                        regions = new;
                    } else |_| {}
                } else {
                    if (allocator.realloc(regions, n)) |new| {
                        regions = new;
                    } else |_| {}
                }
            }

            // We can copy this many regions per call.
            const max = regions.len;

            var i: usize = 0;
            while (i < n) : (i += max) {
                for (0..@min(n - i, max)) |j|
                    regions[j] = .{
                        .srcOffset = x.regions[i + j].source_offset,
                        .dstOffset = x.regions[i + j].dest_offset,
                        .size = x.regions[i + j].size,
                    };
                Device.cast(device).vkCmdCopyBuffer(
                    cast(command_buffer).handle,
                    Buffer.cast(x.source.impl).handle,
                    Buffer.cast(x.dest.impl).handle,
                    @intCast(@min(n - i, max)),
                    regions.ptr,
                );
            }
        }
    }

    pub fn copyImage(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        copies: []const ngl.Cmd.ImageCopy,
    ) void {
        var region: [1]c.VkImageCopy = undefined;
        var regions: []c.VkImageCopy = &region;
        defer if (regions.len > 1) allocator.free(regions);

        for (copies) |x| {
            // We need to copy this many regions.
            const n = x.regions.len;

            if (n > regions.len) {
                if (regions.len == 1) {
                    if (allocator.alloc(c.VkImageCopy, n)) |new| {
                        regions = new;
                    } else |_| {}
                } else {
                    if (allocator.realloc(regions, n)) |new| {
                        regions = new;
                    } else |_| {}
                }
            }

            // We can copy this many regions per call.
            const max = regions.len;

            // TODO: Check that the compiler is generating a
            // separate path for 3D images.
            const source_3d = x.source.type == .@"3d";
            const dest_3d = x.dest.type == .@"3d";

            var i: usize = 0;
            while (i < n) : (i += max) {
                for (0..@min(n - i, max)) |j| {
                    const r = &x.regions[i + j];
                    regions[j] = .{
                        .srcSubresource = .{
                            .aspectMask = conv.toVkImageAspect(r.source_aspect),
                            .mipLevel = r.source_level,
                            .baseArrayLayer = if (source_3d) 0 else r.source_z_or_layer,
                            .layerCount = if (source_3d) 1 else r.depth_or_layers,
                        },
                        .srcOffset = .{
                            .x = @min(r.source_x, std.math.maxInt(i32)),
                            .y = @min(r.source_y, std.math.maxInt(i32)),
                            .z = if (source_3d)
                                @min(r.source_z_or_layer, std.math.maxInt(i32))
                            else
                                0,
                        },
                        .dstSubresource = .{
                            .aspectMask = conv.toVkImageAspect(r.dest_aspect),
                            .mipLevel = r.dest_level,
                            .baseArrayLayer = if (dest_3d) 0 else r.dest_z_or_layer,
                            .layerCount = if (dest_3d) 1 else r.depth_or_layers,
                        },
                        .dstOffset = .{
                            .x = @min(r.dest_x, std.math.maxInt(i32)),
                            .y = @min(r.dest_y, std.math.maxInt(i32)),
                            .z = if (dest_3d)
                                @min(r.dest_z_or_layer, std.math.maxInt(i32))
                            else
                                0,
                        },
                        .extent = .{
                            .width = r.width,
                            .height = r.height,
                            .depth = if (source_3d or dest_3d) r.depth_or_layers else 1,
                        },
                    };
                }
                Device.cast(device).vkCmdCopyImage(
                    cast(command_buffer).handle,
                    Image.cast(x.source.impl).handle,
                    conv.toVkImageLayout(x.source_layout),
                    Image.cast(x.dest.impl).handle,
                    conv.toVkImageLayout(x.dest_layout),
                    @intCast(@min(n - i, max)),
                    regions.ptr,
                );
            }
        }
    }

    fn copyBufferToImageOrImageToBuffer(
        comptime call: enum { bufferToImage, imageToBuffer },
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        copies: []const ngl.Cmd.BufferImageCopy,
    ) void {
        var region: [1]c.VkBufferImageCopy = undefined;
        var regions: []c.VkBufferImageCopy = &region;
        defer if (regions.len > 1) allocator.free(regions);

        for (copies) |x| {
            // We need to copy this many regions.
            const n = x.regions.len;

            if (n > regions.len) {
                if (regions.len == 1) {
                    if (allocator.alloc(c.VkBufferImageCopy, n)) |new| {
                        regions = new;
                    } else |_| {}
                } else {
                    if (allocator.realloc(regions, n)) |new| {
                        regions = new;
                    } else |_| {}
                }
            }

            // We can copy this many regions per call.
            const max = regions.len;

            // TODO: Check that the compiler is generating a
            // separate path for 3D images.
            const is_3d = x.image.type == .@"3d";

            var i: usize = 0;
            while (i < n) : (i += max) {
                for (0..@min(n - i, max)) |j| {
                    const r = &x.regions[i + j];
                    regions[j] = .{
                        .bufferOffset = r.buffer_offset,
                        .bufferRowLength = r.buffer_row_length,
                        .bufferImageHeight = r.buffer_image_height,
                        .imageSubresource = .{
                            .aspectMask = conv.toVkImageAspect(r.image_aspect),
                            .mipLevel = r.image_level,
                            .baseArrayLayer = if (is_3d) 0 else r.image_z_or_layer,
                            .layerCount = if (is_3d) 1 else r.image_depth_or_layers,
                        },
                        .imageOffset = .{
                            .x = @min(r.image_x, std.math.maxInt(i32)),
                            .y = @min(r.image_y, std.math.maxInt(i32)),
                            .z = if (is_3d) @min(r.image_z_or_layer, std.math.maxInt(i32)) else 0,
                        },
                        .imageExtent = .{
                            .width = r.image_width,
                            .height = r.image_height,
                            .depth = if (is_3d) r.image_depth_or_layers else 1,
                        },
                    };
                }
                switch (call) {
                    .bufferToImage => Device.cast(device).vkCmdCopyBufferToImage(
                        cast(command_buffer).handle,
                        Buffer.cast(x.buffer.impl).handle,
                        Image.cast(x.image.impl).handle,
                        conv.toVkImageLayout(x.image_layout),
                        @intCast(@min(n - i, max)),
                        regions.ptr,
                    ),
                    .imageToBuffer => Device.cast(device).vkCmdCopyImageToBuffer(
                        cast(command_buffer).handle,
                        Image.cast(x.image.impl).handle,
                        conv.toVkImageLayout(x.image_layout),
                        Buffer.cast(x.buffer.impl).handle,
                        @intCast(@min(n - i, max)),
                        regions.ptr,
                    ),
                }
            }
        }
    }

    pub fn copyBufferToImage(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        copies: []const ngl.Cmd.BufferImageCopy,
    ) void {
        copyBufferToImageOrImageToBuffer(.bufferToImage, allocator, device, command_buffer, copies);
    }

    pub fn copyImageToBuffer(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        copies: []const ngl.Cmd.BufferImageCopy,
    ) void {
        copyBufferToImageOrImageToBuffer(.imageToBuffer, allocator, device, command_buffer, copies);
    }

    pub fn resetQueryPool(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        query_pool: Impl.QueryPool,
        first_query: u32,
        query_count: u32,
    ) void {
        Device.cast(device).vkCmdResetQueryPool(
            cast(command_buffer).handle,
            QueryPool.cast(query_pool).handle,
            first_query,
            query_count,
        );
    }

    pub fn beginQuery(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        _: ngl.QueryType,
        query_pool: Impl.QueryPool,
        query: u32,
        control: ngl.Cmd.QueryControl,
    ) void {
        Device.cast(device).vkCmdBeginQuery(
            cast(command_buffer).handle,
            QueryPool.cast(query_pool).handle,
            query,
            // This assumes that `control.precise` will only be set to
            // `true` for occlusion queries.
            if (control.precise) c.VK_QUERY_CONTROL_PRECISE_BIT else 0,
        );
    }

    pub fn endQuery(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        _: ngl.QueryType,
        query_pool: Impl.QueryPool,
        query: u32,
    ) void {
        Device.cast(device).vkCmdEndQuery(
            cast(command_buffer).handle,
            QueryPool.cast(query_pool).handle,
            query,
        );
    }

    pub fn writeTimestamp(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        stage: ngl.Stage,
        query_pool: Impl.QueryPool,
        query: u32,
    ) void {
        Device.cast(device).vkCmdWriteTimestamp(
            cast(command_buffer).handle,
            conv.toVkPipelineStage(.source, stage),
            QueryPool.cast(query_pool).handle,
            query,
        );
    }

    pub fn copyQueryPoolResults(
        _: *anyopaque,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        query_type: ngl.QueryType,
        query_pool: Impl.QueryPool,
        first_query: u32,
        query_count: u32,
        dest: Impl.Buffer,
        dest_offset: u64,
        result: ngl.Cmd.QueryResult,
    ) void {
        const stride = getQueryLayout(
            undefined,
            device, //undefined,
            query_type,
            1,
            result.with_availability,
        ).size;

        const flags = blk: {
            var flags: c.VkQueryResultFlags = c.VK_QUERY_RESULT_64_BIT;
            if (result.wait)
                flags |= c.VK_QUERY_RESULT_WAIT_BIT;
            if (result.with_availability)
                flags |= c.VK_QUERY_RESULT_WITH_AVAILABILITY_BIT;
            break :blk flags;
        };

        Device.cast(device).vkCmdCopyQueryPoolResults(
            cast(command_buffer).handle,
            QueryPool.cast(query_pool).handle,
            first_query,
            query_count,
            Buffer.cast(dest).handle,
            dest_offset,
            stride,
            flags,
        );
    }

    pub fn pipelineBarrier(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        dependencies: []const ngl.Cmd.Dependency,
    ) void {
        const dev = Device.cast(device);
        const cmd_buf = cast(command_buffer);

        // TODO: Need synchronization2 to implement this efficiently.
        if (true) {
            for (dependencies) |x| {
                const depend_flags: c.VkDependencyFlags = if (x.by_region)
                    c.VK_DEPENDENCY_BY_REGION_BIT
                else
                    0;
                for (x.global_dependencies) |d|
                    dev.vkCmdPipelineBarrier(
                        cmd_buf.handle,
                        conv.toVkPipelineStageFlags(.source, d.source_stage_mask),
                        conv.toVkPipelineStageFlags(.dest, d.dest_stage_mask),
                        depend_flags,
                        1,
                        &[1]c.VkMemoryBarrier{.{
                            .sType = c.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
                            .pNext = null,
                            .srcAccessMask = conv.toVkAccessFlags(d.source_access_mask),
                            .dstAccessMask = conv.toVkAccessFlags(d.dest_access_mask),
                        }},
                        0,
                        null,
                        0,
                        null,
                    );
                for (x.buffer_dependencies) |d|
                    dev.vkCmdPipelineBarrier(
                        cmd_buf.handle,
                        conv.toVkPipelineStageFlags(.source, d.source_stage_mask),
                        conv.toVkPipelineStageFlags(.dest, d.dest_stage_mask),
                        depend_flags,
                        0,
                        null,
                        1,
                        &[1]c.VkBufferMemoryBarrier{.{
                            .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                            .pNext = null,
                            .srcAccessMask = conv.toVkAccessFlags(d.source_access_mask),
                            .dstAccessMask = conv.toVkAccessFlags(d.dest_access_mask),
                            .srcQueueFamilyIndex = if (d.queue_transfer) |t|
                                Queue.cast(t.source.impl).family
                            else
                                c.VK_QUEUE_FAMILY_IGNORED,
                            .dstQueueFamilyIndex = if (d.queue_transfer) |t|
                                Queue.cast(t.dest.impl).family
                            else
                                c.VK_QUEUE_FAMILY_IGNORED,
                            .buffer = Buffer.cast(d.buffer.impl).handle,
                            .offset = d.offset,
                            .size = d.size orelse c.VK_WHOLE_SIZE,
                        }},
                        0,
                        null,
                    );
                for (x.image_dependencies) |d|
                    dev.vkCmdPipelineBarrier(
                        cmd_buf.handle,
                        conv.toVkPipelineStageFlags(.source, d.source_stage_mask),
                        conv.toVkPipelineStageFlags(.dest, d.dest_stage_mask),
                        depend_flags,
                        0,
                        null,
                        0,
                        null,
                        1,
                        &[1]c.VkImageMemoryBarrier{.{
                            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                            .pNext = null,
                            .srcAccessMask = conv.toVkAccessFlags(d.source_access_mask),
                            .dstAccessMask = conv.toVkAccessFlags(d.dest_access_mask),
                            .oldLayout = conv.toVkImageLayout(d.old_layout),
                            .newLayout = conv.toVkImageLayout(d.new_layout),
                            .srcQueueFamilyIndex = if (d.queue_transfer) |t|
                                Queue.cast(t.source.impl).family
                            else
                                c.VK_QUEUE_FAMILY_IGNORED,
                            .dstQueueFamilyIndex = if (d.queue_transfer) |t|
                                Queue.cast(t.dest.impl).family
                            else
                                c.VK_QUEUE_FAMILY_IGNORED,
                            .image = Image.cast(d.image.impl).handle,
                            .subresourceRange = .{
                                .aspectMask = conv.toVkImageAspectFlags(d.range.aspect_mask),
                                .baseMipLevel = d.range.level,
                                .levelCount = d.range.levels,
                                .baseArrayLayer = d.range.layer,
                                .layerCount = d.range.layers,
                            },
                        }},
                    );
            }
        } else {
            var mem_barrier: [1]c.VkMemoryBarrier2 = undefined;
            var buf_barrier: [1]c.VkBufferMemoryBarrier2 = undefined;
            var img_barrier: [1]c.VkImageMemoryBarrier2 = undefined;
            var mem_barriers: []c.VkMemoryBarrier2 = &mem_barrier;
            var buf_barriers: []c.VkBufferMemoryBarrier2 = &buf_barrier;
            var img_barriers: []c.VkImageMemoryBarrier2 = &img_barrier;
            defer {
                if (mem_barriers.len > 1) allocator.free(mem_barriers);
                if (buf_barriers.len > 1) allocator.free(buf_barriers);
                if (img_barriers.len > 1) allocator.free(img_barriers);
            }

            for (dependencies) |x| {
                const mem_n = x.global_dependencies.len;
                const buf_n = x.buffer_dependencies.len;
                const img_n = x.image_dependencies.len;

                if (mem_n > mem_barriers.len) {
                    if (mem_barriers.len == 1) {
                        if (allocator.alloc(c.VkMemoryBarrier2, mem_n)) |new| {
                            mem_barriers = new;
                        } else |_| {}
                    } else {
                        if (allocator.realloc(mem_barriers, mem_n)) |new| {
                            mem_barriers = new;
                        } else |_| {}
                    }
                }
                if (buf_n > buf_barriers.len) {
                    if (buf_barriers.len == 1) {
                        if (allocator.alloc(c.VkBufferMemoryBarrier2, buf_n)) |new| {
                            buf_barriers = new;
                        } else |_| {}
                    } else {
                        if (allocator.realloc(buf_barriers, buf_n)) |new| {
                            buf_barriers = new;
                        } else |_| {}
                    }
                }
                if (img_n > img_barriers.len) {
                    if (img_barriers.len == 1) {
                        if (allocator.alloc(c.VkImageMemoryBarrier2, img_n)) |new| {
                            img_barriers = new;
                        } else |_| {}
                    } else {
                        if (allocator.realloc(img_barriers, img_n)) |new| {
                            img_barriers = new;
                        } else |_| {}
                    }
                }

                const mem_max = mem_barriers.len;
                const buf_max = buf_barriers.len;
                const img_max = img_barriers.len;

                var mem_i: usize = 0;
                var buf_i: usize = 0;
                var img_i: usize = 0;
                while (mem_i < mem_n or buf_i < buf_n or img_i < img_n) {
                    for (0..@min(mem_n -| mem_i, mem_max)) |j| {
                        const d = &x.global_dependencies[mem_i + j];
                        // TODO
                        _ = d;
                    }
                    for (0..@min(buf_n -| buf_i, buf_max)) |j| {
                        const d = &x.buffer_dependencies[buf_i + j];
                        // TODO
                        _ = d;
                    }
                    for (0..@min(img_n -| img_i, img_max)) |j| {
                        const d = &x.image_dependencies[img_i + j];
                        // TODO
                        _ = d;
                    }
                    // TODO: Call `vkCmdPipelineBarrier2`.
                    // Maybe try to fill more `VkDependencyInfo`s.
                    mem_i += mem_max;
                    buf_i += buf_max;
                    img_i += img_max;
                }
            }
        }
    }

    pub fn executeCommands(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
        secondary_command_buffers: []const *ngl.CommandBuffer,
    ) void {
        // Ideally, this would be the number of available cores,
        // but such value isn't known at compile time.
        const n = if (builtin.single_threaded) 1 else 16;
        var stk_cmd_bufs: [n]c.VkCommandBuffer = undefined;
        const cmd_bufs = if (secondary_command_buffers.len > n) allocator.alloc(
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
        try check(Device.cast(device).vkEndCommandBuffer(cast(command_buffer).handle));
    }
};

pub const Dynamic = struct {
    state: dyn.State(state_mask),
    rendering: dyn.Rendering(rendering_mask),
    fbo: c.VkFramebuffer,
    err: ?Error,

    pub const state_mask = dyn.StateMask(.primitive){
        .shaders = true,
        .vertex_input = true,
        .primitive_topology = true,
        .rasterization_enable = true,
        .polygon_mode = true,
        .cull_mode = true,
        .front_face = true,
        .sample_count = true,
        .sample_mask = true,
        .depth_bias_enable = true,
        .depth_test_enable = true,
        .depth_compare_op = true,
        .depth_write_enable = true,
        .stencil_test_enable = true,
        .stencil_op = true,
        .color_blend_enable = true,
        .color_blend = true,
        .color_write = true,
    };

    // Note that this is the union of render pass and
    // framebuffer requirements.
    pub const rendering_mask = dyn.RenderingMask{
        .color_view = true,
        .color_format = true,
        .color_samples = true,
        .color_layout = true,
        .color_op = true,
        .color_resolve_view = true,
        .color_resolve_layout = true,
        .color_resolve_mode = true,
        .depth_view = true,
        .depth_format = true,
        .depth_samples = true,
        .depth_layout = true,
        .depth_op = true,
        .depth_resolve_view = true,
        .depth_resolve_layout = true,
        .depth_resolve_mode = true,
        .stencil_view = true,
        .stencil_format = true,
        .stencil_samples = true,
        .stencil_layout = true,
        .stencil_op = true,
        .stencil_resolve_view = true,
        .stencil_resolve_layout = true,
        .stencil_resolve_mode = true,
        .render_area_size = true,
        .layers = true,
        .view_mask = true,
    };

    pub fn init() @This() {
        var self: @This() = undefined;
        self.state = @TypeOf(self.state).init();
        self.rendering = @TypeOf(self.rendering).init();
        self.fbo = null_handle;
        self.err = null;
        return self;
    }

    pub fn clear(self: *@This(), allocator: ?std.mem.Allocator, device: *Device) void {
        self.state.clear(allocator);
        self.rendering.clear(allocator);
        device.vkDestroyFramebuffer(self.fbo, null);
        self.fbo = null_handle;
        self.err = null;
    }
};

const testing = std.testing;
const context = @import("../../test/test.zig").context;

test CommandPool {
    const ctx = context();
    const dev = ctx.device.impl;
    const queue = &ctx.device.queues[0];

    const cmd_pool = try CommandPool.init(undefined, testing.allocator, dev, .{ .queue = queue });
    defer CommandPool.deinit(undefined, testing.allocator, dev, cmd_pool);

    var cmd_bufs = [_]ngl.CommandBuffer{.{ .impl = .{ .val = 0 } }} ** 5;

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 1 },
        cmd_bufs[0..1],
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 1);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 0);

    CommandPool.free(undefined, testing.allocator, dev, cmd_pool, &.{&cmd_bufs[0]});
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 1);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 1);

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 2 },
        cmd_bufs[0..2],
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 2);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 0);

    CommandPool.free(undefined, testing.allocator, dev, cmd_pool, &.{&cmd_bufs[0]});
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 2);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 1);

    try CommandPool.reset(undefined, dev, cmd_pool, .release);

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 1 },
        cmd_bufs[0..1],
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 2);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 0);

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 3 },
        cmd_bufs[2..5],
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 5);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 0);

    for (&cmd_bufs, 0..) |*x, i| {
        CommandPool.free(undefined, testing.allocator, dev, cmd_pool, &.{x});
        try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == cmd_bufs.len);
        try testing.expect(CommandPool.cast(cmd_pool).unused.count() == i + 1);
    }

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 4 },
        cmd_bufs[1..],
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 5);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 1);

    CommandPool.free(undefined, testing.allocator, dev, cmd_pool, &.{ &cmd_bufs[1], &cmd_bufs[3] });
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 5);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 3);

    try CommandPool.reset(undefined, dev, cmd_pool, .release);

    CommandPool.free(undefined, testing.allocator, dev, cmd_pool, &.{ &cmd_bufs[4], &cmd_bufs[2] });
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 5);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 5);

    try CommandPool.alloc(
        undefined,
        testing.allocator,
        dev,
        cmd_pool,
        .{ .level = .primary, .count = 5 },
        &cmd_bufs,
    );
    try testing.expect(CommandPool.cast(cmd_pool).allocs.items.len == 5);
    try testing.expect(CommandPool.cast(cmd_pool).unused.count() == 0);

    outer: for (cmd_bufs) |x| {
        for (CommandPool.cast(cmd_pool).allocs.items) |y|
            if (CommandBuffer.cast(x.impl) == y) continue :outer;
        try testing.expect(false);
    }

    try CommandPool.reset(undefined, dev, cmd_pool, .keep);
    try CommandPool.reset(undefined, dev, cmd_pool, .release);
}

test CommandBuffer {
    const ctx = context();
    const dev = ctx.device.impl;
    const queue = &ctx.device.queues[
        ctx.device.findQueue(
            .{ .graphics = true, .compute = true },
            null,
        ) orelse return error.SkipZigTest
    ];

    const cmd_pool = try CommandPool.init(undefined, testing.allocator, dev, .{ .queue = queue });
    defer CommandPool.deinit(undefined, testing.allocator, dev, cmd_pool);

    const cmd_buf = blk: {
        var dest = [1]ngl.CommandBuffer{.{ .impl = .{ .val = 0 } }};
        try CommandPool.alloc(
            undefined,
            testing.allocator,
            dev,
            cmd_pool,
            .{ .level = .primary, .count = 1 },
            &dest,
        );
        break :blk dest[0].impl;
    };

    if (Device.cast(dev).isFullyDynamic()) {
        try testing.expect(CommandBuffer.cast(cmd_buf).dyn == null);
        // Nothing else to test here; rely on the generic tests
        // for correctness.
        return error.SkipZigTest;
    }
    const d = CommandBuffer.cast(cmd_buf).dyn.?;

    try CommandBuffer.begin(
        undefined,
        testing.allocator,
        dev,
        cmd_buf,
        .{ .one_time_submit = true, .inheritance = null },
    );

    var shds = [2]ngl.Shader{ .{ .impl = .{ .val = 1 } }, .{ .impl = .{ .val = 2 } } };
    const prev_shds = d.state.shaders;
    CommandBuffer.setShaders(
        undefined,
        testing.allocator,
        dev,
        cmd_buf,
        &.{ .vertex, .fragment },
        &.{ &shds[0], &shds[1] },
    );
    try testing.expect(!prev_shds.eql(d.state.shaders));

    // Won't leak.
    const prev_vert_in = @TypeOf(d.state.vertex_input){
        .bindings = try d.state.vertex_input.bindings.clone(testing.allocator),
        .attributes = try d.state.vertex_input.attributes.clone(testing.allocator),
    };
    CommandBuffer.setVertexInput(
        undefined,
        testing.allocator,
        dev,
        cmd_buf,
        &.{
            .{ .binding = 0, .stride = 16, .step_rate = .vertex },
            .{ .binding = 1, .stride = 4, .step_rate = .{ .instance = 1 } },
        },
        &.{
            .{ .location = 0, .binding = 0, .format = .rgba32_sfloat, .offset = 0 },
            .{ .location = 1, .binding = 1, .format = .r32_uint, .offset = 0 },
        },
    );
    try testing.expect(!prev_vert_in.eql(d.state.vertex_input));

    const prev_prim_top = d.state.primitive_topology;
    CommandBuffer.setPrimitiveTopology(undefined, dev, cmd_buf, .line_list);
    try testing.expect(!prev_prim_top.eql(d.state.primitive_topology));

    const prev_raster_enable = d.state.rasterization_enable;
    CommandBuffer.setRasterizationEnable(undefined, dev, cmd_buf, false);
    try testing.expect(!prev_raster_enable.eql(d.state.rasterization_enable));

    const prev_poly_mode = d.state.polygon_mode;
    CommandBuffer.setPolygonMode(undefined, dev, cmd_buf, .line);
    try testing.expect(!prev_poly_mode.eql(d.state.polygon_mode));

    const prev_cull_mode = d.state.cull_mode;
    CommandBuffer.setCullMode(undefined, dev, cmd_buf, .front);
    try testing.expect(!prev_cull_mode.eql(d.state.cull_mode));

    const prev_front_face = d.state.front_face;
    CommandBuffer.setFrontFace(undefined, dev, cmd_buf, .counter_clockwise);
    try testing.expect(!prev_front_face.eql(d.state.front_face));

    const prev_spl_cnt = d.state.sample_count;
    CommandBuffer.setSampleCount(undefined, dev, cmd_buf, .@"4");
    try testing.expect(!prev_spl_cnt.eql(d.state.sample_count));

    const prev_spl_mask = d.state.sample_mask;
    CommandBuffer.setSampleMask(undefined, dev, cmd_buf, 0xf);
    try testing.expect(!prev_spl_mask.eql(d.state.sample_mask));

    const prev_dep_bias_enable = d.state.depth_bias_enable;
    CommandBuffer.setDepthBiasEnable(undefined, dev, cmd_buf, true);
    try testing.expect(!prev_dep_bias_enable.eql(d.state.depth_bias_enable));

    const prev_dep_test_enable = d.state.depth_test_enable;
    CommandBuffer.setDepthTestEnable(undefined, dev, cmd_buf, true);
    try testing.expect(!prev_dep_test_enable.eql(d.state.depth_test_enable));

    const prev_dep_cmp_op = d.state.depth_compare_op;
    CommandBuffer.setDepthCompareOp(undefined, dev, cmd_buf, .equal);
    try testing.expect(!prev_dep_cmp_op.eql(d.state.depth_compare_op));

    const prev_dep_write_enable = d.state.depth_write_enable;
    CommandBuffer.setDepthWriteEnable(undefined, dev, cmd_buf, true);
    try testing.expect(!prev_dep_write_enable.eql(d.state.depth_write_enable));

    const prev_sten_test_enable = d.state.stencil_test_enable;
    CommandBuffer.setStencilTestEnable(undefined, dev, cmd_buf, true);
    try testing.expect(!prev_sten_test_enable.eql(d.state.stencil_test_enable));

    const prev_sten_op = d.state.stencil_op;
    CommandBuffer.setStencilOp(undefined, dev, cmd_buf, .back, .keep, .zero, .replace, .less);
    try testing.expect(!prev_sten_op.eql(d.state.stencil_op));

    const prev_col_blend_enable = d.state.color_blend_enable;
    CommandBuffer.setColorBlendEnable(
        undefined,
        testing.allocator,
        dev,
        cmd_buf,
        0,
        &.{ false, true },
    );
    try testing.expect(!prev_col_blend_enable.eql(d.state.color_blend_enable));

    const prev_col_blend = d.state.color_blend;
    CommandBuffer.setColorBlend(undefined, testing.allocator, dev, cmd_buf, 1, &.{.{
        .color_source_factor = .dest_color,
        .color_dest_factor = .zero,
        .color_op = .add,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .one_minus_source_alpha,
        .alpha_op = .add,
    }});
    try testing.expect(!prev_col_blend.eql(d.state.color_blend));

    const prev_col_write = d.state.color_write;
    CommandBuffer.setColorWrite(
        undefined,
        testing.allocator,
        dev,
        cmd_buf,
        0,
        &.{ .all, .{ .mask = .{ .r = true } } },
    );
    try testing.expect(!prev_col_write.eql(d.state.color_write));

    var image = try ngl.Image.init(testing.allocator, &ctx.device, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 1,
        .height = 1,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .color_attachment = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    defer image.deinit(testing.allocator, &ctx.device);
    var mem = blk: {
        const mem_reqs = image.getMemoryRequirements(&ctx.device);
        var mem = try (&ctx.device).alloc(testing.allocator, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(ctx.device, .{ .device_local = true }, null).?,
        });
        errdefer (&ctx.device).free(testing.allocator, &mem);
        try image.bind(&ctx.device, &mem, 0);
        break :blk mem;
    };
    defer (&ctx.device).free(testing.allocator, &mem);
    var view = try ngl.ImageView.init(testing.allocator, &ctx.device, .{
        .image = &image,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer view.deinit(testing.allocator, &ctx.device);

    const prev_rend = d.rendering;
    CommandBuffer.beginRendering(undefined, testing.allocator, dev, cmd_buf, .{
        .colors = &.{.{
            .view = &view,
            .layout = .color_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
            .resolve = null,
        }},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1, .height = 1 },
        .layers = 1,
    });
    try testing.expect(!prev_rend.eql(d.rendering));

    CommandBuffer.endRendering(undefined, dev, cmd_buf);
    try testing.expect(prev_rend.eql(d.rendering));
}
