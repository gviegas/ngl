const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.PsLayout;
const DescLayout = @import("DescLayout.zig");

device: *Device,
inner: Inner,

pub const Constant = struct {
    offset: u9,
    size: u9,
    visibility: struct {
        vertex: bool = false,
        fragment: bool = false,
        compute: bool = false,
    },
};

pub const Config = struct {
    desc_layouts: []const *DescLayout,
    constants: []const Constant,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
