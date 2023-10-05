const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;

pub const Fence = struct {
    handle: c.VkFence,

    pub inline fn cast(impl: *Impl.Fence) *Fence {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.Fence.Desc,
    ) Error!*Impl.Fence {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Fence);
        errdefer allocator.destroy(ptr);

        var fence: c.VkFence = undefined;
        try conv.check(dev.vkCreateFence(&.{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = switch (desc.initial_status) {
                .unsignaled => 0,
                .signaled => @as(c.VkFlags, c.VK_FENCE_CREATE_SIGNALED_BIT),
            },
        }, null, &fence));

        ptr.* = .{ .handle = fence };
        return @ptrCast(ptr);
    }

    pub fn reset(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        fences: []const *ngl.Fence,
    ) Error!void {
        var fnc: [1]c.VkFence = undefined;
        var fncs = if (fences.len > 1) try allocator.alloc(c.VkFence, fences.len) else &fnc;
        defer if (fncs.len > 1) allocator.free(fncs);

        for (fncs, fences) |*handle, fence|
            handle.* = cast(fence.impl).handle;

        return conv.check(Device.cast(device).vkResetFences(@intCast(fncs.len), fncs.ptr));
    }

    pub fn wait(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        timeout: u64,
        fences: []const *ngl.Fence,
    ) Error!void {
        var fnc: [1]c.VkFence = undefined;
        var fncs = if (fences.len > 1) try allocator.alloc(c.VkFence, fences.len) else &fnc;
        defer if (fncs.len > 1) allocator.free(fncs);

        for (fncs, fences) |*handle, fence|
            handle.* = cast(fence.impl).handle;

        return conv.check(Device.cast(device).vkWaitForFences(
            @intCast(fncs.len),
            fncs.ptr,
            c.VK_TRUE, // TODO: Maybe expose this
            timeout,
        ));
    }

    pub fn getStatus(
        _: *anyopaque,
        device: *Impl.Device,
        fence: *Impl.Fence,
    ) Error!ngl.Fence.Status {
        conv.check(Device.cast(device).vkGetFenceStatus(cast(fence).handle)) catch |err| {
            if (err == Error.NotReady) return .unsignaled;
            return err;
        };
        return .signaled;
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        fence: *Impl.Fence,
    ) void {
        const dev = Device.cast(device);
        const fnc = cast(fence);
        dev.vkDestroyFence(fnc.handle, null);
        allocator.destroy(fnc);
    }
};

pub const Semaphore = struct {
    handle: c.VkSemaphore,

    pub inline fn cast(impl: *Impl.Semaphore) *Semaphore {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        _: ngl.Semaphore.Desc,
    ) Error!*Impl.Semaphore {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Semaphore);
        errdefer allocator.destroy(ptr);

        var sema: c.VkSemaphore = undefined;
        try conv.check(dev.vkCreateSemaphore(&.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        }, null, &sema));

        ptr.* = .{ .handle = sema };
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        semaphore: *Impl.Semaphore,
    ) void {
        const dev = Device.cast(device);
        const sema = cast(semaphore);
        dev.vkDestroySemaphore(sema.handle, null);
        allocator.destroy(sema);
    }
};
