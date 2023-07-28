const Texture = @import("Texture.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.TexView;

texture: *Texture,
inner: Inner,
dimension: Dimension,
format: Texture.Format,
plane: u2,
first_level: u32,
levels: u32,
first_layer: u32,
layers: u32,

pub const Dimension = enum {
    @"1d",
    @"1d_array",
    @"2d",
    @"2d_array",
    cube,
    cube_array,
    @"3d",
};

pub const Config = struct {
    dimension: Dimension,
    format: Texture.Format,
    plane: u2 = 0,
    first_level: u32 = 0,
    levels: u32 = 1,
    first_layer: u32 = 0,
    layers: u32 = 1,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.texture.heap.device.impl;
}
