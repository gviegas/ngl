const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.ShaderCode;

device: *Device,
inner: Inner,

pub const Config = struct {
    code: []const u8,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
