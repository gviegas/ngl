const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "dispatchIndirect command" {
    const ctx = context();
    const dev = &ctx.device;
    if (!ngl.Feature.get(gpa, &ctx.instance, ctx.device_desc, .core).?.dispatch.indirect_command)
        return error.SkipZigTest;

    var indir_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = @sizeOf(ngl.Cmd.DispatchIndirectCommand),
        .usage = .{ .indirect_buffer = true, .transfer_dest = true },
    });
    errdefer indir_buf.deinit(gpa, dev);
    var indir_mem = blk: {
        const mem_reqs = indir_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try indir_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &indir_mem);

    const wg_count = .{ 32, 20, 11 };
    const invoc = wg_count[0] * wg_count[1] * wg_count[2];

    var stor_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = 4 * invoc,
        .usage = .{ .storage_buffer = true, .transfer_source = true },
    });
    defer stor_buf.deinit(gpa, dev);
    var stor_mem = blk: {
        const mem_reqs = stor_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try stor_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &stor_mem);

    var stg_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = @max(@sizeOf(ngl.Cmd.DispatchIndirectCommand), 4 * invoc),
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    defer stg_buf.deinit(gpa, dev);
    var stg_mem = blk: {
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
    defer dev.free(gpa, &stg_mem);

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &.{.{
            .binding = 0,
            .type = .storage_buffer,
            .count = 1,
            .stage_mask = .{ .compute = true },
            .immutable_samplers = null,
        }},
    });
    defer set_layt.deinit(gpa, dev);
    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

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
            .range = 4 * invoc,
        }} },
    }});

    var pl = blk: {
        const s = try ngl.Pipeline.initCompute(gpa, dev, .{
            .states = &.{.{
                .stage = .{ .code = &comp_spv, .name = "main" },
                .layout = &pl_layt,
            }},
            .cache = null,
        });
        defer gpa.free(s);
        break :blk s[0];
    };
    defer pl.deinit(gpa, dev);

    const queue_i = dev.findQueue(.{ .compute = true }, null).?;

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.copyBuffer(&.{.{
        .source = &stg_buf,
        .dest = &indir_buf,
        .regions = &.{.{
            .source_offset = 0,
            .dest_offset = 0,
            .size = @sizeOf(ngl.Cmd.DispatchIndirectCommand),
        }},
    }});
    cmd.pipelineBarrier(&.{.{
        .buffer_dependencies = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{ .draw_indirect = true },
            .dest_access_mask = .{ .indirect_command_read = true },
            .queue_transfer = null,
            .buffer = &indir_buf,
            .offset = 0,
            .size = null,
        }},
        .by_region = false,
    }});
    cmd.setPipeline(&pl);
    cmd.setDescriptors(.compute, &pl_layt, 0, &.{&desc_set});
    cmd.dispatchIndirect(&indir_buf, 0);
    cmd.pipelineBarrier(&.{.{
        .buffer_dependencies = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true },
            .queue_transfer = null,
            .buffer = &stor_buf,
            .offset = 0,
            .size = null,
        }},
        .by_region = false,
    }});
    cmd.copyBuffer(&.{.{
        .source = &stor_buf,
        .dest = &stg_buf,
        .regions = &.{.{
            .source_offset = 0,
            .dest_offset = 0,
            .size = 4 * invoc,
        }},
    }});
    try cmd.end();

    const stg_data = try stg_mem.map(dev, 0, null);

    const indir_cmd = ngl.Cmd.DispatchIndirectCommand{
        .group_count_x = wg_count[0],
        .group_count_y = wg_count[1],
        .group_count_z = wg_count[2],
    };
    @memcpy(stg_data, @as([*]const u8, @ptrCast(&indir_cmd))[0..@sizeOf(@TypeOf(indir_cmd))]);

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);
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

    // We should have dispatched a total of `invoc` invocations,
    // each of which wrote `invoc` - <flattened invocation index>
    // to a single location of `stor_buf`

    const s = @as([*]const u32, @ptrCast(@alignCast(stg_data)))[0..invoc];
    for (s, 0..) |x, i|
        try testing.expectEqual(x, invoc - i);
}

// #version 460 core
//
// layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
//
// layout(set = 0, binding = 0) buffer Storage {
//     uint data[];
// } storage;
//
// void main() {
//     const uint idx = gl_GlobalInvocationID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
//         gl_GlobalInvocationID.y * gl_NumWorkGroups.x +
//         gl_GlobalInvocationID.x;
//     const uint len = gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z;
//     storage.data[idx] = len - idx;
// }
const comp_spv align(4) = [1212]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x38, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x2c, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x23, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x2c, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x37, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1d, 0x0,  0x3,  0x0,  0x2b, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x3,  0x0,  0x2c, 0x0,  0x0,  0x0,  0x2b, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x2d, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x2c, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x2d, 0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0x2f, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x2f, 0x0,  0x0,  0x0,  0x30, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x35, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x2c, 0x0, 0x6,  0x0, 0x9,  0x0,  0x0,  0x0,  0x37, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0xd,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0xc,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x84, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x14, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x41, 0x0, 0x5,  0x0, 0xd,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x84, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x17, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x84, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x80, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x1f, 0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x80, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x21, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x8,  0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x23, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x24, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x41, 0x0, 0x5,  0x0, 0xd,  0x0,  0x0,  0x0,  0x25, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x25, 0x0, 0x0,  0x0, 0x84, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x27, 0x0,  0x0,  0x0,
    0x24, 0x0, 0x0,  0x0, 0x26, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x28, 0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x29, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,  0x84, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x2a, 0x0,  0x0,  0x0,  0x27, 0x0,  0x0,  0x0,  0x29, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x22, 0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x31, 0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x32, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x33, 0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,  0x82, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x34, 0x0,  0x0,  0x0,  0x32, 0x0,  0x0,  0x0,  0x33, 0x0,  0x0,  0x0,
    0x41, 0x0, 0x6,  0x0, 0x35, 0x0,  0x0,  0x0,  0x36, 0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,
    0x30, 0x0, 0x0,  0x0, 0x31, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x36, 0x0,  0x0,  0x0,
    0x34, 0x0, 0x0,  0x0, 0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};
