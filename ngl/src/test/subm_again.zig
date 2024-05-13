const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "re-submission of command buffer recording" {
    const ctx = context();
    const dev = &ctx.device;
    //const queue_i = dev.findQueue(.{ .transfer = true }, null).?;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;
    const queue = &dev.queues[queue_i];

    const size = 8192;

    var res: [3]struct {
        buf: ngl.Buffer,
        mem: ngl.Memory,
        data: ?[]u8,
    } = undefined;
    for (&res, [_]bool{ false, false, true }, 0..) |*r, mappable, i| {
        errdefer for (0..i) |j| {
            res[j].buf.deinit(gpa, dev);
            dev.free(gpa, &res[j].mem);
        };
        r.buf = try ngl.Buffer.init(gpa, dev, .{
            .size = size,
            .usage = .{ .transfer_source = !mappable, .transfer_dest = true },
        });
        errdefer r.buf.deinit(gpa, dev);
        const mem_reqs = r.buf.getMemoryRequirements(dev);
        r.mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .device_local = !mappable,
                .host_visible = mappable,
                .host_coherent = mappable,
            }, null).?,
        });
        errdefer dev.free(gpa, &r.mem);
        try r.buf.bind(dev, &r.mem, 0);
        r.data = if (mappable) try r.mem.map(dev, 0, size) else null;
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = queue });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_bufs = (try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 2 }))[0..2];
    defer gpa.free(cmd_bufs);

    const values = [2]u8{ 0b10101010, 0b01101101 };

    for (0..2) |i| {
        var cmd = try cmd_bufs[i].begin(gpa, dev, .{
            .one_time_submit = false,
            .inheritance = null,
        });
        cmd.clearBuffer(&res[i].buf, 0, size, values[i]);
        cmd.barrier(&.{.{
            .global = &.{.{
                .source_stage_mask = .{ .clear = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
            }},
        }});
        cmd.copyBuffer(&.{.{
            .source = &res[i].buf,
            .dest = &res[2].buf,
            .regions = &.{.{
                .source_offset = 0,
                .dest_offset = 0,
                .size = size,
            }},
        }});
        try cmd.end();
    }

    var fence = try ngl.Fence.init(gpa, dev, .{ .status = .unsignaled });
    defer fence.deinit(gpa, dev);

    for (0..5) |i| {
        ctx.lockQueue(queue_i);

        queue.submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_bufs[i & 1] }},
            .wait = &.{},
            .signal = &.{},
        }}) catch |err| {
            ctx.unlockQueue(queue_i);
            return err;
        };

        ctx.unlockQueue(queue_i);

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});
        try ngl.Fence.reset(gpa, dev, &.{&fence});

        try testing.expect(std.mem.allEqual(u8, res[2].data.?, values[i & 1]));
    }
}
