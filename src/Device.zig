const std = @import("std");
const Allocator = std.mem.Allocator;

const Impl = @import("Impl.zig");
const Inner = Impl.Device;
const Heap = @import("Heap.zig");
const Sampler = @import("Sampler.zig");
const Error = @import("main.zig").Error;

impl: *Impl,
inner: Inner,
allocator: Allocator,

pub const Config = struct {
    power_preference: PowerPreference = .high_performance,
    force_fallback_device: bool = false,
};

pub const PowerPreference = enum {
    high_performance,
    low_power,
};

const Self = @This();

pub fn init(allocator: Allocator, config: Config) Error!Self {
    const impl = try Impl.get(null);
    const inner = try impl.initDevice(allocator, config);
    return .{
        .impl = impl,
        .inner = inner,
        .allocator = allocator,
    };
}

pub fn initAll(_: Allocator) Error![]Self {
    @compileError("TODO");
}

pub fn isHighPerformance(self: Self) bool {
    return self.inner.high_performance;
}

pub fn isLowPower(self: Self) bool {
    return self.inner.low_power;
}

pub fn isFallbackDevice(self: Self) bool {
    return self.inner.fallback;
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.allocator);
    self.impl.unget();
    self.* = undefined;
}

pub fn initHeap(self: *Self, config: Heap.Config) Error!Heap {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initHeap(self.*, self.allocator, config),
        .size = config.size,
        .cpu_access = config.cpu_access,
    };
}

pub fn initSampler(self: *Self, config: Sampler.Config) Error!Sampler {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initSampler(self.*, self.allocator, config),
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
