const Heap = @import("Heap.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.Buffer;

heap: *Heap,
inner: Inner,
offset: u64,
size: u64,
usage: Usage,

pub const Usage = struct {
    copy_src: bool = false,
    copy_dst: bool = false,
    storage: bool = false,
    uniform: bool = false,
    index: bool = false,
    vertex: bool = false,
    indirect: bool = false,
};

pub const Config = struct {
    offset: u64,
    size: u64,
    usage: Usage,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.heap.device.impl;
}
