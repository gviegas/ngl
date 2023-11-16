const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;
const platform = @import("sf.zig").platform;
const platform_lock = &@import("sf.zig").platform_lock;

test "Queue.submit" {
    const dev = &context().device;
    const queue = &dev.queues[0];

    var semas: [3]ngl.Semaphore = undefined;
    for (&semas, 0..) |*sema, i| {
        sema.* = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
            for (0..i) |j| semas[j].deinit(gpa, dev);
            return err;
        };
    }
    defer for (&semas) |*sema| sema.deinit(gpa, dev);

    var fences: [2]ngl.Fence = undefined;
    for (&fences, 0..) |*fence, i| {
        fence.* = ngl.Fence.init(gpa, dev, .{}) catch |err| {
            for (0..i) |j| fences[j].deinit(gpa, dev);
            return err;
        };
    }
    defer for (&fences) |*fence| fence.deinit(gpa, dev);

    const timeout = std.time.ns_per_ms * 10;

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = queue });
    defer cmd_pool.deinit(gpa, dev);

    var cmd_bufs = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 3 });
    defer gpa.free(cmd_bufs);

    queue_locks[0].lock();
    defer queue_locks[0].unlock();

    {
        // Submission of empty command buffers is allowed
        for (cmd_bufs) |*cmd_buf| {
            var cmd = try cmd_buf.begin(
                gpa,
                dev,
                .{ .one_time_submit = true, .inheritance = null },
            );
            try cmd.end();
        }

        try queue.submit(gpa, dev, &fences[0], &.{.{
            .commands = &.{
                .{ .command_buffer = &cmd_bufs[0] },
                .{ .command_buffer = &cmd_bufs[1] },
                .{ .command_buffer = &cmd_bufs[2] },
            },
            .wait = &.{},
            .signal = &.{},
        }});

        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[0]});
    }

    {
        try cmd_pool.reset(dev);

        for (cmd_bufs) |*cmd_buf| {
            var cmd = try cmd_buf.begin(
                gpa,
                dev,
                .{ .one_time_submit = true, .inheritance = null },
            );
            try cmd.end();
        }

        try queue.submit(gpa, dev, &fences[1], &.{
            .{
                .commands = &.{.{ .command_buffer = &cmd_bufs[0] }},
                .wait = &.{},
                .signal = &.{
                    .{ .semaphore = &semas[0], .stage_mask = .{ .all_commands = true } },
                    .{ .semaphore = &semas[1], .stage_mask = .{ .all_commands = true } },
                },
            },
            .{
                .commands = &.{.{ .command_buffer = &cmd_bufs[1] }},
                .wait = &.{
                    .{ .semaphore = &semas[1], .stage_mask = .{ .all_commands = true } },
                    .{ .semaphore = &semas[0], .stage_mask = .{ .all_commands = true } },
                },
                .signal = &.{.{ .semaphore = &semas[2], .stage_mask = .{ .all_commands = true } }},
            },
            .{
                .commands = &.{.{ .command_buffer = &cmd_bufs[2] }},
                .wait = &.{.{ .semaphore = &semas[2], .stage_mask = .{ .all_commands = true } }},
                .signal = &.{},
            },
        });

        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[1]});
    }

    {
        try cmd_pool.reset(dev);
        try ngl.Fence.reset(gpa, dev, &.{ &fences[0], &fences[1] });

        for (cmd_bufs) |*cmd_buf| {
            var cmd = try cmd_buf.begin(
                gpa,
                dev,
                .{ .one_time_submit = true, .inheritance = null },
            );
            try cmd.end();
        }

        const subm = ngl.Queue.Submit{
            .commands = &.{
                .{ .command_buffer = &cmd_bufs[2] },
                .{ .command_buffer = &cmd_bufs[0] },
            },
            .wait = &.{},
            .signal = &.{
                .{ .semaphore = &semas[0], .stage_mask = .{ .clear = true } },
                .{ .semaphore = &semas[1], .stage_mask = .{ .copy = true } },
                .{ .semaphore = &semas[2], .stage_mask = .{ .host = true } },
            },
        };

        const subm_2 = ngl.Queue.Submit{
            .commands = &.{.{ .command_buffer = &cmd_bufs[1] }},
            .wait = &.{
                .{ .semaphore = &semas[1], .stage_mask = .{ .copy = true } },
                .{ .semaphore = &semas[2], .stage_mask = .{ .copy = true } },
                .{ .semaphore = &semas[0], .stage_mask = .{ .all_commands = true } },
            },
            .signal = &.{},
        };

        try queue.submit(gpa, dev, &fences[0], &.{subm});
        try queue.submit(gpa, dev, &fences[1], &.{subm_2});

        try ngl.Fence.wait(gpa, dev, timeout, &.{ &fences[0], &fences[1] });
    }

    {
        try cmd_pool.reset(dev);
        try ngl.Fence.reset(gpa, dev, &.{ &fences[0], &fences[1] });

        // We should be able to re-submit this command buffer
        // when a previous submission completes its execution
        var cmd = try cmd_bufs[0].begin(gpa, dev, .{
            .one_time_submit = false,
            .inheritance = null,
        });
        try cmd.end();

        const subm = ngl.Queue.Submit{
            .commands = &.{.{ .command_buffer = &cmd_bufs[0] }},
            .wait = &.{},
            .signal = &.{},
        };

        try queue.submit(gpa, dev, &fences[0], &.{subm});
        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[0]});

        try queue.submit(gpa, dev, &fences[1], &.{subm});
        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[1]});
    }

    {
        try ngl.Fence.reset(gpa, dev, &.{&fences[0]});

        // We don't have to submit any command buffers
        try queue.submit(gpa, dev, null, &.{.{
            .commands = &.{},
            .wait = &.{},
            .signal = &.{.{ .semaphore = &semas[0], .stage_mask = .{ .copy = true } }},
        }});

        // We don't have to submit anything at all
        try queue.submit(gpa, dev, &fences[0], &.{});
        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[0]});
    }
}

test "Queue.present" {
    const dev = &context().device;
    const plat = try platform();

    var semas = try gpa.alloc(ngl.Semaphore, plat.images.len);
    defer gpa.free(semas);
    for (semas, 0..) |*sema, i| {
        sema.* = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
            for (0..i) |j| semas[j].deinit(gpa, dev);
            return err;
        };
    }
    var fences = try gpa.alloc(ngl.Fence, plat.images.len);
    defer gpa.free(fences);
    for (fences, 0..) |*fence, i| {
        fence.* = ngl.Fence.init(gpa, dev, .{}) catch |err| {
            for (0..i) |j| fences[j].deinit(gpa, dev);
            return err;
        };
    }

    const timeout = std.time.ns_per_ms * 3;

    // TODO: Create the swap chain with more images than the minimum
    // so we can test multiple presents in one call

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[plat.queue_index] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_bufs = try cmd_pool.alloc(gpa, dev, .{
        .level = .primary,
        .count = @intCast(plat.images.len),
    });
    defer gpa.free(cmd_bufs);

    queue_locks[plat.queue_index].lock();
    defer queue_locks[plat.queue_index].unlock();
    platform_lock.lock();
    defer platform_lock.unlock();

    for (0..plat.images.len) |i| {
        const next = try plat.swap_chain.nextImage(dev, timeout, null, &fences[i]);

        var cmd = try cmd_bufs[i].begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{},
                .dest_access_mask = .{},
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .present_source,
                .image = &plat.images[next],
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            }},
            .by_region = false,
        }});
        try cmd.end();

        try ngl.Fence.wait(gpa, dev, timeout, &.{&fences[i]});

        try dev.queues[plat.queue_index].submit(gpa, dev, null, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_bufs[i] }},
            .wait = &.{},
            .signal = &.{.{ .semaphore = &semas[i], .stage_mask = .{} }},
        }});

        try dev.queues[plat.queue_index].present(
            gpa,
            dev,
            &.{&semas[i]},
            &.{.{ .swap_chain = &plat.swap_chain, .image_index = next }},
        );
    }
}

test "Queue.wait" {
    const dev = &context().device;

    for (dev.queues[0..dev.queue_n], queue_locks[0..dev.queue_n]) |*queue, *lock| {
        lock.lock();
        defer lock.unlock();
        try queue.wait(dev);
    }
}
