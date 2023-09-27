const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;

pub const Pipeline = struct {
    handle: c.VkPipeline,

    pub inline fn cast(impl: *Impl.Pipeline) *Pipeline {
        return @ptrCast(@alignCast(impl));
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline: *Impl.Pipeline,
        _: ngl.Pipeline.Type,
    ) void {
        const dev = Device.cast(device);
        const pl = cast(pipeline);
        dev.vkDestroyPipeline(pl.handle, null);
        allocator.destroy(pl);
    }
};

pub const PipelineCache = struct {
    handle: c.VkPipelineCache,

    pub inline fn cast(impl: *Impl.PipelineCache) *PipelineCache {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.PipelineCache.Desc,
    ) Error!*Impl.PipelineCache {
        const dev = Device.cast(device);

        var ptr = try allocator.create(PipelineCache);
        errdefer allocator.destroy(ptr);

        var pl_cache: c.VkPipelineCache = undefined;
        try conv.check(dev.vkCreatePipelineCache(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .initialDataSize = if (desc.initial_data) |x| x.len else 0,
            .pInitialData = if (desc.initial_data) |x| x.ptr else null,
        }, null, &pl_cache));

        ptr.* = .{ .handle = pl_cache };
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline_cache: *Impl.PipelineCache,
    ) void {
        const dev = Device.cast(device);
        const pl_cache = cast(pipeline_cache);
        dev.vkDestroyPipelineCache(pl_cache.handle, null);
        allocator.destroy(pl_cache);
    }
};
