const std = @import("std");
const native_endian = @import("builtin").cpu.arch.endian();

const ngl = @import("../ngl.zig");

pub const DataPng = struct {
    width: u32,
    height: u32,
    format: ngl.Format,
    data: []const u8,

    const signature = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

    const ChunkType = packed struct {
        @"0": u8,
        @"1": u8,
        @"2": u8,
        @"3": u8,

        const ihdr = make("IHDR");
        const iend = make("IEND");
        const idat = make("IDAT");
        const plte = make("PLTE");

        fn make(name: *const [4]u8) ChunkType {
            return .{
                .@"0" = name[0],
                .@"1" = name[1],
                .@"2" = name[2],
                .@"3" = name[3],
            };
        }

        fn eql(self: ChunkType, other: ChunkType) bool {
            const U = @typeInfo(ChunkType).Struct.backing_integer.?;
            return @as(U, @bitCast(self)) == @as(U, @bitCast(other));
        }

        pub fn format(
            value: ChunkType,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("{c}{c}{c}{c}", .{ value.@"0", value.@"1", value.@"2", value.@"3" });
        }
    };

    const ChunkCrc = packed struct {
        crc: u32,

        const table = blk: {
            var tab: [256]u32 = undefined;
            @setEvalBranchQuota(2048 + 256);
            for (0..256) |i| {
                var x: u32 = i;
                for (0..8) |_|
                    x = if (x & 1 == 1) 0xedb88320 ^ (x >> 1) else x >> 1;
                tab[i] = x;
            }
            break :blk tab;
        };

        fn calc(data: []const u8) u32 {
            var crc = ~@as(u32, 0);
            for (data) |x|
                crc = table[(crc ^ x) & 0xff] ^ (crc >> 8);
            return crc ^ ~@as(u32, 0);
        }

        fn check(self: ChunkCrc, data: []const u8) bool {
            return calc(data) == self.crc;
        }
    };

    const Ihdr = packed struct {
        width: u32,
        height: u32,
        bit_depth: u8,
        color_type: u8,
        compression_method: u8,
        filter_method: u8,
        interlace_method: u8,

        // Call this once
        fn toNative(self: *Ihdr) void {
            switch (native_endian) {
                .little => std.mem.byteSwapAllFields(Ihdr, self),
                .big => {},
            }
        }
    };

    const Idat = struct {
        data: std.ArrayListUnmanaged(u8) = .{},
        channels: u3,
        bits_per_pixel: u7,
        bytes_per_pixel: u4,
        scanline_size: u32,
        image_height: u32,

        fn init(ihdr: Ihdr) Idat {
            const chans: u3 = switch (ihdr.color_type) {
                0, 3 => 1,
                2 => 3,
                4 => 2,
                6 => 4,
                else => unreachable,
            };
            const bipp = chans * ihdr.bit_depth;
            const bypp = @max(bipp / 8, 1);
            const scanln = if (bipp & 7 != 0)
                1 + @divFloor(ihdr.width * bipp - 1, 8) + 1
            else
                1 + ihdr.width * bypp;

            return .{
                .channels = chans,
                .bits_per_pixel = @intCast(bipp),
                .bytes_per_pixel = @intCast(bypp),
                .scanline_size = scanln,
                .image_height = ihdr.height,
            };
        }

        // `reader` must be positioned at the beginning of the data
        // in the first IDAT chunk
        // It returns the preamble of the next non-IDAT chunk
        fn readChunks(
            self: *Idat,
            gpa: std.mem.Allocator,
            buffer: *std.ArrayListAlignedUnmanaged(u8, 4),
            current_chunk_length: u32,
            reader: anytype,
        ) !struct {
            length: u32,
            type: ChunkType,
        } {
            try self.data.resize(gpa, 0);

            try buffer.resize(gpa, 4 + current_chunk_length);
            try buffer.appendSlice(gpa, "IDAT");
            if (try reader.read(buffer.items[4 .. 4 + current_chunk_length]) !=
                current_chunk_length)
            {
                return error.BadPng;
            }

            if (@as(ChunkCrc, @bitCast(try reader.readInt(u32, .big))).check(buffer.items))
                return error.BadPng;

            try self.data.appendSlice(gpa, buffer.items[4 .. 4 + current_chunk_length]);

            while (true) {
                const chk_len = try reader.readInt(u32, .big);
                if (try reader.read(buffer.items[0..4]) != 4)
                    return error.BadPng;
                const chk_type = ChunkType.make(buffer.items[0..4]);

                if (chk_type.eql(ChunkType.idat)) {
                    try buffer.resize(gpa, 4 + chk_len);
                    try buffer.appendSlice(gpa, "IDAT");
                    if (try reader.read(buffer.items[4 .. 4 + chk_len]) != chk_len)
                        return error.BadPng;

                    if (@as(ChunkCrc, @bitCast(try reader.readInt(u32, .big))).check(buffer.items))
                        return error.BadPng;

                    try self.data.appendSlice(gpa, buffer.items[4 .. 4 + chk_len]);
                    continue;
                }

                return .{ .length = chk_len, .type = chk_type };
            }
        }

        fn decode(self: *Idat, gpa: std.mem.Allocator) !ngl.Format {
            try self.decompress(gpa);
            try self.unfilter();
            return self.convert(gpa);
        }

        // Called by `decode`
        fn decompress(self: *Idat, gpa: std.mem.Allocator) !void {
            var input = std.io.fixedBufferStream(self.data.items);
            var dec = try std.compress.zlib.decompressStream(gpa, input.reader());
            defer dec.deinit();
            // TODO
            const max_size = std.math.maxInt(usize);
            const output = try dec.reader().readAllAlloc(gpa, max_size);
            self.data.deinit(gpa);
            self.data = std.ArrayListUnmanaged(u8).fromOwnedSlice(output);
        }

        // Called by `decode`
        fn unfilter(self: *Idat) !void {
            var ln = self.data.items.ptr;
            switch (ln[0]) {
                // None/Up
                0, 2 => {},
                // Sub/Paeth
                1, 4 => {
                    for (self.bytes_per_pixel + 1..self.scanline_size) |i|
                        ln[i] +%= ln[i - self.bytes_per_pixel];
                },
                // Average
                3 => {
                    for (self.bytes_per_pixel + 1..self.scanline_size) |i|
                        ln[i] +%= ln[i - self.bytes_per_pixel] / 2;
                },
                else => return error.BadPng,
            }
            for (1..self.image_height) |_| {
                const prev_ln = ln;
                ln += self.scanline_size;
                switch (ln[0]) {
                    // None
                    0 => {},
                    // Sub
                    1 => {
                        for (self.bytes_per_pixel + 1..self.scanline_size) |i|
                            ln[i] +%= ln[i - self.bytes_per_pixel];
                    },
                    // Up
                    2 => {
                        for (1..self.scanline_size) |i|
                            ln[i] +%= prev_ln[i];
                    },
                    // Average
                    3 => {
                        for (1..self.bytes_per_pixel) |i|
                            ln[i] +%= prev_ln[i] / 2;
                        for (self.bytes_per_pixel + 1..self.scanline_size) |i| {
                            const left: u9 = ln[i - self.bytes_per_pixel];
                            const up: u9 = prev_ln[i];
                            ln[i] +%= @truncate((left + up) / 2);
                        }
                    },
                    // Paeth
                    4 => {
                        for (1..self.bytes_per_pixel) |i|
                            ln[i] +%= prev_ln[i];
                        for (self.bytes_per_pixel + 1..self.scanline_size) |i| {
                            const a: i10 = ln[i - self.bytes_per_pixel];
                            const b: i10 = prev_ln[i];
                            const c: i10 = prev_ln[i - self.bytes_per_pixel];
                            const p = a + b - c;
                            const pa = @abs(p - a);
                            const pb = @abs(p - b);
                            const pc = @abs(p - c);
                            ln[i] +%= @intCast(if (pa <= pb and pa <= pc)
                                a
                            else if (pb <= pc)
                                b
                            else
                                c);
                        }
                    },
                    else => return error.BadPng,
                }
            }
        }

        // Called by `decode`
        // TODO: Currently this only handles rgb8/rgba8
        fn convert(self: *Idat, gpa: std.mem.Allocator) !ngl.Format {
            if (self.channels == 3 and self.bits_per_pixel == 24) {
                const w = self.scanline_size / 3;
                const h = self.image_height;
                var data = try gpa.alloc(u8, w * h * 4);
                for (0..h) |i| {
                    var source = self.data.items[w * 3 * i + i + 1 ..];
                    var dest = data[w * 4 * i ..];
                    for (0..w) |j| {
                        @memcpy(dest[j * 4 .. j * 4 + 3], source[j * 3 .. j * 3 + 3]);
                        dest[j * 4 + 3] = 255;
                    }
                }
                self.data.deinit(gpa);
                self.data = std.ArrayListUnmanaged(u8).fromOwnedSlice(data);
                return .rgba8_srgb;
            } else if (self.channels == 4 and self.bits_per_pixel == 32) {
                const w = self.scanline_size / 4;
                const h = self.image_height;
                var data = try gpa.alloc(u8, w * h * 4);
                for (0..h) |i| {
                    var source = self.data.items[w * 4 * i + i + 1 ..];
                    var dest = data[w * 4 * i ..];
                    @memcpy(dest[0 .. w * 4], source[0 .. w * 4]);
                }
                self.data.deinit(gpa);
                self.data = std.ArrayListUnmanaged(u8).fromOwnedSlice(data);
                return .rgba8_srgb;
            } else {
                // TODO
                return error.PngConversionNotImplemented;
            }
        }

        fn deinit(self: *Idat, gpa: std.mem.Allocator) void {
            self.data.deinit(gpa);
            self.* = undefined;
        }
    };

    pub fn load(self: *DataPng, gpa: std.mem.Allocator, reader: anytype) !void {
        var brd = std.io.bufferedReader(reader);
        var rd = brd.reader();

        var magic: [signature.len]u8 = undefined;
        if (try rd.read(&magic) != signature.len or !std.mem.eql(u8, &magic, &signature))
            return error.NotPng;

        var buf = try std.ArrayListAlignedUnmanaged(u8, 4).initCapacity(gpa, 4096);
        defer buf.deinit(gpa);

        const ihdr_len = try rd.readInt(u32, .big);
        if (ihdr_len != 13)
            return error.BadPng;
        try buf.resize(gpa, 4 + 13);
        if (try rd.read(buf.items) != 17)
            return error.BadPng;
        if (!ChunkType.make(buf.items[0..4]).eql(ChunkType.ihdr))
            return error.BadPng;

        const ihdr_crc: ChunkCrc = @bitCast(try rd.readInt(u32, .big));
        if (!ihdr_crc.check(buf.items))
            return error.BadPng;

        var ihdr: Ihdr = undefined;
        @memcpy(@as([*]u8, @ptrCast(&ihdr)), buf.items[4..]);
        ihdr.toNative();
        self.width = ihdr.width;
        self.height = ihdr.height;

        while (true) {
            const chk_len = try rd.readInt(u32, .big);
            try buf.resize(gpa, 4);
            if (try rd.read(buf.items[0..4]) != 4) return error.BadPng;
            const chk_type = ChunkType.make(buf.items[0..4]);

            if (chk_type.eql(ChunkType.idat)) {
                var idat = Idat.init(ihdr);
                defer idat.deinit(gpa);
                _ = try idat.readChunks(gpa, &buf, chk_len, rd);
                const format = try idat.decode(gpa);
                self.format = format;
                self.data = try idat.data.toOwnedSlice(gpa);
                // We have all we need
                return;
            }

            if (chk_type.eql(ChunkType.plte)) {
                // TODO
                return error.PngPlteNotImplemented;
            }

            if (chk_type.eql(ChunkType.iend)) {
                // This should be unreachable since we end on IDAT
                return error.BadPng;
            }

            // TODO: Fail if the chunk is required
            try rd.skipBytes(chk_len + 4, .{});
        }
    }

    pub fn deinit(self: *DataPng, gpa: std.mem.Allocator) void {
        if (self.data.len > 0)
            gpa.free(self.data);
        self.* = undefined;
    }
};

pub fn loadPng(gpa: std.mem.Allocator, path: []const u8) !DataPng {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var data = DataPng{
        .width = undefined,
        .height = undefined,
        .format = undefined,
        .data = &.{},
    };
    try data.load(gpa, file.reader());

    return data;
}
