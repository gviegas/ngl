const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "executeCommands command (copying)" {
    const ctx = context();
    const dev = &ctx.device;

    var t = try T(2).init(.{ .transfer = true });
    defer t.deinit();

    var res: [2]struct {
        buf: ngl.Buffer,
        mem: ngl.Memory,
        data: *[@TypeOf(t).size / 4]u32,
    } = undefined;
    for (&res, 0..) |*r, i| {
        errdefer for (0..i) |j| {
            res[j].buf.deinit(gpa, dev);
            dev.free(gpa, &res[j].mem);
        };
        r.buf = try ngl.Buffer.init(gpa, dev, .{
            .size = @TypeOf(t).size,
            .usage = .{ .transfer_source = true },
        });
        errdefer r.buf.deinit(gpa, dev);
        const mem_reqs = r.buf.getMemoryRequirements(dev);
        r.mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &r.mem);
        try r.buf.bind(dev, &r.mem, 0);
        r.data = @as(
            [*]u32,
            @ptrCast(@alignCast(try r.mem.map(dev, 0, null))),
        )[0 .. @TypeOf(t).size / 4];
    }
    defer for (&res) |*r| {
        r.buf.deinit(gpa, dev);
        dev.free(gpa, &r.mem);
    };

    const rec: [2]struct {
        dev: *ngl.Device,
        t: *@TypeOf(t),
        buf: *ngl.Buffer,
        data: []u32,

        fn cmdBuf1(self: @This()) void {
            errdefer |err| @panic(@errorName(err));
            @memset(self.data, @TypeOf(t).top_val);
            var cmd = try self.t.cmd_bufs[1].begin(gpa, self.dev, .{
                .one_time_submit = true,
                .inheritance = .{ .render_pass_continue = null, .query_continue = null },
            });
            cmd.copyBuffer(&.{.{
                .source = self.buf,
                .dest = &self.t.stg_buf,
                .regions = &.{.{
                    .source_offset = 0,
                    .dest_offset = 0,
                    .size = @TypeOf(t).size / 2,
                }},
            }});
            try cmd.end();
        }

        fn cmdBuf2(self: @This()) void {
            errdefer |err| @panic(@errorName(err));
            @memset(self.data, @TypeOf(t).bot_val);
            var cmd = try self.t.cmd_bufs[2].begin(gpa, self.dev, .{
                .one_time_submit = true,
                .inheritance = .{ .render_pass_continue = null, .query_continue = null },
            });
            cmd.copyBuffer(&.{.{
                .source = self.buf,
                .dest = &self.t.stg_buf,
                .regions = &.{.{
                    .source_offset = 0,
                    .dest_offset = @TypeOf(t).size / 2,
                    .size = @TypeOf(t).size / 2,
                }},
            }});
            try cmd.end();
        }
    } = .{
        .{
            .dev = dev,
            .t = &t,
            .buf = &res[0].buf,
            .data = res[0].data,
        },
        .{
            .dev = dev,
            .t = &t,
            .buf = &res[1].buf,
            .data = res[1].data,
        },
    };

    const thrds = [2]std.Thread{
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[0]).cmdBuf1, .{rec[0]}),
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[1]).cmdBuf2, .{rec[1]}),
    };
    for (thrds) |thrd| thrd.join();

    var cmd = try t.cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.executeCommands(&.{
        &t.cmd_bufs[1],
        &t.cmd_bufs[2],
    });
    try cmd.end();
    {
        ctx.lockQueue(t.queue_i);
        defer ctx.unlockQueue(t.queue_i);
        try t.queue.submit(gpa, dev, &t.fence, &.{.{
            .commands = &.{.{ .command_buffer = &t.cmd_bufs[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&t.fence});

    try t.validate();
}

test "executeCommands command (dispatching)" {
    const ctx = context();
    const dev = &ctx.device;

    var t = try T(4).init(.{ .compute = true });
    defer t.deinit();

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = @TypeOf(t).format,
        .width = @TypeOf(t).width,
        .height = @TypeOf(t).height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .storage_image = true, .transfer_source = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    defer image.deinit(gpa, dev);
    const mem_reqs = image.getMemoryRequirements(dev);
    var mem = try dev.alloc(gpa, .{
        .size = mem_reqs.size,
        .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
    });
    defer dev.free(gpa, &mem);
    try image.bind(dev, &mem, 0);
    var view = try ngl.ImageView.init(gpa, dev, .{
        .image = &image,
        .type = .@"2d",
        .format = @TypeOf(t).format,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer view.deinit(gpa, dev);

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .storage_image,
        .count = 1,
        .stage_mask = .{ .compute = true },
        .immutable_samplers = null,
    }} });
    defer set_layt.deinit(gpa, dev);
    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{ .storage_image = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    const desc_set = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
    defer gpa.free(desc_set);
    try ngl.DescriptorSet.write(gpa, dev, &.{.{
        .descriptor_set = &desc_set[0],
        .binding = 0,
        .element = 0,
        .contents = .{ .storage_image = &.{.{
            .view = &view,
            .layout = .general,
        }} },
    }});

    const lwidth = @TypeOf(t).width / 2;
    const rwidth = lwidth + (@TypeOf(t).width & 1);
    const height = @TypeOf(t).height / 2;

    const consts = blk: {
        var consts: [12]ngl.ShaderStage.Specialization.Constant = undefined;
        for (&consts, 0..) |*c, i|
            c.* = .{
                .id = @intCast(i % 3),
                .offset = @intCast(i * 4),
                .size = 4,
            };
        break :blk consts;
    };
    const const_data: [12]u32 = .{
        0,      0,      @TypeOf(t).top_val,
        lwidth, 0,      @TypeOf(t).top_val,
        lwidth, height, @TypeOf(t).bot_val,
        0,      height, @TypeOf(t).bot_val,
    };

    const states = blk: {
        var states = [_]ngl.ComputeState{.{
            .stage = .{
                .code = &comp_spv,
                .name = "main",
                .specialization = undefined,
            },
            .layout = &pl_layt,
        }} ** 4;
        for (&states, 0..) |*state, i|
            state.stage.specialization = .{
                .constants = consts[i * 3 .. i * 3 + 3],
                .data = @as([*]const u8, @ptrCast(&const_data))[0 .. const_data.len * 4],
            };
        break :blk states;
    };
    const pls = try ngl.Pipeline.initCompute(gpa, dev, .{
        .states = &states,
        .cache = null,
    });
    defer {
        for (pls) |*pl| pl.deinit(gpa, dev);
        gpa.free(pls);
    }

    var rem: u3 = 4;

    const rec: [4]struct {
        dev: *ngl.Device,
        pl_layt: *ngl.PipelineLayout,
        desc_set: *ngl.DescriptorSet,
        pl: *ngl.Pipeline,
        cmd_buf: *ngl.CommandBuffer,
        wg_count: [3]u32,
        rem: *u3,

        fn cmdBuf(self: @This()) void {
            errdefer |err| @panic(@errorName(err));
            var cmd = try self.cmd_buf.begin(gpa, self.dev, .{
                .one_time_submit = true,
                .inheritance = .{ .render_pass_continue = null, .query_continue = null },
            });
            cmd.setDescriptors(.compute, self.pl_layt, 0, &.{self.desc_set});
            cmd.setPipeline(self.pl);
            cmd.dispatch(self.wg_count[0], self.wg_count[1], self.wg_count[2]);
            try cmd.end();
            _ = @atomicRmw(@TypeOf(self.rem.*), self.rem, .Sub, 1, .AcqRel);
        }
    } = .{
        // Top-left
        .{
            .dev = dev,
            .pl_layt = &pl_layt,
            .desc_set = &desc_set[0],
            .pl = &pls[0],
            .cmd_buf = &t.cmd_bufs[1],
            .wg_count = .{ lwidth, height, 1 },
            .rem = &rem,
        },
        // Top-right
        .{
            .dev = dev,
            .pl_layt = &pl_layt,
            .desc_set = &desc_set[0],
            .pl = &pls[1],
            .cmd_buf = &t.cmd_bufs[2],
            .wg_count = .{ rwidth, height, 1 },
            .rem = &rem,
        },
        // Bottom-right
        .{
            .dev = dev,
            .pl_layt = &pl_layt,
            .desc_set = &desc_set[0],
            .pl = &pls[2],
            .cmd_buf = &t.cmd_bufs[3],
            .wg_count = .{ rwidth, height, 1 },
            .rem = &rem,
        },
        // Bottom-left
        .{
            .dev = dev,
            .pl_layt = &pl_layt,
            .desc_set = &desc_set[0],
            .pl = &pls[3],
            .cmd_buf = &t.cmd_bufs[4],
            .wg_count = .{ lwidth, height, 1 },
            .rem = &rem,
        },
    };

    const thrds = [4]std.Thread{
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[0]).cmdBuf, .{rec[0]}),
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[1]).cmdBuf, .{rec[1]}),
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[2]).cmdBuf, .{rec[2]}),
        try std.Thread.spawn(.{ .allocator = gpa }, @TypeOf(rec[3]).cmdBuf, .{rec[3]}),
    };
    defer for (thrds) |thrd| thrd.join();

    var cmd = try t.cmd_bufs[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
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
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        }},
        .by_region = false,
    }});
    while (@atomicLoad(@TypeOf(rem), &rem, .Acquire) > 0) {}
    cmd.executeCommands(blk: {
        var ptrs: [rec.len]*ngl.CommandBuffer = undefined;
        for (&ptrs, t.cmd_bufs[1..]) |*p, *c| p.* = c;
        break :blk &ptrs;
    });
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
            .queue_transfer = null,
            .old_layout = .general,
            .new_layout = .transfer_source_optimal,
            .image = &image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        }},
        .by_region = true,
    }});
    cmd.copyImageToBuffer(&.{.{
        .buffer = &t.stg_buf,
        .image = &image,
        .image_layout = .transfer_source_optimal,
        .image_type = .@"2d",
        .regions = &.{.{
            .buffer_offset = 0,
            .buffer_row_length = @TypeOf(t).width,
            .buffer_image_height = @TypeOf(t).height,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = @TypeOf(t).width,
            .image_height = @TypeOf(t).height,
            .image_depth_or_layers = 1,
        }},
    }});
    try cmd.end();
    {
        ctx.lockQueue(t.queue_i);
        defer ctx.unlockQueue(t.queue_i);
        try t.queue.submit(gpa, dev, &t.fence, &.{.{
            .commands = &.{.{ .command_buffer = &t.cmd_bufs[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&t.fence});

    try t.validate();
}

fn T(comptime cmd_buf_sec_n: u32) type {
    return struct {
        queue_i: ngl.Queue.Index,
        queue: *ngl.Queue,
        // We want to record in parallel
        cmd_pools: [1 + cmd_buf_sec_n]ngl.CommandPool,
        cmd_bufs: [1 + cmd_buf_sec_n]ngl.CommandBuffer,
        fence: ngl.Fence,
        stg_buf: ngl.Buffer,
        stg_mem: ngl.Memory,
        stg_data: []u8,

        const format = ngl.Format.r32_uint;
        const width = 75;
        const height = 100;
        comptime {
            if (height & 1 != 0) unreachable;
        }
        const size = 4 * width * height;

        // The values that `validate` expects in the top/bottom
        // halves of `stg_data`
        const top_val: u32 = 0xabeeface;
        const bot_val: u32 = 0xdeadd0d0;

        fn init(capabilities: ngl.Queue.Capabilities) !@This() {
            const dev = &context().device;
            const queue_i = dev.findQueue(capabilities, null) orelse return error.SkipZigTest;

            const queue = &dev.queues[queue_i];
            var cmd_pools: [1 + cmd_buf_sec_n]ngl.CommandPool = undefined;
            for (&cmd_pools, 0..) |*cmd_pool, i|
                cmd_pool.* = ngl.CommandPool.init(gpa, dev, .{ .queue = queue }) catch |err| {
                    for (0..i) |j| cmd_pools[j].deinit(gpa, dev);
                    return err;
                };
            errdefer for (&cmd_pools) |*cmd_pool| cmd_pool.deinit(gpa, dev);
            const cmd_bufs = blk: {
                var cmd_bufs: [1 + cmd_buf_sec_n]ngl.CommandBuffer = undefined;
                var s = try cmd_pools[0].alloc(gpa, dev, .{ .level = .primary, .count = 1 });
                cmd_bufs[0] = s[0];
                gpa.free(s);
                for (cmd_pools[1..], cmd_bufs[1..]) |*cmd_pool, *cmd_buf| {
                    s = try cmd_pool.alloc(gpa, dev, .{ .level = .secondary, .count = 1 });
                    cmd_buf.* = s[0];
                    gpa.free(s);
                }
                break :blk cmd_bufs;
            };

            var fence = try ngl.Fence.init(gpa, dev, .{});
            errdefer fence.deinit(gpa, dev);

            var stg_buf = try ngl.Buffer.init(gpa, dev, .{
                .size = size,
                .usage = .{ .transfer_source = true, .transfer_dest = true },
            });
            errdefer stg_buf.deinit(gpa, dev);
            const stg_reqs = stg_buf.getMemoryRequirements(dev);
            var stg_mem = try dev.alloc(gpa, .{
                .size = stg_reqs.size,
                .type_index = stg_reqs.findType(dev.*, .{
                    .host_visible = true,
                    .host_coherent = true,
                }, null).?,
            });
            errdefer dev.free(gpa, &stg_mem);
            try stg_buf.bind(dev, &stg_mem, 0);
            const stg_data = (try stg_mem.map(dev, 0, size))[0..size];

            return .{
                .queue_i = queue_i,
                .queue = queue,
                .cmd_pools = cmd_pools,
                .cmd_bufs = cmd_bufs,
                .fence = fence,
                .stg_buf = stg_buf,
                .stg_mem = stg_mem,
                .stg_data = stg_data,
            };
        }

        fn validate(self: @This()) !void {
            const s = @as([*]const u32, @ptrCast(@alignCast(self.stg_data)))[0 .. size / 4];
            for (0..height / 2) |y| {
                for (0..width) |x| {
                    const i = y * width + x;
                    const j = i + width * height / 2;
                    try testing.expectEqual(top_val, s[i]);
                    try testing.expectEqual(bot_val, s[j]);
                }
            }
        }

        fn deinit(self: *@This()) void {
            const dev = &context().device;
            dev.free(gpa, &self.stg_mem);
            self.stg_buf.deinit(gpa, dev);
            for (&self.cmd_pools) |*cmd_pool| cmd_pool.deinit(gpa, dev);
        }
    };
}

// #version 460 core
//
// layout(constant_id = 0) const uint offset_x = 0;
// layout(constant_id = 1) const uint offset_y = 0;
// layout(constant_id = 2) const uint value = 0;
//
// layout(set = 0, binding = 0, r32ui) writeonly uniform uimage2D storage;
//
// void main() {
//     const uvec2 gid = gl_GlobalInvocationID.xy;
//     imageStore(storage, ivec2(gid + uvec2(offset_x, offset_y)), uvec4(value));
// }
const comp_spv align(4) = [740]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x6,  0x0, 0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xc,  0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x3,  0x0, 0x11, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x9,  0x0, 0xf,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x32, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x32, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x33, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x32, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x33, 0x0,  0x7,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x1d, 0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x4f, 0x0, 0x7,  0x0, 0x7,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x9,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x80, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x7c, 0x0,  0x4,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x63, 0x0,  0x4,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};
