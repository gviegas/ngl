const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;

fn testInitializedDevice(device: ngl.Device, gpu: ngl.Gpu) !void {
    // Queues must be created verbatim.
    try testing.expectEqual(device.queue_n, blk: {
        var n: ngl.Queue.Count = 0;
        for (gpu.queues) |q|
            if (q) |d| {
                if (@typeInfo(ngl.Queue).Struct.fields.len != 4) @compileError("Update me");
                try testing.expectEqual(device.queues[n].capabilities, d.capabilities);
                try testing.expectEqual(device.queues[n].priority, d.priority);
                try testing.expectEqual(
                    device.queues[n].image_transfer_granularity,
                    d.image_transfer_granularity,
                );
                n += 1;
            };
        break :blk n;
    });

    for (device.queues[0..device.queue_n]) |q| {
        // Queues must be capable of something.
        try testing.expect(@as(
            @typeInfo(ngl.Queue.Capabilities).Struct.backing_integer.?,
            @bitCast(q.capabilities),
        ) != 0);

        // Queues supporting graphics and/or compute
        // must also support transfer operations
        // (and must indicate such by setting the
        // `transfer` capability - it's not implicit).
        if (q.capabilities.graphics or q.capabilities.compute)
            try testing.expect(q.capabilities.transfer);

        // Queues supporting graphics and/or compute
        // must not impose any granularity restriction
        // on image transfers.
        if (q.capabilities.graphics or q.capabilities.compute)
            try testing.expectEqual(q.image_transfer_granularity, .one);
    }

    var visible_coherent = false;
    var device_local = false;

    for (device.mem_types[0..device.mem_type_n]) |m| {
        // Visible coherent memory type is required.
        visible_coherent = visible_coherent or
            m.properties.host_visible and m.properties.host_coherent;

        // Device local memory type is required.
        device_local = device_local or m.properties.device_local;

        try testing.expect(m.heap_index < device.mem_heap_n);
    }

    try testing.expect(visible_coherent);
    try testing.expect(device_local);

    device_local = false;

    for (device.mem_heaps[0..device.mem_heap_n]) |h| {
        if (h.size) |x|
            try testing.expect(x > 0);

        // Device local memory heap is required.
        device_local = device_local or h.device_local;
    }
}

// TODO: Test w/ subset of `Gpu`'s queues/features.
test "Device.init/deinit" {
    const gpus = try ngl.getGpus(gpa);
    defer gpa.free(gpus);

    for (gpus) |gpu| {
        // Should fail if no queue descriptions are provided.
        var gpu_no_q = gpu;
        gpu_no_q.queues = [_]?ngl.Queue.Desc{null} ** ngl.Queue.max;
        try testing.expectError(ngl.Error.InvalidArgument, ngl.Device.init(gpa, gpu_no_q));

        var dev = try ngl.Device.init(gpa, gpu);
        defer dev.deinit(gpa);

        try testInitializedDevice(dev, gpu);
    }
}

test "multiple Device instances" {
    const gpus = try ngl.getGpus(gpa);
    defer gpa.free(gpus);

    if (gpus.len < 2) return error.SkipZigTest;

    var devs = try gpa.alloc(ngl.Device, gpus.len);
    defer gpa.free(devs);

    for (devs, gpus, 0..) |*dev, gpu, i|
        dev.* = ngl.Device.init(gpa, gpu) catch |err| {
            for (0..i) |j| devs[j].deinit(gpa);
            return err;
        };
    defer for (devs) |*dev| dev.deinit(gpa);

    for (devs, gpus) |dev, gpu|
        try testInitializedDevice(dev, gpu);
}

test "aliasing Device instances" {
    const gpu = blk: {
        const gpus = try ngl.getGpus(gpa);
        defer gpa.free(gpus);
        break :blk gpus[0];
    };

    var devs = try gpa.alloc(ngl.Device, 2);
    defer gpa.free(devs);

    for (devs, 0..) |*dev, i|
        dev.* = ngl.Device.init(gpa, gpu) catch |err| {
            for (0..i) |j| devs[j].deinit(gpa);
            return err;
        };
    defer for (devs) |*dev| dev.deinit(gpa);

    try testInitializedDevice(devs[0], gpu);

    for (devs[1..devs.len]) |dev| {
        try testing.expectEqual(devs[0].queue_n, dev.queue_n);
        try testing.expectEqual(devs[0].mem_type_n, dev.mem_type_n);
        try testing.expectEqual(devs[0].mem_heap_n, dev.mem_heap_n);
        for (devs[0].queues[0..devs[0].queue_n], dev.queues[0..dev.queue_n]) |x, y| {
            // Note that `impl` can differ.
            if (@typeInfo(ngl.Queue).Struct.fields.len != 4) @compileError("Update me");
            try testing.expectEqual(x.capabilities, y.capabilities);
            try testing.expectEqual(x.priority, y.priority);
            try testing.expectEqual(x.image_transfer_granularity, y.image_transfer_granularity);
        }
        // Don't rely on the order being consistent for memory types/heaps.
        {
            var seem = [_]bool{false} ** ngl.Memory.max_type;
            for (devs[0].mem_types[0..devs[0].mem_type_n]) |x|
                for (dev.mem_types[0..dev.mem_type_n], 0..) |y, i| {
                    if (!seem[i] and std.meta.eql(x, y)) {
                        seem[i] = true;
                        break;
                    }
                } else return error.MemoryTypeMismatch;
        }
        {
            var seem = [_]bool{false} ** ngl.Memory.max_heap;
            for (devs[0].mem_heaps[0..devs[0].mem_heap_n]) |x|
                for (dev.mem_heaps[0..dev.mem_heap_n], 0..) |y, i| {
                    if (!seem[i] and std.meta.eql(x, y)) {
                        seem[i] = true;
                        break;
                    }
                } else return error.MemoryHeapMismatch;
        }
    }
}

test "Device.alloc/free" {
    const gpu = blk: {
        const gpus = try ngl.getGpus(gpa);
        defer gpa.free(gpus);
        break :blk gpus[0];
    };

    var dev = try ngl.Device.init(gpa, gpu);
    defer dev.deinit(gpa);

    const sizes = [_]u64{ 1, 256, 64, 4096, 16384 };

    const mems = try gpa.alloc(ngl.Memory, sizes.len * dev.mem_type_n);
    defer gpa.free(mems);
    var mems_ptr = mems.ptr;

    for (0..dev.mem_type_n) |i| {
        const m: ngl.Memory.TypeIndex = @intCast(i);
        var a = try dev.alloc(gpa, .{ .size = sizes[0], .type_index = m });
        dev.free(gpa, &a);
        var b = try dev.alloc(gpa, .{ .size = sizes[1], .type_index = m });
        defer dev.free(gpa, &b);
        var c = try dev.alloc(gpa, .{ .size = sizes[2], .type_index = m });
        dev.free(gpa, &c);
        for (sizes) |sz| {
            mems_ptr[0] = dev.alloc(gpa, .{ .size = sz, .type_index = m }) catch |err| {
                while (mems_ptr != mems.ptr) : (mems_ptr -= 1) dev.free(gpa, &(mems_ptr - 1)[0]);
                return err;
            };
            mems_ptr += 1;
        }
    }

    for (mems) |*m| dev.free(gpa, m);
}

test "Device.wait" {
    const gpus = try ngl.getGpus(gpa);
    defer gpa.free(gpus);

    var dev = try ngl.Device.init(gpa, gpus[0]);
    defer dev.deinit(gpa);

    try dev.wait();

    var dev_2 = try ngl.Device.init(gpa, gpus[gpus.len - 1]);
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

test "Device.findQueue/findQueueExact" {
    var dev: ngl.Device = undefined;

    const g = ngl.Queue.Capabilities{ .graphics = true };
    const c = ngl.Queue.Capabilities{ .compute = true };
    const t = ngl.Queue.Capabilities{ .transfer = true };
    const gc = ngl.Queue.Capabilities{ .graphics = true, .compute = true };
    const gt = ngl.Queue.Capabilities{ .graphics = true, .transfer = true };
    const ct = ngl.Queue.Capabilities{ .compute = true, .transfer = true };
    const gct = ngl.Queue.Capabilities{ .graphics = true, .compute = true, .transfer = true };

    const Case = struct { ngl.Queue.Capabilities, ?ngl.Queue.Priority, ?ngl.Queue.Index };

    dev.queue_n = 1;
    dev.queues[0] = .{
        .impl = undefined,
        .capabilities = gct,
        .priority = .default,
        .image_transfer_granularity = .one,
    };

    for ([_]Case{
        .{ g, null, 0 },
        .{ g, .default, 0 },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, 0 },
        .{ c, .default, 0 },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 0 },
        .{ t, .default, 0 },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, 0 },
        .{ gc, .default, 0 },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, 0 },
        .{ gt, .default, 0 },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, 0 },
        .{ ct, .default, 0 },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, 0 },
        .{ gct, .default, 0 },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueue(case.@"0", case.@"1"), case.@"2");

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, null },
        .{ t, .default, null },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, null },
        .{ ct, .default, null },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, 0 },
        .{ gct, .default, 0 },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueueExact(case.@"0", case.@"1"), case.@"2");

    dev.queue_n = 1;
    dev.queues[0] = .{
        .impl = undefined,
        .capabilities = ct,
        .priority = .default,
        .image_transfer_granularity = .one,
    };

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, 0 },
        .{ c, .default, 0 },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 0 },
        .{ t, .default, 0 },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, 0 },
        .{ ct, .default, 0 },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueue(case.@"0", case.@"1"), case.@"2");

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, null },
        .{ t, .default, null },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, 0 },
        .{ ct, .default, 0 },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueueExact(case.@"0", case.@"1"), case.@"2");

    dev.queue_n = 1;
    dev.queues[0] = .{
        .impl = undefined,
        .capabilities = t,
        .priority = .default,
        .image_transfer_granularity = .whole_level,
    };

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 0 },
        .{ t, .default, 0 },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, null },
        .{ ct, .default, null },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case| {
        try testing.expectEqual(dev.findQueue(case.@"0", case.@"1"), case.@"2");
        try testing.expectEqual(dev.findQueueExact(case.@"0", case.@"1"), case.@"2");
    }

    // Check that default and high priorities are treated equally
    // when none is specified.

    dev.queue_n = 2;
    dev.queues[0] = .{
        .impl = undefined,
        .capabilities = ct,
        .priority = .default,
        .image_transfer_granularity = .one,
    };
    dev.queues[1] = .{
        .impl = undefined,
        .capabilities = t,
        .priority = .high,
        .image_transfer_granularity = .whole_level,
    };

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, 0 },
        .{ c, .default, 0 },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 0 },
        .{ t, .default, 0 },
        .{ t, .low, null },
        .{ t, .high, 1 },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, 0 },
        .{ ct, .default, 0 },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueue(case.@"0", case.@"1"), case.@"2");

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 1 },
        .{ t, .default, null },
        .{ t, .low, null },
        .{ t, .high, 1 },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, null },
        .{ gt, .default, null },
        .{ gt, .low, null },
        .{ gt, .high, null },
        .{ ct, null, 0 },
        .{ ct, .default, 0 },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueueExact(case.@"0", case.@"1"), case.@"2");

    // Check that default or high priority is selected in lieu of
    // low priority when none is specified.

    dev.queue_n = 2;
    dev.queues[0] = .{
        .impl = undefined,
        .capabilities = gt,
        .priority = .low,
        .image_transfer_granularity = .one,
    };
    dev.queues[1] = .{
        .impl = undefined,
        .capabilities = gt,
        .priority = .default,
        .image_transfer_granularity = .one,
    };

    for ([_]Case{
        .{ g, null, 1 },
        .{ g, .default, 1 },
        .{ g, .low, 0 },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, 1 },
        .{ t, .default, 1 },
        .{ t, .low, 0 },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, 1 },
        .{ gt, .default, 1 },
        .{ gt, .low, 0 },
        .{ gt, .high, null },
        .{ ct, null, null },
        .{ ct, .default, null },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueue(case.@"0", case.@"1"), case.@"2");

    for ([_]Case{
        .{ g, null, null },
        .{ g, .default, null },
        .{ g, .low, null },
        .{ g, .high, null },
        .{ c, null, null },
        .{ c, .default, null },
        .{ c, .low, null },
        .{ c, .high, null },
        .{ t, null, null },
        .{ t, .default, null },
        .{ t, .low, null },
        .{ t, .high, null },
        .{ gc, null, null },
        .{ gc, .default, null },
        .{ gc, .low, null },
        .{ gc, .high, null },
        .{ gt, null, 1 },
        .{ gt, .default, 1 },
        .{ gt, .low, 0 },
        .{ gt, .high, null },
        .{ ct, null, null },
        .{ ct, .default, null },
        .{ ct, .low, null },
        .{ ct, .high, null },
        .{ gct, null, null },
        .{ gct, .default, null },
        .{ gct, .low, null },
        .{ gct, .high, null },
    }) |case|
        try testing.expectEqual(dev.findQueueExact(case.@"0", case.@"1"), case.@"2");
}
