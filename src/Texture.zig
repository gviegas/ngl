const Device = @import("Device.zig");
const Inner = @import("impl.zig").Texture;
const Error = @import("main.zig").Error;

device: *Device,
inner: Inner,
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
    copy_dst: bool = false,
    storage: bool = false,
    sampled: bool = false,
    attachment: bool = false,
};

pub const Config = struct {
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

pub fn init(device: *Device, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .device = device,
        .inner = try device.inner.initTexture(device.allocator, config),
        .dimension = config.dimension,
        .format = config.format,
        .width = config.width,
        .height = config.height,
        .depth_or_layers = config.depth_or_layers,
        .levels = config.levels,
        .samples = config.samples,
        .usage = config.usage,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.device.allocator, self.device.inner);
    self.* = undefined;
}
