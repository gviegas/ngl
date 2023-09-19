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
        try conv.check(dev.vkCreateFence(&c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = if (desc.signaled) c.VK_FENCE_CREATE_SIGNALED_BIT else 0,
        }, null, &fence));

        ptr.* = .{ .handle = fence };
        return @ptrCast(ptr);
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
