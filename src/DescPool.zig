const Allocator = @import("std").mem.Allocator;

const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.DescPool;
const DescSet = @import("DescSet.zig");
const Error = @import("main.zig").Error;

device: *Device,
inner: Inner,
max_sets: u32,
size: Size,

pub const Size = struct {
    storage_buffer: u32 = 0,
    uniform_buffer: u32 = 0,
    dynamic_storage_buffer: u32 = 0,
    dynamic_uniform_buffer: u32 = 0,
    storage_texture: u32 = 0,
    sampled_texture: u32 = 0,
    sampler: u32 = 0,
};

pub const Config = struct {
    max_sets: u32,
    size: Size,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn allocSets(
    self: *Self,
    allocator: Allocator,
    configs: []const DescSet.Config,
) Error![]DescSet {
    // TODO: Validation.
    const n = blk: {
        var n: u32 = 0;
        for (configs) |config| {
            n += config.count;
        }
        break :blk n;
    };
    var sets = try allocator.alloc(DescSet, n);
    errdefer allocator.free(sets);
    for (sets) |*set| {
        set.pool = self;
        set.inner = undefined;
    }
    try Inner.allocSets(self.*, sets, configs);
    return sets;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
