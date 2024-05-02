const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const log = @import("test.zig").log;

test "Memory.map/unmap" {
    const dev = &context().device;

    const type_idx = for (0..dev.mem_type_n) |i| {
        const typ = dev.mem_types[i];
        if (typ.properties.host_visible and typ.properties.host_coherent)
            break @as(ngl.Memory.TypeIndex, @intCast(i));
    } else unreachable;

    const size = 1024;

    var mem = try dev.alloc(gpa, .{ .size = size, .type_index = type_idx });
    defer dev.free(gpa, &mem);

    {
        var p = try mem.map(dev, 0, size);
        try testing.expect(p.len == size);
        @memset(p, 0xcd);

        mem.unmap(dev);

        p = try mem.map(dev, 0, size);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p, &[_]u8{0xcd} ** size));
    }

    const off = 256;

    {
        var p = try mem.map(dev, off, size - off);
        try testing.expect(p.len == size - off);
        try testing.expect(std.mem.eql(u8, p, &[_]u8{0xcd} ** (size - off)));
        @memset(p, 0xf9);

        mem.unmap(dev);

        p = try mem.map(dev, 0, off);
        try testing.expect(p.len == off);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p, &[_]u8{0xcd} ** off));
    }

    {
        var p = try mem.map(dev, 0, size);
        try testing.expect(std.mem.eql(u8, p[0..off], &[_]u8{0xcd} ** off));
        try testing.expect(std.mem.eql(u8, p[off..size], &[_]u8{0xf9} ** (size - off)));

        p[0] = 0x6a;
        p[size - 1] = 0xb0;

        mem.unmap(dev);

        p = try mem.map(dev, 0, size);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p[1..off], &[_]u8{0xcd} ** (off - 1)));
        try testing.expect(std.mem.eql(u8, p[off .. size - 1], &[_]u8{0xf9} ** (size - off - 1)));
        try testing.expectEqual(p[0], 0x6a);
        try testing.expectEqual(p[size - 1], 0xb0);
    }

    @memset(try mem.map(dev, 0, size), 0xff);
    mem.unmap(dev);

    const size_2 = std.mem.page_size + 513;

    var mem_2 = try dev.alloc(gpa, .{ .size = size_2, .type_index = type_idx });
    defer dev.free(gpa, &mem_2);

    {
        var s = try mem_2.map(dev, 0, size_2);
        @memset(s, 0x2e);

        mem_2.unmap(dev);

        s = try mem_2.map(dev, 0, size_2);
        try testing.expectEqual(std.mem.indexOfNone(u8, s, &[_]u8{0x2e}), null);
        defer mem_2.unmap(dev);
    }

    const off_2 = 512;

    {
        var s = try mem.map(dev, off, size - off);
        var s_2 = try mem_2.map(dev, off_2, size_2 - off_2);
        try testing.expect(std.mem.eql(u8, s, &[_]u8{0xff} ** (size - off)));
        try testing.expectEqual(std.mem.indexOfNone(u8, s_2, &[_]u8{0x2e}), null);

        const n = @min(size_2 - off_2, size - off);
        @memcpy(s_2[0..n], s[0..n]);
        mem_2.unmap(dev);
        mem.unmap(dev);

        var p = try mem_2.map(dev, 0, size_2);
        defer mem_2.unmap(dev);
        for (0..off_2) |i| try testing.expectEqual(p[i], 0x2e);
        p = p[off_2..];
        for (0..n) |i| try testing.expectEqual(p[i], 0xff);
        if (off_2 + n < size_2) {
            p = p[n..];
            for (0..size_2 - (off_2 + n)) |i| try testing.expectEqual(p[i], 0x2e);
        }
    }

    // Freeing mapped device memory is allowed.
    _ = try mem.map(dev, 0, size);
}

test "Memory.flushMapped/invalidateMapped" {
    const dev = &context().device;

    const size = 1 << 22;
    const type_idx = blk: {
        var type_idx: ngl.Memory.TypeIndex = 0;
        for (dev.mem_types[0..dev.mem_type_n], 0..) |x, i| {
            if (x.properties.host_visible) {
                type_idx = @intCast(i);
                if (!x.properties.host_coherent)
                    break;
            }
        } else log.warn(
            \\In {s}:
            \\  Device doesn't expose host visible, non-coherent memory.
            \\  Chose {} instead.
        ,
            .{ @src().fn_name, dev.mem_types[type_idx].properties },
        );
        break :blk type_idx;
    };

    var mem = try dev.alloc(gpa, .{ .size = size, .type_index = type_idx });
    defer dev.free(gpa, &mem);

    const data = try mem.map(dev, 0, size);
    defer mem.unmap(dev);
    @memset(data, 0xdf);

    // TODO: `Stage.host`, `Access.host_read` and `Access.host_write`.

    try mem.flushMapped(gpa, dev, &.{0}, &.{size});

    try testing.expect(for (data) |x| {
        if (x != 0xdf) break false;
    } else true);

    try mem.invalidateMapped(gpa, dev, &.{0}, &.{size});

    try testing.expect(for (data) |x| {
        if (x != 0xdf) break false;
    } else true);
}

test "Memory.Requirements.findType/findTypeExact" {
    var dev: ngl.Device = undefined;
    dev.mem_type_n = 3;
    dev.mem_types[0] = .{
        .properties = .{ .device_local = true },
        .heap_index = 0,
    };
    dev.mem_types[1] = .{
        .properties = .{ .host_visible = true, .host_coherent = true },
        .heap_index = 0,
    };
    dev.mem_types[2] = .{
        .properties = .{ .host_visible = true },
        .heap_index = 1,
    };

    var mem_reqs: ngl.Memory.Requirements = undefined;
    var mem_props: ngl.Memory.Properties = undefined;

    mem_reqs.type_bits = 0b111;

    mem_props = .{ .device_local = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), 0);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), 0);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), 2);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), 2);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), 2);

    mem_props = .{ .host_coherent = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .host_coherent = true, .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), 1);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), 1);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .device_local = true, .host_coherent = true, .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{};
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), 2);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_reqs.type_bits = 0b101;

    mem_props = .{ .device_local = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 0);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), 0);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), 0);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 2);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), 2);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), 2);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), 2);

    mem_props = .{ .host_coherent = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .host_coherent = true, .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_reqs.type_bits = 0b010;

    mem_props = .{ .device_local = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{ .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), 1);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_reqs.type_bits = 0;

    mem_props = .{ .host_visible = true };
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);

    mem_props = .{};
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findType(dev, mem_props, 1), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, null), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 0), null);
    try testing.expectEqual(mem_reqs.findTypeExact(dev, mem_props, 1), null);
}
