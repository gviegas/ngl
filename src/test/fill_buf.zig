const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "fillBuffer command" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = for (0..dev.queue_n) |i| {
        // TODO: Vulkan 1.0 doesn't allow this command in transfer-only queues
        //if (dev.queues[i].capabilities.transfer) break i;
        if (dev.queues[i].capabilities.graphics or dev.queues[i].capabilities.compute) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const size = 4096;
    const off = 1024;

    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_dest = true },
    });
    var mem = blk: {
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
        dev.free(gpa, &mem);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.fillBuffer(&buf, 0, off, 0x89);
    cmd.fillBuffer(&buf, off, null, 0xc1);
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

    var p = try mem.map(dev, 0, size);
    try testing.expect(std.mem.eql(u8, p[0..off], &[_]u8{0x89} ** off));
    try testing.expect(std.mem.eql(u8, p[off..size], &[_]u8{0xc1} ** (size - off)));
}
