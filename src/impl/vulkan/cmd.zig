const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;
const Queue = @import("init.zig").Queue;

pub const CommandPool = struct {
    handle: c.VkCommandPool,

    pub inline fn cast(impl: *Impl.CommandPool) *CommandPool {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.CommandPool.Desc,
    ) Error!*Impl.CommandPool {
        const dev = Device.cast(device);
        const queue = Queue.cast(Impl.Queue.cast(desc.queue));

        var ptr = try allocator.create(CommandPool);
        errdefer allocator.destroy(ptr);

        var cmd_pool: c.VkCommandPool = undefined;
        try conv.check(dev.vkCreateCommandPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0, // TODO: Maybe expose this
            .queueFamilyIndex = queue.family,
        }, null, &cmd_pool));

        ptr.* = .{ .handle = cmd_pool };
        return @ptrCast(ptr);
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        command_pool: *Impl.CommandPool,
        device: *Impl.Device,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void {
        const cmd_pool = cast(command_pool);
        const dev = Device.cast(device);

        var cmd_bufs = try allocator.alloc(c.VkCommandBuffer, desc.count);
        defer allocator.free(cmd_bufs);

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

        try conv.check(dev.vkAllocateCommandBuffers(&alloc_info, cmd_bufs.ptr));
        errdefer dev.vkFreeCommandBuffers(cmd_pool.handle, desc.count, cmd_bufs.ptr);

        for (cmd_bufs, 0..) |cb, i| {
            var ptr = allocator.create(CommandBuffer) catch |err| {
                for (0..i) |j| allocator.destroy(CommandBuffer.cast(command_buffers[j].impl));
                return err;
            };
            ptr.* = .{ .handle = cb };
            command_buffers[i].impl = @ptrCast(ptr);
        }
    }

    pub fn free(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        command_pool: *Impl.CommandPool,
        device: *Impl.Device,
        command_buffers: []const ngl.CommandBuffer,
    ) void {
        const cmd_pool = cast(command_pool);
        const dev = Device.cast(device);
        const n = command_buffers.len;

        var cmd_bufs = allocator.alloc(c.VkCommandBuffer, n) catch {
            for (command_buffers) |cb| {
                var ptr = CommandBuffer.cast(cb.impl);
                const h: *[1]c.VkCommandBuffer = &ptr.handle;
                dev.vkFreeCommandBuffers(cmd_pool.handle, 1, h);
                allocator.destroy(ptr);
            }
            return;
        };
        defer allocator.free(cmd_bufs);

        for (0..n) |i| {
            var ptr = CommandBuffer.cast(command_buffers[i].impl);
            cmd_bufs[i] = ptr.handle;
            allocator.destroy(ptr);
        }
        dev.vkFreeCommandBuffers(cmd_pool.handle, @intCast(n), cmd_bufs.ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        command_pool: *Impl.CommandPool,
    ) void {
        const dev = Device.cast(device);
        const cmd_pool = cast(command_pool);
        dev.vkDestroyCommandPool(cmd_pool.handle, null);
        allocator.destroy(cmd_pool);
    }
};

pub const CommandBuffer = struct {
    handle: c.VkCommandBuffer,

    pub inline fn cast(impl: *Impl.CommandBuffer) *CommandBuffer {
        return @ptrCast(@alignCast(impl));
    }
};
