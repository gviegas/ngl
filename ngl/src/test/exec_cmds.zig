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
                    try testing.expectEqual(s[i], top_val);
                    try testing.expectEqual(s[j], bot_val);
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
