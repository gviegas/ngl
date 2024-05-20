const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../../inc.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;

pub const Fence = packed struct {
    handle: c.VkFence,

    pub fn cast(impl: Impl.Fence) Fence {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Fence.Desc,
    ) Error!Impl.Fence {
        var fence: c.VkFence = undefined;
        try check(Device.cast(device).vkCreateFence(&.{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = switch (desc.status) {
                .unsignaled => 0,
                .signaled => @as(c.VkFlags, c.VK_FENCE_CREATE_SIGNALED_BIT),
            },
        }, null, &fence));

        return .{ .val = @bitCast(Fence{ .handle = fence }) };
    }

    pub fn reset(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        fences: []const *ngl.Fence,
    ) Error!void {
        var fnc: [1]c.VkFence = undefined;
        const fncs = if (fences.len > 1) try allocator.alloc(c.VkFence, fences.len) else &fnc;
        defer if (fncs.len > 1) allocator.free(fncs);

        for (fncs, fences) |*handle, fence|
            handle.* = cast(fence.impl).handle;

        try check(Device.cast(device).vkResetFences(@intCast(fncs.len), fncs.ptr));
    }

    pub fn wait(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        timeout: u64,
        fences: []const *ngl.Fence,
    ) Error!void {
        var fnc: [1]c.VkFence = undefined;
        const fncs = if (fences.len > 1) try allocator.alloc(c.VkFence, fences.len) else &fnc;
        defer if (fncs.len > 1) allocator.free(fncs);

        for (fncs, fences) |*handle, fence|
            handle.* = cast(fence.impl).handle;

        try check(Device.cast(device).vkWaitForFences(
            @intCast(fncs.len),
            fncs.ptr,
            c.VK_TRUE, // TODO: Maybe expose this.
            timeout,
        ));
    }

    pub fn getStatus(
        _: *anyopaque,
        device: Impl.Device,
        fence: Impl.Fence,
    ) Error!ngl.Fence.Status {
        check(Device.cast(device).vkGetFenceStatus(cast(fence).handle)) catch |err| {
            if (err == Error.NotReady) return .unsignaled;
            return err;
        };
        return .signaled;
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        fence: Impl.Fence,
    ) void {
        Device.cast(device).vkDestroyFence(cast(fence).handle, null);
    }
};

pub const Semaphore = packed struct {
    handle: c.VkSemaphore,

    pub fn cast(impl: Impl.Semaphore) Semaphore {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        _: ngl.Semaphore.Desc,
    ) Error!Impl.Semaphore {
        var sem: c.VkSemaphore = undefined;
        try check(Device.cast(device).vkCreateSemaphore(&.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        }, null, &sem));

        return .{ .val = @bitCast(Semaphore{ .handle = sem }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        semaphore: Impl.Semaphore,
    ) void {
        Device.cast(device).vkDestroySemaphore(cast(semaphore).handle, null);
    }
};
