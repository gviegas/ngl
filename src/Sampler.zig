const Device = @import("Device.zig");
const Inner = @import("Impl.zig").Sampler;
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

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.device.allocator);
    self.* = undefined;
}
