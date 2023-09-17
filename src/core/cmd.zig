const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Queue = ngl.Queue;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const CommandPool = struct {
    impl: *Impl.CommandPool,

    pub const Desc = struct {
        queue: *const Queue,
    };

    const Self = @This();

    pub fn init(device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initCommandPool(device.allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, device: *Device) void {
        Impl.get().deinitCommandPool(device.allocator, device.impl, self.impl);
    }
};
