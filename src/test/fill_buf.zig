const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;

test "fillBuffer command" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.transfer) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const size = 4096;
    const off = 1024;

    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_source = false, .transfer_dest = true },
    });
    var mem = blk: {
        errdefer buf.deinit(gpa, dev);
        const reqs = buf.getMemoryRequirements(dev);
        const idx = for (0..dev.mem_type_n) |i| {
            const idx: ngl.Memory.TypeIndex = @intCast(i);
            if (dev.mem_types[idx].properties.host_visible and
                dev.mem_types[idx].properties.host_coherent and
                reqs.supportsMemoryType(idx))
            {
                break idx;
            }
        } else unreachable;
        var mem = try dev.alloc(gpa, .{ .size = reqs.size, .mem_type_index = idx });
        errdefer dev.free(gpa, &mem);
        try buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        buf.deinit(gpa, dev);
        dev.free(gpa, &mem);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.fillBuffer(&buf, 0, off, 0x89);
    cmd.fillBuffer(&buf, off, null, 0xc1);
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

    var p = try mem.map(dev, 0, size);
    try testing.expect(std.mem.eql(u8, p[0..off], &[_]u8{0x89} ** off));
    try testing.expect(std.mem.eql(u8, p[off..size], &[_]u8{0xc1} ** (size - off)));
}
