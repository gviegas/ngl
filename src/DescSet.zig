const DescPool = @import("DescPool.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.DescSet;
const DescLayout = @import("DescLayout.zig");

pool: *DescPool,
inner: Inner,
// TODO: This needs to be ref-counted.
//layout: *DescLayout,

pub const Config = struct {
    layout: *DescLayout,
    count: u32 = 1,
};

const Self = @This();

pub fn free(self: *Self) void {
    self.inner.free(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.pool.device.impl;
}
