const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("ctx.zig").context;

test "QueryPool.init/deinit" {
    const dev = &context().device;

    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = 1,
    });
    defer query_pool.deinit(gpa, dev);

    var query_pool_2 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = 2,
    });
    query_pool_2.deinit(gpa, dev);

    var query_pool_3 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
        .query_count = 1,
    });
    query_pool_3.deinit(gpa, dev);

    var query_pool_4 = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
        .query_count = 4,
    });
    defer query_pool_4.deinit(gpa, dev);

    inline for (.{
        .{ ngl.QueryType.occlusion, 15 },
        .{ ngl.QueryType.timestamp, 32 },
    }) |x| {
        var qp = try ngl.QueryPool.init(gpa, dev, .{
            .query_type = x[0],
            .query_count = x[1],
        });
        qp.deinit(gpa, dev);
    }
}
