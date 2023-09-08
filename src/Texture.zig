const Heap = @import("Heap.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.Texture;
const TexView = @import("TexView.zig");
const Error = @import("main.zig").Error;

heap: *Heap,
inner: Inner,
offset: u64,
dimension: Dimension,
format: Format,
width: u32,
height: u32,
depth_or_layers: u32,
levels: u32,
samples: u32,
usage: Usage,

pub const Dimension = enum {
    @"1d",
    @"2d",
    @"3d",
};

pub const Format = enum {
    rgba8_unorm,
    depth16_unorm,
    // TODO
};

pub const Usage = struct {
    copy_src: bool = false,
    copy_dest: bool = false,
    storage: bool = false,
    sampled: bool = false,
    attachment: bool = false,
};

pub const Config = struct {
    offset: u64,
    dimension: Dimension,
    format: Format,
    width: u32,
    height: u32,
    depth_or_layers: u32,
    levels: u32 = 1,
    samples: u32 = 1,
    usage: Usage,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn initView(self: *Self, config: TexView.Config) Error!TexView {
    // TODO: Validation.
    return .{
        .texture = self,
        .inner = try Inner.initView(self.*, config),
        .dimension = config.dimension,
        .format = config.format,
        .plane = config.plane,
        .first_level = config.first_level,
        .levels = config.levels,
        .first_layer = config.first_layer,
        .layers = config.layers,
    };
}

pub fn impl(self: Self) *const Impl {
    return self.heap.device.impl;
}
