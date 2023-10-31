const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;
const shd_code = @import("shd_code.zig");

test "compute dispatch" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.compute and dev.queues[i].capabilities.transfer) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    // Dimensions for the `dispatch` call
    const groups = .{ 4, 5, 1 };
    // Defined in shader code
    const local = .{ 16, 16, 1 };

    const w = groups[0] * local[0];
    const h = groups[1] * local[1];
    const size = w * h * 4;

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .storage_image = true, .transfer_source = true },
        .misc = .{},
        .initial_layout = .undefined,
    });
    var img_mem = blk: {
        errdefer image.deinit(gpa, dev);
        const mem_reqs = image.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try image.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        image.deinit(gpa, dev);
        dev.free(gpa, &img_mem);
    }
    var img_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &image,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer img_view.deinit(gpa, dev);

    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_dest = true },
    });
    var buf_mem = blk: {
        errdefer buf.deinit(gpa, dev);
        const mem_reqs = buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        buf.deinit(gpa, dev);
        dev.free(gpa, &buf_mem);
    }

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.checker_desc_bindings,
    });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var pl = blk: {
        var s = try ngl.Pipeline.initCompute(gpa, dev, .{
            .states = &.{.{
                .stage = .{
                    .stage = .compute,
                    .code = &shd_code.checker_comp_spv,
                    .name = "main",
                },
                .layout = &pl_layt,
            }},
            .cache = null,
        });
        defer gpa.free(s);
        break :blk s[0];
    };
    defer pl.deinit(gpa, dev);

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{ .storage_image = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_set = blk: {
        var s = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Write to the descriptor set before recording
    try ngl.DescriptorSet.write(gpa, dev, &.{.{
        .descriptor_set = &desc_set,
        .binding = shd_code.checker_desc_bindings[0].binding,
        .element = 0,
        .contents = .{ .storage_image = &.{.{ .view = &img_view, .layout = .general }} },
    }});

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Dispatch compute thread groups that write to the storage image
    // and then copy this image to a mappable buffer

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{},
            .source_access_mask = .{},
            .dest_stage_mask = .{ .compute_shader = true },
            .dest_access_mask = .{ .shader_storage_write = true },
            .queue_transfer = null,
            .old_layout = .undefined,
            .new_layout = .general,
            .image = &image,
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

    cmd.setPipeline(&pl);
    cmd.setDescriptors(.compute, &pl_layt, 0, &.{&desc_set});
    cmd.dispatch(groups[0], groups[1], groups[2]);

    cmd.pipelineBarrier(&.{.{
        // Leave the image in the general layout
        .global_dependencies = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
        }},
        .by_region = false,
    }});

    cmd.copyImageToBuffer(&.{.{
        .buffer = &buf,
        .image = &image,
        .image_layout = .general,
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
    }});

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

    var s = (try buf_mem.map(dev, 0, size))[0..size];

    const bw = [2]u32{ std.mem.bigToNative(u32, 0x00_00_00_ff), 0xff_ff_ff_ff };
    for (0..h) |y| {
        for (0..w) |x| {
            const cell = [2]usize{ x / local[0], y / local[1] };
            const data = bw[(cell[0] & 1) ^ (cell[1] & 1)];
            const i = (x + w * y) * 4;
            const p: *const u32 = @ptrCast(@alignCast(&s[i]));
            try testing.expectEqual(p.*, data);
        }
    }

    if (false) {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        for (0..size / 4) |k| {
            const i = k * 4;
            const p = @as(*const u32, @ptrCast(@alignCast(&s[i])));
            try str.appendSlice(switch (p.*) {
                0xff_00_00_00, 0x00_00_00_ff => " ♥",
                0xff_ff_ff_ff => " ♢",
                else => unreachable,
            });
            if ((k + 1) % w == 0) try str.append('\n');
        }
        std.debug.print("{s}", .{str.items});
    }
}
