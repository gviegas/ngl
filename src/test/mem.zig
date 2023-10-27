const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Memory.map/unmap (coherent)" {
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
        @memset(p[0..size], 0xcd);

        mem.unmap(dev);

        // Should be equivalent to `map(dev, 0, size)`
        p = try mem.map(dev, 0, null);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p[0..size], &[_]u8{0xcd} ** size));
    }

    const off = 256;

    {
        var p = try mem.map(dev, off, size - off);
        try testing.expect(std.mem.eql(u8, p[0 .. size - off], &[_]u8{0xcd} ** (size - off)));
        @memset(p[0 .. size - off], 0xf9);

        mem.unmap(dev);

        // Should be equivalent to `map(dev, off, size - off)`
        p = try mem.map(dev, off, null);
        try testing.expect(std.mem.eql(u8, p[0 .. size - off], &[_]u8{0xf9} ** (size - off)));

        mem.unmap(dev);

        p = try mem.map(dev, 0, off);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p[0..off], &[_]u8{0xcd} ** off));
    }

    {
        var p = try mem.map(dev, 0, size);
        try testing.expect(std.mem.eql(u8, p[0..off], &[_]u8{0xcd} ** off));
        try testing.expect(std.mem.eql(u8, p[off..size], &[_]u8{0xf9} ** (size - off)));

        p[0] = 0x6a;
        p[size - 1] = 0xb0;

        mem.unmap(dev);

        p = try mem.map(dev, 0, null);
        defer mem.unmap(dev);
        try testing.expect(std.mem.eql(u8, p[1..off], &[_]u8{0xcd} ** (off - 1)));
        try testing.expect(std.mem.eql(u8, p[off .. size - 1], &[_]u8{0xf9} ** (size - off - 1)));
        try testing.expectEqual(p[0], 0x6a);
        try testing.expectEqual(p[size - 1], 0xb0);
    }

    @memset((try mem.map(dev, 0, size))[0..size], 0xff);
    mem.unmap(dev);

    const size_2 = std.mem.page_size + 513;

    var mem_2 = try dev.alloc(gpa, .{ .size = size_2, .type_index = type_idx });
    defer dev.free(gpa, &mem_2);

    {
        var s = (try mem_2.map(dev, 0, null))[0..size_2];
        @memset(s, 0x2e);

        mem_2.unmap(dev);

        s = (try mem_2.map(dev, 0, size_2))[0..size_2];
        try testing.expectEqual(std.mem.indexOfNone(u8, s, &[_]u8{0x2e}), null);
        defer mem_2.unmap(dev);
    }

    const off_2 = 512;

    {
        var s = (try mem.map(dev, off, null))[0 .. size - off];
        var s_2 = (try mem_2.map(dev, off_2, null))[0 .. size_2 - off_2];
        try testing.expect(std.mem.eql(u8, s, &[_]u8{0xff} ** (size - off)));
        try testing.expectEqual(std.mem.indexOfNone(u8, s_2, &[_]u8{0x2e}), null);

        const n = @min(size_2 - off_2, size - off);
        @memcpy(s_2[0..n], s[0..n]);
        mem_2.unmap(dev);
        mem.unmap(dev);

        var p = try mem_2.map(dev, 0, null);
        defer mem_2.unmap(dev);
        for (0..off_2) |i| try testing.expectEqual(p[i], 0x2e);
        p += off_2;
        for (0..n) |i| try testing.expectEqual(p[i], 0xff);
        if (off_2 + n < size_2) {
            p += n;
            for (0..size_2 - (off_2 + n)) |i| try testing.expectEqual(p[i], 0x2e);
        }
    }

    // Freeing mapped device memory is allowed
    _ = try mem.map(dev, 0, size);
}

test "Memory.flushMapped/invalidateMapped (non-coherent)" {
    // TODO: Need a device that exposes such memory
}
