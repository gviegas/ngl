const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "CommandBuffer.begin/Cmd.end" {
    const dev = &context().device;

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[0] });
    defer cmd_pool.deinit(gpa, dev);

    var cmd_bufs = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 2 });
    defer gpa.free(cmd_bufs);

    var cmd = try cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    // Command buffers containing no commands should be valid
    try cmd.end();

    // It shouldn't be necessary to submit an ended command buffer
    // The pool must be reset however (no implicit reset on `begin`)
    try cmd_pool.reset(dev);
    cmd = try cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    var cmd_2 = try cmd_bufs[1].begin(gpa, dev, .{ .one_time_submit = false, .inheritance = null });
    try cmd.end();
    try cmd_2.end();

    // The pool can be reset during recording, which invalidates
    // the command buffer
    cmd = try cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = false, .inheritance = null });
    try cmd_pool.reset(dev);
    cmd = try cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = false, .inheritance = null });
    try cmd.end();

    var cmd_pool_2 = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[0] });
    defer cmd_pool_2.deinit(gpa, dev);

    var cmd_bufs_2 = try cmd_pool_2.alloc(gpa, dev, .{ .level = .secondary, .count = 3 });
    defer gpa.free(cmd_bufs_2);

    var cmd_3 = try cmd_bufs_2[0].begin(gpa, dev, .{
        .one_time_submit = true,
        // This field must be set for secondary command buffers
        .inheritance = .{
            .render_pass_continue = null,
            .query_continue = null,
        },
    });
    try cmd_3.end();

    if (!builtin.single_threaded) {
        // Uses `cmd_pool`
        const doPrimary = struct {
            fn f(device: *ngl.Device, command_buffer: *ngl.CommandBuffer) ngl.Error!void {
                var _cmd = try command_buffer.begin(gpa, device, .{
                    .one_time_submit = true,
                    .inheritance = null,
                });
                try _cmd.end();
            }
        }.f;

        // Uses `cmd_pool_2`
        const doSecondary = struct {
            fn f(device: *ngl.Device, command_buffers: *[2]ngl.CommandBuffer) ngl.Error!void {
                var _cmd = try command_buffers[0].begin(gpa, device, .{
                    .one_time_submit = true,
                    .inheritance = .{
                        .render_pass_continue = null,
                        .query_continue = null,
                    },
                });
                var _cmd_2 = try command_buffers[1].begin(gpa, device, .{
                    .one_time_submit = false,
                    .inheritance = .{
                        .render_pass_continue = null,
                        .query_continue = null,
                    },
                });
                try _cmd_2.end();
                try _cmd.end();
            }
        }.f;

        const thrds = [2]std.Thread{
            try std.Thread.spawn(.{ .allocator = gpa }, doPrimary, .{ dev, &cmd_bufs[1] }),
            try std.Thread.spawn(.{ .allocator = gpa }, doSecondary, .{ dev, cmd_bufs_2[1..3] }),
        };
        for (thrds) |thrd| thrd.join();
    }

    // It should be OK to deinitialize the pool during recording
    cmd = try cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    // It should be OK to free the command buffer during recording
    cmd_2 = try cmd_bufs[1].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd_pool.free(gpa, dev, &.{&cmd_bufs[1]});
}
