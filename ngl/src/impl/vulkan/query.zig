const std = @import("std");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;

pub fn getQueryLayout(
    _: *anyopaque,
    _: Impl.Device,
    query_type: ngl.QueryType,
    query_count: u32,
    with_availability: bool,
) ngl.QueryType.Layout {
    // We always set VK_QUERY_RESULT_64_BIT when copying results
    const result_size: u64 = switch (query_type) {
        .occlusion, .timestamp => @sizeOf(u64),
    };
    const avail_size: u64 = if (with_availability) @sizeOf(u64) else 0;
    return .{
        .size = (result_size + avail_size) * query_count,
        .alignment = 8,
    };
}

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

pub fn resolveQueryOcclusion(
    _: *anyopaque,
    _: Impl.Device,
    first_result: u32,
    with_availability: bool,
    source: []const u8,
    dest: @TypeOf((ngl.QueryResolve(.occlusion){}).resolved_results),
) Error!void {
    if (@intFromPtr(source.ptr) & 7 != 0) return Error.InvalidArgument;

    var source_64 = @as([*]const u64, @ptrCast(@alignCast(source)))[0 .. source.len / 8];

    if (with_availability) {
        source_64 = source_64[first_result * 2 ..];
        for (dest) |*r| {
            r.samples_passed = if (source_64[1] != 0) source_64[0] else null;
            source_64 = source_64[2..];
        }
    } else {
        source_64 = source_64[first_result..];
        for (dest, source_64[0..dest.len]) |*r, u|
            r.samples_passed = u;
    }
}

pub fn resolveQueryTimestamp(
    _: *anyopaque,
    device: Impl.Device,
    first_result: u32,
    with_availability: bool,
    source: []const u8,
    dest: @TypeOf((ngl.QueryResolve(.timestamp){}).resolved_results),
) Error!void {
    if (@intFromPtr(source.ptr) & 7 != 0) return Error.InvalidArgument;

    var source_64 = @as([*]const u64, @ptrCast(@alignCast(source)))[0 .. source.len / 8];
    const period: f64 = Device.cast(device).timestamp_period;

    if (with_availability) {
        source_64 = source_64[first_result * 2 ..];
        for (dest) |*r| {
            r.ns = if (source_64[1] != 0)
                @intFromFloat(@as(f64, @floatFromInt(source_64[0])) * period)
            else
                null;
            source_64 = source_64[2..];
        }
    } else {
        source_64 = source_64[first_result..];
        for (dest, source_64[0..dest.len]) |*r, u|
            r.ns = @intFromFloat(@as(f64, @floatFromInt(u)) * period);
    }
}
