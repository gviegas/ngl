const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

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

test "timestamp query" {
    const ctx = context();
    const dev = &ctx.device;
    const core_feat = ngl.Feature.get(gpa, &ctx.instance, ctx.device_desc, .core).?;
    if (std.mem.eql(bool, &core_feat.query.timestamp, &[_]bool{false} ** ngl.Queue.max))
        return error.SkipZigTest;
    var queue_i: ngl.Queue.Index = undefined;
    // We dont' want a transfer-only queue because it may be faster and
    // also because Vulkan 1.0 doesn't allow filling buffers on such a queue
    for (dev.queues[0..dev.queue_n], 0..) |queue, i| {
        if (!core_feat.query.timestamp[i]) continue;
        queue_i = @intCast(i);
        if (queue.capabilities.graphics or queue.capabilities.compute)
            break;
    }

    const query_count = 2;
    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .timestamp,
        .query_count = query_count,
    });
    defer query_pool.deinit(gpa, dev);

    const query_buf_size = query_pool.type.getLayout(dev, query_count, false).size;
    var query_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = query_buf_size,
        .usage = .{ .transfer_dest = true },
    });
    defer query_buf.deinit(gpa, dev);
    var query_mem = blk: {
        const mem_reqs = query_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try query_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &query_mem);
    const query_data = (try query_mem.map(dev, 0, null))[0..query_buf_size];
    @memset(query_data, 255);

    var image: ngl.Image = undefined;
    var img_mem: ngl.Memory = undefined;
    const extent = blk: {
        var extent: u32 = 2 * core_feat.image.max_dimension_2d;
        while (extent > 4096) {
            extent /= 2;
            image = ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = .rgba8_unorm,
                .width = extent,
                .height = extent,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = .@"1",
                .tiling = .optimal,
                .usage = .{
                    .sampled_image = true,
                    .transfer_source = true,
                    .transfer_dest = true,
                },
                .misc = .{},
                .initial_layout = .unknown,
            }) catch |err| {
                if (err != ngl.Error.OutOfMemory) return err;
                continue;
            };
            img_mem = blk_2: {
                const mem_reqs = image.getMemoryRequirements(dev);
                var mem = dev.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
                }) catch |err| {
                    image.deinit(gpa, dev);
                    if (err != ngl.Error.OutOfMemory) return err;
                    continue;
                };
                image.bind(dev, &mem, 0) catch |err| {
                    image.deinit(gpa, dev);
                    dev.free(gpa, &mem);
                    if (err != ngl.Error.OutOfMemory) return err;
                    continue;
                };
                break :blk_2 mem;
            };
            break :blk extent;
        }
        @panic("Device can't create an image with the minimum required size");
    };
    defer {
        image.deinit(gpa, dev);
        dev.free(gpa, &img_mem);
    }

    // BUG: Putting a value too low here will crash the test during
    // the fill plus copy loop below (note that it's quadratic)
    // Need to investigate the cause
    const tile = extent / 32;
    const copy_buf_size = tile * tile * 4;
    var copy_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = copy_buf_size,
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    defer copy_buf.deinit(gpa, dev);
    var copy_mem = blk: {
        const mem_reqs = copy_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try copy_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &copy_mem);

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.resetQueryPool(&query_pool, 0, query_count);
    cmd.writeTimestamp(.all_commands, &query_pool, 0);
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{},
            .source_access_mask = .{},
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
            .queue_transfer = null,
            .old_layout = .unknown,
            .new_layout = .general,
            .image = &image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = null,
                .base_layer = 0,
                .layers = null,
            },
        }},
        .by_region = false,
    }});
    // This should take a while
    for (0..extent / tile) |x| {
        for (0..extent / tile) |y| {
            cmd.fillBuffer(&copy_buf, 0, null, @intCast((x ^ y) & 255));
            cmd.pipelineBarrier(&.{.{
                .global_dependencies = &.{.{
                    .source_stage_mask = .{ .copy = true },
                    .source_access_mask = .{ .transfer_read = true, .transfer_write = true },
                    .dest_stage_mask = .{ .copy = true },
                    .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                }},
                .by_region = false,
            }});
            cmd.copyBufferToImage(&.{.{
                .buffer = &copy_buf,
                .image = &image,
                .image_layout = .general,
                .image_type = .@"2d",
                .regions = &.{.{
                    .buffer_offset = 0,
                    .buffer_row_length = tile,
                    .buffer_image_height = tile,
                    .image_aspect = .color,
                    .image_level = 0,
                    .image_x = @intCast(x * tile),
                    .image_y = @intCast(y * tile),
                    .image_z_or_layer = 0,
                    .image_width = tile,
                    .image_height = tile,
                    .image_depth_or_layers = 1,
                }},
            }});
            cmd.pipelineBarrier(&.{.{
                .global_dependencies = &.{.{
                    .source_stage_mask = .{ .copy = true },
                    .source_access_mask = .{ .transfer_read = true, .transfer_write = true },
                    .dest_stage_mask = .{ .copy = true },
                    .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                }},
                .by_region = false,
            }});
        }
    }
    cmd.writeTimestamp(.all_commands, &query_pool, 1);
    cmd.copyQueryPoolResults(&query_pool, 0, 2, &query_buf, 0, .{});
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
    defer query_resolve.free(gpa);
    try query_resolve.resolve(gpa, dev, 0, 2, false, query_data);

    const r0 = query_resolve.resolved_results[0].ns.?;
    const r1 = query_resolve.resolved_results[1].ns.?;
    try testing.expect(r0 < r1);
    const dt = r1 - r0;
    // TODO: May need to adjust this value
    // It takes ~150ms on an integrated GPU from 2014
    try testing.expect(dt > std.time.ns_per_ms * 5);
}
