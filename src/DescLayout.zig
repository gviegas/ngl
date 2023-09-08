const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.DescLayout;

device: *Device,
inner: Inner,
entries: []Entry,

pub const Descriptor = enum {
    storage_buffer,
    uniform_buffer,
    storage_texture,
    sampled_texture,
    sampler,
    input_texture,
};

pub const Entry = struct {
    binding: u32,
    descriptor: Descriptor,
    count: u32,
    visibility: struct {
        vertex: bool = false,
        fragment: bool = false,
        compute: bool = false,
    },
};

pub const Config = struct {
    entries: []const Entry,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.impl().allocator.free(self.entries);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
