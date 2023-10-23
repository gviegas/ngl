const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;

test "Device.init/deinit" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    // Should fail if no queue descriptions are provided
    try testing.expectError(ngl.Error.InvalidArgument, ngl.Device.init(gpa, &inst, .{}));

    var dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    var dev = try ngl.Device.init(gpa, &inst, dev_descs[0]);
    defer dev.deinit(gpa);

    // Queues must be created verbatim
    try testing.expectEqual(dev.queue_n, blk: {
        var n: u8 = 0;
        for (dev_descs[0].queues) |q| {
            if (q) |_| n += 1;
        }
        break :blk n;
    });

    // Visible coherent memory is required
    for (dev.mem_types[0..dev.mem_type_n]) |m| {
        if (m.properties.host_visible and m.properties.host_coherent) break;
    } else try testing.expect(false);

    // Device-local memory is required
    for (dev.mem_types[0..dev.mem_type_n]) |m| {
        if (m.properties.device_local) break;
    } else try testing.expect(false);
}

test "multiple Device instances" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    var dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    if (dev_descs.len < 2) return error.SkipZigTest;

    var devs = try gpa.alloc(ngl.Device, dev_descs.len);
    defer gpa.free(devs);

    for (devs, dev_descs, 0..) |*dev, desc, i|
        dev.* = ngl.Device.init(gpa, &inst, desc) catch |err| {
            for (0..i) |j| devs[j].deinit(gpa);
            return err;
        };
    defer for (devs) |*dev| dev.deinit(gpa);

    for (devs, dev_descs) |dev, desc| {
        try testing.expectEqual(dev.queue_n, blk: {
            var n: u8 = 0;
            for (desc.queues) |q| {
                if (q) |_| n += 1;
            }
            break :blk n;
        });

        for (dev.mem_types[0..dev.mem_type_n]) |m| {
            if (m.properties.host_visible and m.properties.host_coherent) break;
        } else try testing.expect(false);

        for (dev.mem_types[0..dev.mem_type_n]) |m| {
            if (m.properties.device_local) break;
        } else try testing.expect(false);
    }
}

test "aliasing Device instances" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    var dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    var devs = try gpa.alloc(ngl.Device, 2);
    defer gpa.free(devs);

    for (devs, 0..) |*dev, i|
        dev.* = ngl.Device.init(gpa, &inst, dev_descs[0]) catch |err| {
            for (0..i) |j| devs[j].deinit(gpa);
            return err;
        };
    defer for (devs) |*dev| dev.deinit(gpa);

    try testing.expectEqual(devs[0].queue_n, blk: {
        var n: u8 = 0;
        for (dev_descs[0].queues) |q| {
            if (q) |_| n += 1;
        }
        break :blk n;
    });

    for (devs[0].mem_types[0..devs[0].mem_type_n]) |m| {
        if (m.properties.host_visible and m.properties.host_coherent) break;
    } else try testing.expect(false);

    for (devs[0].mem_types[0..devs[0].mem_type_n]) |m| {
        if (m.properties.device_local) break;
    } else try testing.expect(false);

    for (devs[1..devs.len]) |dev| {
        try testing.expectEqual(devs[0].queue_n, dev.queue_n);
        try testing.expectEqual(devs[0].mem_type_n, dev.mem_type_n);
        // Don't rely on the order being consistent
        var seem = [_]bool{false} ** ngl.Memory.max_type;
        for (devs[0].mem_types[0..devs[0].mem_type_n]) |x| {
            for (dev.mem_types[0..dev.mem_type_n], 0..) |y, i| {
                if (!seem[i] and std.meta.eql(x, y)) {
                    seem[i] = true;
                    break;
                }
            } else try testing.expect(false);
        }
    }
}

test "Device.alloc/free" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    var dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    var dev = try ngl.Device.init(gpa, &inst, dev_descs[0]);
    defer dev.deinit(gpa);

    const sizes = [_]u64{ 1, 256, 64, 4096, 16384 };

    var mems = try gpa.alloc(ngl.Memory, sizes.len * dev.mem_type_n);
    defer gpa.free(mems);
    var mems_ptr = mems.ptr;

    for (0..dev.mem_type_n) |i| {
        const m: ngl.Memory.TypeIndex = @intCast(i);
        var a = try dev.alloc(gpa, .{ .size = sizes[0], .mem_type_index = m });
        dev.free(gpa, &a);
        var b = try dev.alloc(gpa, .{ .size = sizes[1], .mem_type_index = m });
        defer dev.free(gpa, &b);
        var c = try dev.alloc(gpa, .{ .size = sizes[2], .mem_type_index = m });
        dev.free(gpa, &c);
        for (sizes) |sz| {
            mems_ptr[0] = dev.alloc(gpa, .{ .size = sz, .mem_type_index = m }) catch |err| {
                while (mems_ptr != mems.ptr) : (mems_ptr -= 1) dev.free(gpa, &(mems_ptr - 1)[0]);
                return err;
            };
            mems_ptr += 1;
        }
    }

    for (mems) |*m| dev.free(gpa, m);
}

test "Device.wait" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    var dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    var dev = try ngl.Device.init(gpa, &inst, dev_descs[0]);
    defer dev.deinit(gpa);

    try dev.wait();

    var dev_2 = try ngl.Device.init(gpa, &inst, dev_descs[dev_descs.len - 1]);
    defer dev_2.deinit(gpa);

    try dev_2.wait();
    try dev.wait();

    if (!builtin.single_threaded) {
        const f = struct {
            fn f(device: *ngl.Device) ngl.Error!void {
                std.time.sleep(std.time.ns_per_ms);
                try device.wait();
            }
        }.f;
        var thrd = try std.Thread.spawn(.{ .allocator = gpa }, f, .{&dev});
        var thrd_2 = try std.Thread.spawn(.{ .allocator = gpa }, f, .{&dev_2});
        thrd.join();
        thrd_2.join();
    }
}
