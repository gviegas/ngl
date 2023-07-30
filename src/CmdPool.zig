const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.CmdPool;

device: *Device,
inner: Inner,
direct_count_hint: u32,
indirect_count_hint: u32,

pub const Config = struct {
    direct_count_hint: u32 = 1,
    indirect_count_hint: u32 = 0,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
