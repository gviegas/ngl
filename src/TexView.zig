const Texture = @import("Texture.zig");
const Inner = @import("Impl.zig").TexView;
const Error = @import("main.zig").Error;

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
    self.inner.deinit(self.*, self.texture.heap.device.allocator);
    self.* = undefined;
}
