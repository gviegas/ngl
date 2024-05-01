const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "dispatch command" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .compute = true }, null) orelse return error.SkipZigTest;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    // Dimensions for the `dispatch` call.
    const groups = .{ 4, 5, 1 };
    // Defined in shader code.
    const local = .{ 8, 8, 1 };

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
    });
    var img_mem = blk: {
        errdefer image.deinit(gpa, dev);
        const mem_reqs = image.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try image.bind(dev, &mem, 0);
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
            .level = 0,
            .levels = 1,
            .layer = 0,
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
        try buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        buf.deinit(gpa, dev);
        dev.free(gpa, &buf_mem);
    }

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .storage_image,
        .count = 1,
        .shader_mask = .{ .compute = true },
        .immutable_samplers = &.{},
    }} });
    defer set_layt.deinit(gpa, dev);

    var shd_layt = try ngl.ShaderLayout.init(gpa, dev, .{
        .set_layouts = &.{&set_layt},
        .push_constants = &.{},
    });
    defer shd_layt.deinit(gpa, dev);

    var shader = try ngl.Shader.init(gpa, dev, &.{.{
        .type = .compute,
        .next = .{},
        .code = &comp_spv,
        .name = "main",
        .set_layouts = &.{&set_layt},
        .push_constants = &.{},
        .specialization = null,
        .link = false,
    }});
    defer {
        if (shader[0]) |*shd| shd.deinit(gpa, dev) else |_| {}
        gpa.free(shader);
    }

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{ .storage_image = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_set = blk: {
        const s = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Write to the descriptor set before recording.
    try ngl.DescriptorSet.write(gpa, dev, &.{.{
        .descriptor_set = &desc_set,
        .binding = 0,
        .element = 0,
        .contents = .{ .storage_image = &.{.{ .view = &img_view, .layout = .general }} },
    }});

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Dispatch compute thread groups that write to the storage image
    // and then copy this image to a mappable buffer.

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.barrier(&.{.{
        .image = &.{.{
            .source_stage_mask = .{},
            .source_access_mask = .{},
            .dest_stage_mask = .{ .compute_shader = true },
            .dest_access_mask = .{ .shader_storage_write = true },
            .queue_transfer = null,
            .old_layout = .unknown,
            .new_layout = .general,
            .image = &image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        }},
    }});

    cmd.setShaders(&.{.compute}, &.{if (shader[0]) |*shd| shd else |err| return err});
    cmd.setDescriptors(.compute, &shd_layt, 0, &.{&desc_set});
    cmd.dispatch(groups[0], groups[1], groups[2]);

    cmd.barrier(&.{.{
        // Leave the image in the general layout.
        .global = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
        }},
    }});

    cmd.copyImageToBuffer(&.{.{
        .buffer = &buf,
        .image = &image,
        .image_layout = .general,
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
        ctx.lockQueue(queue_i);
        ctx.unlockQueue(queue_i);

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

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ @src().fn_name ++ "\n");
        for (0..size / 4) |k| {
            const i = k * 4;
            const p = @as(*const u32, @ptrCast(@alignCast(&s[i])));
            try str.appendSlice(switch (p.*) {
                0xff_00_00_00, 0x00_00_00_ff => "⚫",
                0xff_ff_ff_ff => "⚪",
                else => unreachable,
            });
            if ((k + 1) % w == 0) try str.append('\n');
        }
        try writer.print("{s}", .{str.items});
    }
}

// #version 460 core
//
// layout(local_size_x = 8, local_size_y = 8) in;
//
// layout(set = 0, binding = 0, rgba8) writeonly uniform image2D storage;
//
// const vec4 color[2] = { vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0) };
//
// void main() {
//     uvec2 nm = gl_WorkGroupID.xy & uvec2(1, 1);
//     uint idx = nm.x ^ nm.y;
//     vec4 data = color[idx];
//
//     ivec2 p = ivec2(gl_GlobalInvocationID.xy);
//
//     imageStore(storage, p, data);
// }
const comp_spv align(4) = [1272]u8{
    0x3,  0x2, 0x23, 0x7,  0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x3a, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0,  0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0,  0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x2e, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x34, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x34, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x34, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0,  0x39, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xa,  0x0, 0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x2c, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x80, 0x3f, 0x2c, 0x0,  0x7,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x2c, 0x0, 0x7,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x2c, 0x0,  0x5,  0x0,
    0x1f, 0x0, 0x0,  0x0,  0x24, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0,  0x26, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0,  0x2c, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x9,  0x0,  0x32, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x33, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x32, 0x0, 0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x33, 0x0,  0x0,  0x0,  0x34, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x38, 0x0,  0x0,  0x0,
    0x8,  0x0, 0x0,  0x0,  0x2c, 0x0,  0x6,  0x0,  0xa,  0x0,  0x0,  0x0,  0x39, 0x0,  0x0,  0x0,
    0x38, 0x0, 0x0,  0x0,  0x38, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0xf8, 0x0, 0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x1d, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x27, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x2c, 0x0,  0x0,  0x0,
    0x2d, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x4f, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0xc7, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x12, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0xc6, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0,  0x13, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x25, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x27, 0x0, 0x0,  0x0,  0x24, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x28, 0x0, 0x0,  0x0,  0x27, 0x0,  0x0,  0x0,  0x25, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x1b, 0x0, 0x0,  0x0,  0x29, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x1d, 0x0, 0x0,  0x0,  0x29, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x2f, 0x0, 0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x4f, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x30, 0x0, 0x0,  0x0,  0x2f, 0x0,  0x0,  0x0,  0x2f, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x7c, 0x0,  0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x31, 0x0,  0x0,  0x0,
    0x30, 0x0, 0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x2d, 0x0,  0x0,  0x0,  0x31, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x32, 0x0,  0x0,  0x0,  0x35, 0x0,  0x0,  0x0,  0x34, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x36, 0x0,  0x0,  0x0,  0x2d, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x37, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x63, 0x0, 0x4,  0x0,  0x35, 0x0,  0x0,  0x0,  0x36, 0x0,  0x0,  0x0,  0x37, 0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};
