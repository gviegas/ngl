const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("ctx.zig").context;

test "timestamp query on empty command buffer" {
    const ctx = context();
    const dev = &ctx.device;
    const core_feat = ngl.Feature.get(gpa, &ctx.instance, ctx.device_desc, .core).?;
    if (std.mem.eql(bool, &core_feat.query.timestamp, &[_]bool{false} ** ngl.Queue.max))
        return error.SkipZigTest;
    // We won't record anything other than the queries themselves
    // so the capabilities of the queue don't matter
    const queue_i: ngl.Queue.Index = @intCast(std.mem.indexOfScalar(
        bool,
        &core_feat.query.timestamp,
        true,
    ).?);

    const query_count = 10;
    comptime if (query_count < 4) unreachable;
    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
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
    for (0..query_count / 2) |i|
        cmd.writeTimestamp(.all_commands, &query_pool, @intCast(i));
    for (0..query_count / 2 + (query_count & 1)) |i|
        cmd.writeTimestamp(.all_commands, &query_pool, @intCast(query_count - i - 1));
    cmd.copyQueryPoolResults(
        &query_pool,
        0,
        query_count,
        &buf,
        2 * query_layt.size,
        .{ .wait = false, .with_availability = true },
    );
    cmd.copyQueryPoolResults(&query_pool, 0, query_count, &buf, 0, .{});
    cmd.copyQueryPoolResults(&query_pool, query_count / 2, 1, &buf, query_layt.size, .{});
    cmd.copyQueryPoolResults(
        &query_pool,
        query_count / 2 - 1,
        2,
        &buf,
        buf_size - query_layt_avail.size,
        .{ .wait = false, .with_availability = true },
    );
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

    var query_resolve = ngl.QueryResolve(.timestamp){};
    var query_resolve_2 = ngl.QueryResolve(.timestamp){};
    defer query_resolve.free(gpa);
    defer query_resolve_2.free(gpa);

    try query_resolve.resolve(gpa, dev, 0, query_count, false, data);
    try query_resolve_2.resolve(gpa, dev, 0, query_count, true, data[2 * query_layt.size ..]);

    try testing.expectEqual(query_resolve.resolved_results.len, query_count);
    try testing.expectEqual(query_resolve_2.resolved_results.len, query_count);
    for (0..query_count / 2 - 1) |i|
        try testing.expect(
            query_resolve.resolved_results[i].ns.? <= query_resolve.resolved_results[i + 1].ns.?,
        );
    for (query_count / 2..query_count - 1) |i|
        try testing.expect(
            query_resolve.resolved_results[i].ns.? >= query_resolve.resolved_results[i + 1].ns.?,
        );
    for (query_resolve.resolved_results, query_resolve_2.resolved_results) |r, s|
        if (s.ns) |x| try testing.expectEqual(r.ns.?, x);

    try query_resolve.resolve(gpa, dev, 0, 1, false, data[query_layt.size..]);
    try query_resolve_2.resolve(gpa, dev, 0, 2, true, data[buf_size - query_layt_avail.size ..]);

    try testing.expectEqual(query_resolve.resolved_results.len, 1);
    try testing.expectEqual(query_resolve_2.resolved_results.len, 2);
    if (query_resolve_2.resolved_results[1].ns) |x|
        try testing.expectEqual(query_resolve.resolved_results[0].ns.?, x);
    if (query_resolve_2.resolved_results[0].ns) |x|
        try testing.expect(query_resolve.resolved_results[0].ns.? >= x);
}
