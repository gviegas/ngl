const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;

test "copyBuffer command" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.transfer) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const sizes = [2]u64{ 2048, 8192 };

    var bufs: [2]ngl.Buffer = undefined;
    var mems: [2]ngl.Memory = undefined;
    for (0..bufs.len) |i| {
        errdefer for (0..i) |j| {
            bufs[i].deinit(gpa, dev);
            dev.free(gpa, &mems[j]);
        };
        bufs[i] = try ngl.Buffer.init(gpa, dev, .{
            .size = sizes[i],
            .usage = .{
                .transfer_source = true,
                .transfer_dest = true,
            },
        });
        mems[i] = blk: {
            errdefer bufs[i].deinit(gpa, dev);
            const reqs = bufs[i].getMemoryRequirements(dev);
            const idx = for (0..dev.mem_type_n) |j| {
                const idx: ngl.Memory.TypeIndex = @intCast(j);
                if (dev.mem_types[idx].properties.host_visible and
                    dev.mem_types[idx].properties.host_coherent and
                    reqs.supportsMemoryType(idx))
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
    defer for (&bufs, &mems) |*buf, *mem| {
        buf.deinit(gpa, dev);
        dev.free(gpa, mem);
    };

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.copyBuffer(&.{.{
        .source = &bufs[0],
        .dest = &bufs[1],
        .regions = &.{
            .{
                .source_offset = 0,
                .dest_offset = sizes[0],
                .size = sizes[0],
            },
            .{
                .source_offset = sizes[0] / 2 - sizes[0] / 4,
                .dest_offset = 0,
                .size = sizes[0] / 2,
            },
        },
    }});
    try cmd.end();

    var p = try mems[0].map(dev, 0, null);
    @memset(p[0 .. sizes[0] / 2], 0x4e);
    @memset(p[sizes[0] / 2 .. sizes[0]], 0xa7);
    mems[0].unmap(dev);
    @memset((try mems[1].map(dev, 0, null))[0..sizes[1]], 0xff);
    mems[1].unmap(dev);

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

    var ps = .{ try mems[0].map(dev, 0, null), try mems[1].map(dev, 0, null) };
    for (0..sizes[0] / 2) |i| try testing.expectEqual(ps[0][i], 0x4e);
    for (sizes[0] / 2..sizes[0]) |i| try testing.expectEqual(ps[0][i], 0xa7);
    try testing.expect(std.mem.eql(
        u8,
        ps[1][0 .. sizes[0] / 2],
        ps[0][sizes[0] / 2 - sizes[0] / 4 .. sizes[0] - sizes[0] / 4],
    ));
    for (sizes[0] / 2..sizes[0]) |i| try testing.expectEqual(ps[1][i], 0xff);
    try testing.expect(std.mem.eql(
        u8,
        ps[1][sizes[0] .. 2 * sizes[0]],
        ps[0][0..sizes[0]],
    ));
    for (2 * sizes[0]..sizes[1]) |i| try testing.expectEqual(ps[1][i], 0xff);
}
