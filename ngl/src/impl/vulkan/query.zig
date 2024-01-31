const std = @import("std");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;

pub const QueryPool = packed struct {
    handle: c.VkQueryPool,

    pub inline fn cast(impl: Impl.QueryPool) QueryPool {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.QueryPool.Desc,
    ) Error!Impl.QueryPool {
        var query_pool: c.VkQueryPool = undefined;
        try check(Device.cast(device).vkCreateQueryPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queryType = switch (desc.query_type) {
                .occlusion => c.VK_QUERY_TYPE_OCCLUSION,
                .timestamp => c.VK_QUERY_TYPE_TIMESTAMP,
            },
            .queryCount = desc.query_count,
            .pipelineStatistics = 0,
        }, null, &query_pool));

        return .{ .val = @bitCast(QueryPool{ .handle = query_pool }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        query_pool: Impl.QueryPool,
    ) void {
        Device.cast(device).vkDestroyQueryPool(cast(query_pool).handle, null);
    }
};
