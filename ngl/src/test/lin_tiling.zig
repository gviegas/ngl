const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "linear tiling" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .transfer = true }, null) orelse unreachable;
    const queue = &dev.queues[queue_i];

    const width = 112;
    const height = 72;

    const @"type" = .@"2d";
    const fmt = ngl.Format.rgba8_unorm;
    const tiling: ngl.Image.Tiling = .{ .linear = .preinitialized };
    const usage = ngl.Image.Usage{ .transfer_source = true, .transfer_dest = true };
    const misc = ngl.Image.Misc{};

    _ = ngl.Image.getCapabilities(dev, @"type", fmt, tiling, usage, misc) catch |err| {
        if (err == ngl.Error.NotSupported)
            return error.SkipZigTest;
        return err;
    };

    var lin_img = try ngl.Image.init(gpa, dev, .{
        .type = @"type",
        .format = fmt,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = tiling,
        .usage = usage,
        .misc = misc,
    });
    defer lin_img.deinit(gpa, dev);
    const lin_reqs = lin_img.getMemoryRequirements(dev);
    var lin_mem = try dev.alloc(gpa, .{
        .size = lin_reqs.size,
        .type_index = lin_reqs.findType(dev.*, .{
            .host_visible = true,
            .host_coherent = true,
        }, null).?,
    });
    defer dev.free(gpa, &lin_mem);
    try lin_img.bind(dev, &lin_mem, 0);
    const data = try lin_mem.map(dev, 0, lin_reqs.size);

    const lin_layt = lin_img.getDataLayout(dev, @"type", .color, 0, 0);
    try testing.expect(lin_layt.offset + lin_layt.size <= lin_reqs.size);
    try testing.expect(lin_layt.size >= 4 * width * height);
    try testing.expectEqual(lin_layt.size, lin_layt.row_pitch * height);

    var opt_img = try ngl.Image.init(gpa, dev, .{
        .type = @"type",
        .format = fmt,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = usage,
        .misc = misc,
    });
    defer opt_img.deinit(gpa, dev);
    const opt_reqs = opt_img.getMemoryRequirements(dev);
    var opt_mem = try dev.alloc(gpa, .{
        .size = opt_reqs.size,
        .type_index = opt_reqs.findTypeExact(dev.*, .{ .device_local = true }, null) orelse
            opt_reqs.findType(dev.*, .{ .device_local = true }, null).?,
    });
    defer dev.free(gpa, &opt_mem);
    try opt_img.bind(dev, &opt_mem, 0);

    const range = ngl.Image.Range{
        .aspect_mask = .{ .color = true },
        .level = 0,
        .levels = 1,
        .layer = 0,
        .layers = 1,
    };

    // This should be preserved due to `preinitialized` layout.
    var s = data[lin_layt.offset..];
    for (0..height) |y| {
        for (0..width) |x| {
            const v = (y * width + x) * 4 + 1;
            s[0] = @truncate(v);
            s[1] = @truncate(v + 1);
            s[2] = @truncate(v + 2);
            s[3] = @truncate(v + 3);
            s = s[4..];
        }
        s = s[lin_layt.row_pitch - 4 * width ..];
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = queue });
    defer cmd_pool.deinit(gpa, dev);
    const cmd_buf = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
    defer gpa.free(cmd_buf);
    var fence = try ngl.Fence.init(gpa, dev, .{ .status = .unsignaled });
    defer fence.deinit(gpa, dev);

    // Copy from the linear tiling image to the optimal tiling one.
    var cmd = try cmd_buf[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.barrier(&.{.{
        .image = &.{
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true },
                .queue_transfer = null,
                .old_layout = .preinitialized,
                .new_layout = .transfer_source_optimal,
                .image = &lin_img,
                .range = range,
            },
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .transfer_dest_optimal,
                .image = &opt_img,
                .range = range,
            },
        },
    }});
    cmd.copyImage(&.{.{
        .source = &lin_img,
        .source_layout = .transfer_source_optimal,
        .dest = &opt_img,
        .dest_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .source_aspect = .color,
            .source_level = 0,
            .source_x = 0,
            .source_y = 0,
            .source_z_or_layer = 0,
            .dest_aspect = .color,
            .dest_level = 0,
            .dest_x = 0,
            .dest_y = 0,
            .dest_z_or_layer = 0,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
        }},
    }});
    cmd.barrier(&.{.{
        .image = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_read = true },
            .dest_stage_mask = .{},
            .dest_access_mask = .{},
            .queue_transfer = null,
            .old_layout = .transfer_source_optimal,
            .new_layout = .general,
            .image = &lin_img,
            .range = range,
        }},
    }});
    try cmd.end();
    {
        ctx.lockQueue(queue_i);
        defer ctx.unlockQueue(queue_i);
        try queue.submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    // Should allow host access in `.general` layout.
    s = data[lin_layt.offset..];
    for (0..height) |y| {
        for (0..width) |x| {
            const v = (y * width + x) * 4 + 1;
            try testing.expect(std.mem.eql(
                u8,
                s[0..4],
                &.{ @truncate(v), @truncate(v + 1), @truncate(v + 2), @truncate(v + 3) },
            ));
            s = s[4..];
        }
        s = s[lin_layt.row_pitch - 4 * width ..];
    }
    // The copy below should overwrite this.
    @memset(data, 255);

    // Now copy back to the linear tiling image.
    try ngl.Fence.reset(gpa, dev, &.{&fence});
    try cmd_pool.reset(dev, .keep);
    cmd = try cmd_buf[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.barrier(&.{.{
        .image = &.{
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true },
                .queue_transfer = null,
                .old_layout = .transfer_dest_optimal,
                .new_layout = .transfer_source_optimal,
                .image = &opt_img,
                .range = range,
            },
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_write = true },
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .transfer_dest_optimal,
                .image = &lin_img,
                .range = range,
            },
        },
    }});
    cmd.copyImage(&.{.{
        .source = &opt_img,
        .source_layout = .transfer_source_optimal,
        .dest = &lin_img,
        .dest_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .source_aspect = .color,
            .source_level = 0,
            .source_x = 0,
            .source_y = 0,
            .source_z_or_layer = 0,
            .dest_aspect = .color,
            .dest_level = 0,
            .dest_x = 0,
            .dest_y = 0,
            .dest_z_or_layer = 0,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
        }},
    }});
    cmd.barrier(&.{.{
        .image = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_access_mask = .{},
            .dest_stage_mask = .{},
            .queue_transfer = null,
            .old_layout = .transfer_dest_optimal,
            .new_layout = .general,
            .image = &lin_img,
            .range = range,
        }},
    }});
    try cmd.end();
    {
        ctx.lockQueue(queue_i);
        defer ctx.unlockQueue(queue_i);
        try queue.submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    s = data[lin_layt.offset..];
    for (0..height) |y| {
        for (0..width) |x| {
            const v = (y * width + x) * 4 + 1;
            try testing.expect(std.mem.eql(
                u8,
                s[0..4],
                &.{ @truncate(v), @truncate(v + 1), @truncate(v + 2), @truncate(v + 3) },
            ));
            s = s[4..];
        }
        s = s[lin_layt.row_pitch - 4 * width ..];
    }
}
