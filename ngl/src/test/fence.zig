const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Fence.init/deinit" {
    const dev = &context().device;

    var unsig = try ngl.Fence.init(gpa, dev, .{ .initial_status = .unsignaled });
    defer unsig.deinit(gpa, dev);
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);

    var sig = try ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled });
    defer sig.deinit(gpa, dev);
    try testing.expectEqual(sig.getStatus(dev), .signaled);

    // Unsignaled is the default.
    var unsig_2 = try ngl.Fence.init(gpa, dev, .{});
    defer unsig_2.deinit(gpa, dev);
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);
}

test "Fence.reset" {
    const dev = &context().device;

    var a = try ngl.Fence.init(gpa, dev, .{ .initial_status = .unsignaled });
    defer a.deinit(gpa, dev);
    var b = try ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled });
    defer b.deinit(gpa, dev);
    var c = try ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled });
    defer c.deinit(gpa, dev);
    var d = try ngl.Fence.init(gpa, dev, .{});
    defer d.deinit(gpa, dev);

    try ngl.Fence.reset(gpa, dev, &.{ &a, &b });
    try testing.expectEqual(a.getStatus(dev), .unsignaled);
    try testing.expectEqual(b.getStatus(dev), .unsignaled);

    try ngl.Fence.reset(gpa, dev, &.{&c});
    try testing.expectEqual(c.getStatus(dev), .unsignaled);
    try ngl.Fence.reset(gpa, dev, &.{&c});
    try testing.expectEqual(c.getStatus(dev), .unsignaled);

    try ngl.Fence.reset(gpa, dev, &.{&d});
    try testing.expectEqual(d.getStatus(dev), .unsignaled);
}

test "Fence.wait" {
    const dev = &context().device;

    var unsig = try ngl.Fence.init(gpa, dev, .{});
    defer unsig.deinit(gpa, dev);
    var sig = try ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled });
    defer sig.deinit(gpa, dev);
    var sig_2 = try ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled });
    defer sig_2.deinit(gpa, dev);
    var unsig_2 = try ngl.Fence.init(gpa, dev, .{});
    defer unsig_2.deinit(gpa, dev);

    const timeout = std.time.ns_per_ms * 5;

    try testing.expectError(
        ngl.Error.Timeout,
        ngl.Fence.wait(gpa, dev, timeout, &.{&unsig}),
    );
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);

    try ngl.Fence.wait(gpa, dev, timeout, &.{&sig});
    try testing.expectEqual(sig.getStatus(dev), .signaled);

    // Current behavior is to wait until all fences become signaled.
    try testing.expectError(
        ngl.Error.Timeout,
        ngl.Fence.wait(gpa, dev, timeout, &.{ &sig, &unsig }),
    );
    try testing.expectEqual(sig.getStatus(dev), .signaled);
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);

    try ngl.Fence.wait(gpa, dev, timeout, &.{ &sig_2, &sig });
    try testing.expectEqual(sig_2.getStatus(dev), .signaled);
    try testing.expectEqual(sig.getStatus(dev), .signaled);

    try testing.expectError(
        ngl.Error.Timeout,
        ngl.Fence.wait(gpa, dev, timeout, &.{ &unsig_2, &unsig }),
    );
    try testing.expectEqual(unsig_2.getStatus(dev), .unsignaled);
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);

    try testing.expectError(
        ngl.Error.Timeout,
        ngl.Fence.wait(gpa, dev, timeout, &.{ &sig_2, &unsig_2, &sig, &unsig }),
    );
    try testing.expectEqual(sig_2.getStatus(dev), .signaled);
    try testing.expectEqual(sig.getStatus(dev), .signaled);
    try testing.expectEqual(unsig_2.getStatus(dev), .unsignaled);
    try testing.expectEqual(unsig.getStatus(dev), .unsignaled);
}
