const CmdPool = @import("CmdPool.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.CmdBuffer;

pool: *CmdPool,
inner: Inner,
kind: Kind,

pub const Kind = enum {
    direct,
    indirect,
};

pub const Config = struct {
    kind: Kind,
};

const Self = @This();

pub fn free(self: *Self) void {
    self.inner.free(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.pool.device.impl;
}
