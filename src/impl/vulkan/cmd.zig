const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;
const Queue = @import("init.zig").Queue;
const RenderPass = @import("pass.zig").RenderPass;
const FrameBuffer = @import("pass.zig").FrameBuffer;
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

    pub fn end(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        command_buffer: Impl.CommandBuffer,
    ) Error!void {
        return check(Device.cast(device).vkEndCommandBuffer(cast(command_buffer).handle));
    }
};
