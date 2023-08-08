const Allocator = @import("std").mem.Allocator;

const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.CmdPool;
const CmdBuffer = @import("CmdBuffer.zig");
const Error = @import("main.zig").Error;

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

pub fn alloc(
    self: *Self,
    allocator: Allocator,
    n: u32,
    config: CmdBuffer.Config,
) Error![]CmdBuffer {
    // TODO: Validation.
    var cbufs = try allocator.alloc(CmdBuffer, n);
    errdefer allocator.free(cbufs);
    for (cbufs) |*cbuf| {
        cbuf.pool = self;
        cbuf.inner = undefined;
        cbuf.kind = config.kind;
    }
    try Inner.alloc(self.*, cbufs, config);
    return cbufs;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
