const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "CommandPool.init/deinit" {
    const dev = &context().device;

    for (dev.queues[0..dev.queue_n]) |*q| {
        var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = q });
        cmd_pool.deinit(gpa, dev);
    }
}

test "CommandPool.alloc/reset/free" {
    const dev = &context().device;

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[0] });
    defer cmd_pool.deinit(gpa, dev);

    const count = 1;
    var cmd_buf = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = count });
    defer gpa.free(cmd_buf);
    try testing.expectEqual(cmd_buf.len, count);

    try cmd_pool.reset(dev, .keep);

    const count_2 = 4;
    var cmd_bufs = try cmd_pool.alloc(gpa, dev, .{ .level = .secondary, .count = count_2 });
    defer gpa.free(cmd_bufs);
    try testing.expectEqual(cmd_bufs.len, count_2);

    // Affects everything in `cmd_buf` and `cmd_bufs`
    try cmd_pool.reset(dev, .keep);

    cmd_pool.free(gpa, dev, &.{&cmd_bufs[0]});
    cmd_pool.free(gpa, dev, &.{ &cmd_buf[0], &cmd_bufs[3], &cmd_bufs[2] });

    // `cmd_bufs[1]` shouldn't leak
}
