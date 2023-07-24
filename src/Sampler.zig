const Device = @import("Device.zig");
const Inner = @import("impl.zig").Sampler;
const Error = @import("main.zig").Error;

device: *Device,
inner: Inner,
u_addressing: AddressMode,
v_addressing: AddressMode,
w_addressing: AddressMode,
mag_filter: Filter,
min_filter: Filter,
mip_filter: MipFilter,
lod_min_clamp: f32,
lod_max_clamp: f32,
max_anisotropy: u5,
compare: ?CompareFn,

pub const AddressMode = union(enum) {
    clamp_to_edge,
    repeat,
    mirror_repeat,
    clamp_to_border: BorderColor,
};

pub const BorderColor = enum {
    transparent_black,
    opaque_black,
    opaque_white,
};

pub const Filter = enum {
    nearest,
    linear,
};

pub const MipFilter = enum {
    nearest,
    linear,
};

pub const CompareFn = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const Config = struct {
    u_addressing: AddressMode = .clamp_to_edge,
    v_addressing: AddressMode = .clamp_to_edge,
    w_addressing: AddressMode = .clamp_to_edge,
    mag_filter: Filter = .nearest,
    min_filter: Filter = .nearest,
    mip_filter: MipFilter = .nearest,
    lod_min_clamp: f32 = 0,
    lod_max_clamp: f32 = 1000,
    max_anisotropy: u5 = 1,
    compare: ?CompareFn = null,
};

const Self = @This();

pub fn init(device: *Device, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .device = device,
        .inner = try device.inner.initSampler(device.allocator, config),
        .u_addressing = config.u_addressing,
        .v_addressing = config.v_addressing,
        .w_addressing = config.w_addressing,
        .mag_filter = config.mag_filter,
        .min_filter = config.min_filter,
        .mip_filter = config.mip_filter,
        .lod_min_clamp = config.lod_min_clamp,
        .lod_max_clamp = config.lod_max_clamp,
        .max_anisotropy = config.max_anisotropy,
        .compare = config.compare,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.device.allocator, self.device.inner);
    self.* = undefined;
}
