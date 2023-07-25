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

pub fn init(texture: *Texture, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .texture = texture,
        .inner = try Inner.init(texture.*, texture.heap.device.allocator, config),
        .dimension = config.dimension,
        .format = config.format,
        .plane = config.plane,
        .first_level = config.first_level,
        .levels = config.levels,
        .first_layer = config.first_layer,
        .layers = config.layers,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.texture.heap.device.allocator);
    self.* = undefined;
}
