const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("ctx.zig").context;

test "occlusion query without draws" {
    const dev = &context().device;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;

    const query_count = 5;
    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = query_count,
    });
    defer query_pool.deinit(gpa, dev);
    const query_layt = query_pool.type.getLayout(dev, query_count, false);
    const query_layt_avail = query_pool.type.getLayout(dev, query_count, true);

    const buf_size = 2 * (query_layt.size + query_layt_avail.size);
    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = buf_size,
        .usage = .{ .transfer_dest = true },
    });
    defer buf.deinit(gpa, dev);
    var mem = blk: {
        const mem_reqs = buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);
    const data = (try mem.map(dev, 0, null))[0..buf_size];
    @memset(data, 255);

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.resetQueryPool(&query_pool, 0, query_count);
    cmd.beginQuery(&query_pool, 4, .{});
    cmd.endQuery(&query_pool, 4);
    cmd.beginQuery(&query_pool, 0, .{});
    cmd.endQuery(&query_pool, 0);
    cmd.beginQuery(&query_pool, 2, .{});
    cmd.endQuery(&query_pool, 2);
    cmd.beginQuery(&query_pool, 1, .{});
    cmd.endQuery(&query_pool, 1);
    cmd.beginQuery(&query_pool, 3, .{});
    cmd.endQuery(&query_pool, 3);
    cmd.copyQueryPoolResults(&query_pool, 2, 3, &buf, 2 * query_layt.size, .{
        .wait = false,
        .with_availability = true,
    });
    cmd.copyQueryPoolResults(&query_pool, 0, 2, &buf, 0, .{});
    cmd.copyQueryPoolResults(&query_pool, 0, query_count, &buf, query_layt.size, .{});
    cmd.copyQueryPoolResults(&query_pool, 4, 1, &buf, buf_size - query_layt_avail.size, .{
        .wait = false,
        .with_availability = true,
    });
    try cmd.end();

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);
    {
        context().lockQueue(queue_i);
        defer context().unlockQueue(queue_i);

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    var query_resolve = ngl.QueryResolve(.occlusion){};
    defer query_resolve.free(gpa);

    try query_resolve.resolve(gpa, dev, 0, 2, false, data);
    try testing.expectEqual(query_resolve.resolved_results.len, 2);
    for (query_resolve.resolved_results) |r|
        try testing.expectEqual(r.samples_passed, 0);

    try query_resolve.resolve(gpa, dev, 0, query_count, false, data[query_layt.size..]);
    try testing.expectEqual(query_resolve.resolved_results.len, query_count);
    for (query_resolve.resolved_results) |r|
        try testing.expectEqual(r.samples_passed, 0);

    try query_resolve.resolve(gpa, dev, 0, 3, true, data[2 * query_layt.size ..]);
    try testing.expectEqual(query_resolve.resolved_results.len, 3);
    for (query_resolve.resolved_results) |r|
        if (r.samples_passed) |x| try testing.expectEqual(x, 0);

    try query_resolve.resolve(gpa, dev, 0, 1, true, data[buf_size - query_layt_avail.size ..]);
    try testing.expectEqual(query_resolve.resolved_results.len, 1);
    if (query_resolve.resolved_results[0].samples_passed) |x|
        try testing.expectEqual(x, 0);

    var query_resolve_2 = ngl.QueryResolve(.occlusion){};
    defer query_resolve_2.free(gpa);

    try query_resolve_2.resolve(gpa, dev, 1, query_count - 1, false, data[query_layt.size..]);
    try testing.expectEqual(query_resolve_2.resolved_results.len, query_count - 1);
    try query_resolve.resolve(gpa, dev, 0, query_count, false, data[query_layt.size..]);
    for (query_resolve_2.resolved_results, query_resolve.resolved_results[1..]) |x, y|
        try testing.expectEqual(x, y);

    try query_resolve_2.resolve(gpa, dev, 1, 2, true, data[2 * query_layt.size ..]);
    try testing.expectEqual(query_resolve_2.resolved_results.len, 2);
    try query_resolve.resolve(gpa, dev, 0, 3, true, data[2 * query_layt.size ..]);
    for (query_resolve_2.resolved_results, query_resolve.resolved_results[1..]) |x, y|
        try testing.expectEqual(x, y);
}
