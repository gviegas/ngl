const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("ctx.zig").context;

test "QueryPool.init/deinit" {
    const ctx = context();
    const dev = &ctx.device;
    const query_feat = ngl.Feature.get(gpa, &ctx.instance, ctx.device_desc, .core).?.query;
    const no_timestamp = std.mem.eql(bool, &query_feat.timestamp, &[_]bool{false} ** ngl.Queue.max);

    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = 1,
    });
    defer query_pool.deinit(gpa, dev);
    try testing.expectEqual(query_pool.type, .occlusion);

    var query_pool_2 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = 2,
    });
    try testing.expectEqual(query_pool_2.type, .occlusion);
    query_pool_2.deinit(gpa, dev);

    for ([_]u32{ 24, 12, 1, 3 }) |x| {
        var qp = try ngl.QueryPool.init(gpa, dev, .{
            .query_type = .occlusion,
            .query_count = x,
        });
        try testing.expectEqual(qp.type, .occlusion);
        qp.deinit(gpa, dev);
    }

    if (no_timestamp) return;

    var query_pool_3 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
        .query_count = 1,
    });
    try testing.expectEqual(query_pool_3.type, .timestamp);
    query_pool_3.deinit(gpa, dev);

    var query_pool_4 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
        .query_count = 4,
    });
    defer query_pool_4.deinit(gpa, dev);
    try testing.expectEqual(query_pool_4.type, .timestamp);

    for ([_]u32{ 14, 28, 1, 5 }) |x| {
        var qp = try ngl.QueryPool.init(gpa, dev, .{
            .query_type = .timestamp,
            .query_count = x,
        });
        try testing.expectEqual(qp.type, .timestamp);
        qp.deinit(gpa, dev);
    }

    for ([_]u32{ 1, 2, 16, 32, 31, 15 }) |x| {
        var tms = try ngl.QueryPool.init(gpa, dev, .{
            .query_type = .timestamp,
            .query_count = x,
        });
        defer tms.deinit(gpa, dev);
        try testing.expectEqual(tms.type, .timestamp);
        var occ = try ngl.QueryPool.init(gpa, dev, .{
            .query_type = .occlusion,
            .query_count = x,
        });
        defer occ.deinit(gpa, dev);
        try testing.expectEqual(occ.type, .occlusion);
    }
}
