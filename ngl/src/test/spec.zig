const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "shader specialization" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .compute = true }, null) orelse return error.SkipZigTest;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const groups = .{ 6, 1, 1 };
    const local = .{ 13, 1, 1 };
    // Two dispatch calls.
    const size = (groups[0] * 2) * local[0] * 4;

    var stor_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .storage_buffer = true, .transfer_source = true },
    });
    var stor_mem = blk: {
        errdefer stor_buf.deinit(gpa, dev);
        const mem_reqs = stor_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try stor_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        stor_buf.deinit(gpa, dev);
        dev.free(gpa, &stor_mem);
    }

    var stg_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_dest = true },
    });
    var stg_mem = blk: {
        errdefer stg_buf.deinit(gpa, dev);
        const mem_reqs = stg_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try stg_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        stg_buf.deinit(gpa, dev);
        dev.free(gpa, &stg_mem);
    }

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .storage_buffer,
        .count = 1,
        .shader_mask = .{ .compute = true },
        .immutable_samplers = &.{},
    }} });
    errdefer set_layt.deinit(gpa, dev);

    var shd_layt = try ngl.ShaderLayout.init(gpa, dev, .{
        .set_layouts = &.{&set_layt},
        .push_constants = &.{},
    });
    errdefer shd_layt.deinit(gpa, dev);

    const values = .{ '🦄', '🐚' };
    const spec_data: struct {
        value: u32 = values[0],
        even: u32 = @intFromBool(true),
        local_x: u32 = local[0],
    } = .{};
    const spec_data_2: struct {
        value: u32 = values[1],
        local_x: u32 = local[0],
    } = .{};

    const spec = ngl.Shader.Specialization{
        .constants = &.{
            .{
                .id = 0,
                .offset = @offsetOf(@TypeOf(spec_data), "value"),
                .size = 4,
            },
            .{
                .id = 1,
                .offset = @offsetOf(@TypeOf(spec_data), "even"),
                .size = 4,
            },
            .{
                .id = 3,
                .offset = @offsetOf(@TypeOf(spec_data), "local_x"),
                .size = 4,
            },
        },
        .data = @as([*]const u8, @ptrCast(&spec_data))[0..@sizeOf(@TypeOf(spec_data))],
    };
    const spec_2 = ngl.Shader.Specialization{
        .constants = &.{
            .{
                .id = 3,
                .offset = @offsetOf(@TypeOf(spec_data_2), "local_x"),
                .size = 4,
            },
            .{
                .id = 0,
                .offset = @offsetOf(@TypeOf(spec_data_2), "value"),
                .size = 4,
            },
        },
        .data = @as([*]const u8, @ptrCast(&spec_data_2))[0..@sizeOf(@TypeOf(spec_data_2))],
    };

    const shaders = try ngl.Shader.init(gpa, dev, &.{
        .{
            .type = .compute,
            .next = .{},
            .code = &comp_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &.{},
            .specialization = spec,
            .link = false,
        },
        .{
            .type = .compute,
            .next = .{},
            .code = &comp_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &.{},
            .specialization = spec_2,
            .link = false,
        },
    });
    defer {
        for (shaders) |*shd|
            if (shd.*) |*s| s.deinit(gpa, dev) else |_| {};
        gpa.free(shaders);
    }

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{ .storage_buffer = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_set = blk: {
        const s = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
        defer gpa.free(s);
        break :blk s[0];
    };
    try ngl.DescriptorSet.write(gpa, dev, &.{.{
        .descriptor_set = &desc_set,
        .binding = 0,
        .element = 0,
        .contents = .{ .storage_buffer = &.{.{
            .buffer = &stor_buf,
            .offset = 0,
            .range = size,
        }} },
    }});

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.setDescriptors(.compute, &shd_layt, 0, &.{&desc_set});
    cmd.setShaders(&.{.compute}, &.{if (shaders[0]) |*shd| shd else |err| return err});
    cmd.dispatch(groups[0], groups[1], groups[2]);
    cmd.setShaders(&.{.compute}, &.{if (shaders[1]) |*shd| shd else |err| return err});
    cmd.dispatch(groups[0], groups[1], groups[2]);
    cmd.pipelineBarrier(&.{.{
        .global_dependencies = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
        }},
        .by_region = false,
    }});
    cmd.copyBuffer(&.{.{
        .source = &stor_buf,
        .dest = &stg_buf,
        .regions = &.{.{
            .source_offset = 0,
            .dest_offset = 0,
            .size = size,
        }},
    }});
    try cmd.end();

    {
        ctx.lockQueue(queue_i);
        defer ctx.unlockQueue(queue_i);

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    // The two shaders use the same shader code, but with different
    // specializations to configure their behavior such that:
    //  - `shaders[0]` writes `values[0]` to even "rows"
    //  - `shaders[1]` writes `values[1]` to odd "rows"
    // (here a row means a contiguous range of length `local[0]`
    // within the storage buffer).

    const p = try stg_mem.map(dev, 0, null);
    const s = @as([*]const u32, @ptrCast(@alignCast(p)))[0 .. size / 4];

    const spans: [2][local[0]]u32 = .{
        [_]u32{values[0]} ** local[0],
        [_]u32{values[1]} ** local[0],
    };

    for (0..groups[0]) |i| {
        const off = i * 2 * local[0];
        try testing.expect(std.mem.eql(u32, &spans[0], s[off .. off + local[0]]));
        const off_2 = off + local[0];
        try testing.expect(std.mem.eql(u32, &spans[1], s[off_2 .. off_2 + local[0]]));
    }

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ @src().fn_name ++ "\n");
        var seq: [7]u8 = undefined;
        for (0..groups[0] * 2) |i| {
            for (0..local[0]) |j| {
                const value: u21 = @truncate(s[i * local[0] + j]);
                const seq_s = seq[0..try std.unicode.utf8Encode(value, &seq)];
                try str.appendSlice(seq_s);
            }
            try str.append('\n');
        }
        try writer.print("{s}", .{str.items});
    }
}

// #version 460 core
//
// layout(local_size_x_id = 3) in;
//
// layout(constant_id = 0) const uint value = 0xbeeface;
// layout(constant_id = 1) const bool even = false;
//
// layout(set = 0, binding = 0) buffer Storage {
//     uint data[];
// } storage;
//
// void main() {
//     uint i = gl_WorkGroupSize.x * gl_WorkGroupID.x * 2 + gl_LocalInvocationID.x;
//     if (!even)
//         i += gl_WorkGroupSize.x;
//     storage.data[i] = value;
// }
const comp_spv align(4) = [1060]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x2d, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x17, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x23, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x24, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x23, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x24, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x32, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x33, 0x0,  0x6,  0x0,  0xb,  0x0,  0x0,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x14, 0x0, 0x2,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x31, 0x0,  0x3,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x34, 0x0,  0x5,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0xa8, 0x0, 0x0,  0x0, 0x1c, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x3,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x3,  0x0,  0x24, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x25, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x24, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x25, 0x0,  0x0,  0x0,  0x26, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0x27, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x27, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x32, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0xce, 0xfa, 0xee, 0xb,
    0x20, 0x0, 0x4,  0x0, 0x2b, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x8,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x41, 0x0, 0x5,  0x0, 0x11, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x84, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x84, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x14, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x18, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x80, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x8,  0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0xf7, 0x0, 0x3,  0x0, 0x1f, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0xfa, 0x0,  0x4,  0x0,
    0x1d, 0x0, 0x0,  0x0, 0x1e, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x8,  0x0,  0x0,  0x0,  0x80, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x22, 0x0, 0x0,  0x0, 0x21, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x22, 0x0,  0x0,  0x0,  0xf9, 0x0,  0x2,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0xf8, 0x0, 0x2,  0x0, 0x1f, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x29, 0x0, 0x0,  0x0, 0x8,  0x0,  0x0,  0x0,  0x41, 0x0,  0x6,  0x0,  0x2b, 0x0,  0x0,  0x0,
    0x2c, 0x0, 0x0,  0x0, 0x26, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,  0x29, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x2c, 0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};
