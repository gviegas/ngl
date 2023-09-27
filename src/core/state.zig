const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Pipeline = struct {
    impl: *Impl.Pipeline,
    type: Type,

    pub const Type = enum {
        graphics,
        compute,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitPipeline(allocator, device.impl, self.impl, self.type);
        self.* = undefined;
    }
};
