const Allocator = @import("std").mem.Allocator;

const Impl = @import("Impl.zig");
const Inner = Impl.Device;
const Heap = @import("Heap.zig");
const Sampler = @import("Sampler.zig");
const DescLayout = @import("DescLayout.zig");
const DescPool = @import("DescPool.zig");
const ShaderCode = @import("ShaderCode.zig");
const PsLayout = @import("PsLayout.zig");
const Buffer = @import("Buffer.zig");
const Texture = @import("Texture.zig");
const Error = @import("main.zig").Error;

impl: *Impl,
inner: Inner,

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
    const impl = try Impl.get(allocator, null);
    errdefer impl.unget();
    const inner = try impl.initDevice(config);
    return .{
        .impl = impl,
        .inner = inner,
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
    self.inner.deinit(self.*);
    self.impl.unget();
    self.* = undefined;
}

pub const PlacementInfo = struct {
    size: u64,
    alignment: u64,
    write_only_heap: bool,
    read_only_heap: bool,
};

pub fn heapBufferPlacement(self: Self, config: Buffer.Config) Error!PlacementInfo {
    return Inner.heapBufferPlacement(self, config);
}

pub fn heapTexturePlacement(self: Self, config: Texture.Config) Error!PlacementInfo {
    return Inner.heapTexturePlacement(self, config);
}

pub fn initHeap(self: *Self, config: Heap.Config) Error!Heap {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initHeap(self.*, config),
        .size = config.size,
        .cpu_access = config.cpu_access,
    };
}

pub fn initSampler(self: *Self, config: Sampler.Config) Error!Sampler {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initSampler(self.*, config),
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

pub fn initDescLayout(self: *Self, config: DescLayout.Config) Error!DescLayout {
    // TODO: Validation.
    const entries = try self.impl.allocator.dupe(DescLayout.Entry, config.entries);
    errdefer self.impl.allocator.free(entries);
    return .{
        .device = self,
        .inner = try Inner.initDescLayout(self.*, config),
        .entries = entries,
    };
}

pub fn initDescPool(self: *Self, config: DescPool.Config) Error!DescPool {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initDescPool(self.*, config),
        .max_sets = config.max_sets,
        .size = config.size,
    };
}

pub fn initShaderCode(self: *Self, config: ShaderCode.Config) Error!ShaderCode {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initShaderCode(self.*, config),
    };
}

pub fn initPsLayout(self: *Self, config: PsLayout.Config) Error!PsLayout {
    // TODO: Validation.
    return .{
        .device = self,
        .inner = try Inner.initPsLayout(self.*, config),
    };
}
