const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;

test "copy between resources" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.transfer) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const w = 32;
    const h = 24;
    const size = w * h * 4;

    var bufs: [3]ngl.Buffer = undefined;
    var buf_mems: [3]ngl.Memory = undefined;
    const buf_usgs: [3]ngl.Buffer.Usage = .{
        .{ .transfer_source = true, .transfer_dest = false },
        .{ .transfer_source = false, .transfer_dest = true },
        .{ .transfer_source = false, .transfer_dest = true },
    };
    for (0..bufs.len) |i| {
        errdefer for (0..i) |j| {
            bufs[j].deinit(gpa, dev);
            dev.free(gpa, &buf_mems[j]);
        };
        bufs[i] = try ngl.Buffer.init(gpa, dev, .{ .size = size, .usage = buf_usgs[i] });
        buf_mems[i] = blk: {
            errdefer bufs[i].deinit(gpa, dev);
            const reqs = bufs[i].getMemoryRequirements(dev);
            const idx = for (0..dev.mem_type_n) |j| {
                const idx: ngl.Memory.TypeIndex = @intCast(j);
                if (dev.mem_types[idx].properties.host_visible and
                    dev.mem_types[idx].properties.host_coherent and
                    reqs.supportsType(idx))
                {
                    break idx;
                }
            } else unreachable;
            var mem = try dev.alloc(gpa, .{ .size = reqs.size, .type_index = idx });
            errdefer dev.free(gpa, &mem);
            try bufs[i].bindMemory(dev, &mem, 0);
            break :blk mem;
        };
    }
    defer for (&bufs, &buf_mems) |*buf, *mem| {
        buf.deinit(gpa, dev);
        dev.free(gpa, mem);
    };

    var images: [2]ngl.Image = undefined;
    var img_mems: [2]ngl.Memory = undefined;
    for (0..images.len) |i| {
        errdefer for (0..i) |j| {
            images[j].deinit(gpa, dev);
            dev.free(gpa, &img_mems[j]);
        };
        images[i] = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = .rgba8_unorm,
            .width = w,
            .height = h,
            .depth_or_layers = @intCast(1 + i),
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .storage_image = true, // Pretend that we'll do something meaningful with it
                .transfer_source = true,
                .transfer_dest = true,
            },
            .misc = .{},
            .initial_layout = .undefined,
        });
        img_mems[i] = blk: {
            errdefer images[i].deinit(gpa, dev);
            const reqs = images[i].getMemoryRequirements(dev);
            const idx = for (0..dev.mem_type_n) |j| {
                const idx: ngl.Memory.TypeIndex = @intCast(j);
                if (dev.mem_types[idx].properties.device_local and reqs.supportsType(idx))
                    break idx;
            } else unreachable;
            var mem = try dev.alloc(gpa, .{ .size = reqs.size, .type_index = idx });
            errdefer dev.free(gpa, &mem);
            try images[i].bindMemory(dev, &mem, 0);
            break :blk mem;
        };
    }
    defer for (&images, &img_mems) |*image, *mem| {
        image.deinit(gpa, dev);
        dev.free(gpa, mem);
    };

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Copy from buffer #0 to image #0, then copy from image #0 to
    // both layers of image #1, then copy the first and second layers
    // of image #1 to buffer #1 and buffer #2, respectively

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.fillBuffer(&bufs[0], 0, size / 2, 0x9d);
    cmd.fillBuffer(&bufs[0], size / 2, size / 2, 0xfa);

    cmd.pipelineBarrier(&.{.{
        .buffer_dependencies = &.{.{
            .source_stage_mask = .{ .clear = true },
            .source_access_mask = .{ .memory_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .queue_transfer = null,
            .buffer = &bufs[0],
            .offset = 0,
            .size = size,
        }},
        .image_dependencies = &.{.{
            .source_stage_mask = .{},
            .source_access_mask = .{},
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .queue_transfer = null,
            .old_layout = .undefined,
            .new_layout = .transfer_dest_optimal,
            .image = &images[0],
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

    // Invert the top and bottom halves
    cmd.copyBufferToImage(&.{.{
        .buffer = &bufs[0],
        .image = &images[0],
        .image_layout = .transfer_dest_optimal,
        .image_type = .@"2d",
        .regions = &.{
            .{
                .buffer_offset = size / 2,
                .buffer_row_length = w,
                .buffer_image_height = h / 2,
                .image_aspect = .color,
                .image_level = 0,
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 0,
                .image_width = w,
                .image_height = h / 2,
                .image_depth_or_layers = 1,
            },
            .{
                .buffer_offset = 0,
                .buffer_row_length = w,
                .buffer_image_height = h / 2,
                .image_aspect = .color,
                .image_level = 0,
                .image_x = 0,
                .image_y = h / 2,
                .image_z_or_layer = 0,
                .image_width = w,
                .image_height = h / 2,
                .image_depth_or_layers = 1,
            },
        },
    }});

    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{
            .{
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .memory_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .memory_read = true, .memory_write = true },
                .queue_transfer = null,
                .old_layout = .transfer_dest_optimal,
                .new_layout = .transfer_source_optimal,
                .image = &images[0],
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            },
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .memory_read = true, .memory_write = true },
                .queue_transfer = null,
                .old_layout = .undefined,
                .new_layout = .transfer_dest_optimal,
                .image = &images[1],
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 2,
                },
            },
        },
        .by_region = false,
    }});

    // Invert the top and bottom halves for the first layer
    // For the second layer, the contents are copied as-is
    cmd.copyImage(&.{.{
        .source = &images[0],
        .source_layout = .transfer_source_optimal,
        .dest = &images[1],
        .dest_layout = .transfer_dest_optimal,
        .type = .@"2d",
        .regions = &.{
            .{
                .source_aspect = .color,
                .source_level = 0,
                .source_x = 0,
                .source_y = 0,
                .source_z_or_layer = 0,
                .dest_aspect = .color,
                .dest_level = 0,
                .dest_x = 0,
                .dest_y = 0,
                .dest_z_or_layer = 1,
                .width = w,
                .height = h,
                .depth_or_layers = 1,
            },
            .{
                .source_aspect = .color,
                .source_level = 0,
                .source_x = 0,
                .source_y = h / 2,
                .source_z_or_layer = 0,
                .dest_aspect = .color,
                .dest_level = 0,
                .dest_x = 0,
                .dest_y = 0,
                .dest_z_or_layer = 0,
                .width = w,
                .height = h / 2,
                .depth_or_layers = 1,
            },
            .{
                .source_aspect = .color,
                .source_level = 0,
                .source_x = 0,
                .source_y = 0,
                .source_z_or_layer = 0,
                .dest_aspect = .color,
                .dest_level = 0,
                .dest_x = 0,
                .dest_y = h / 2,
                .dest_z_or_layer = 0,
                .width = w,
                .height = h / 2,
                .depth_or_layers = 1,
            },
        },
    }});

    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .memory_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .queue_transfer = null,
            .old_layout = .transfer_dest_optimal,
            .new_layout = .transfer_source_optimal,
            .image = &images[1],
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 2,
            },
        }},
        .by_region = false,
    }});

    // Nothing fancy here, just copy the second image's layers
    // to mappable buffers
    cmd.copyImageToBuffer(&.{
        .{
            .buffer = &bufs[1],
            .image = &images[1],
            .image_layout = .transfer_source_optimal,
            .image_type = .@"2d",
            .regions = &.{.{
                .buffer_offset = 0,
                .buffer_row_length = w,
                .buffer_image_height = h,
                .image_aspect = .color,
                .image_level = 0,
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 0,
                .image_width = w,
                .image_height = h,
                .image_depth_or_layers = 1,
            }},
        },
        .{
            .buffer = &bufs[2],
            .image = &images[1],
            .image_layout = .transfer_source_optimal,
            .image_type = .@"2d",
            .regions = &.{.{
                .buffer_offset = 0,
                .buffer_row_length = w,
                .buffer_image_height = h,
                .image_aspect = .color,
                .image_level = 0,
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 1,
                .image_width = w,
                .image_height = h,
                .image_depth_or_layers = 1,
            }},
        },
    });

    try cmd.end();

    {
        queue_locks[queue_i].lock();
        defer queue_locks[queue_i].unlock();

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    var ps = .{
        try buf_mems[0].map(dev, 0, null),
        try buf_mems[1].map(dev, 0, null),
        try buf_mems[2].map(dev, 0, null),
    };

    // We filled the top and bottom halves of the staging buffer
    // with different values
    for (0..size / 2) |i| try testing.expectEqual(ps[0][i], 0x9d);
    for (size / 2..size) |i| try testing.expectEqual(ps[0][i], 0xfa);

    // When copying from the first image to the second's first layer,
    // we inverted the top and bottom halves, so it must match
    // the original contents of the staging buffer
    try testing.expect(std.mem.eql(u8, ps[0][0..size], ps[1][0..size]));

    // The contents of the first image were copied verbatim to the
    // second layer of the second image, so the top half must be
    // at the bottom and the bottom half at the top (relative to
    // staging buffer contents)
    try testing.expect(std.mem.eql(u8, ps[0][0 .. size / 2], ps[2][size / 2 .. size]));
    try testing.expect(std.mem.eql(u8, ps[0][size / 2 .. size], ps[2][0 .. size / 2]));
}
