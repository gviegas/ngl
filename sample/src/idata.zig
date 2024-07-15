const std = @import("std");
const log = std.log.scoped(.sample);
const native_endian = @import("builtin").cpu.arch.endian();

const ngl = @import("ngl");

pub const Data = struct {
    width: u32,
    height: u32,
    format: ngl.Format,
    data: []const u8,

    const Self = @This();

    fn fromPng(data_png: DataPng) Self {
        return .{
            .width = data_png.width,
            .height = data_png.height,
            .format = data_png.format,
            .data = data_png.data,
        };
    }
};

const DataPng = struct {
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

        /// Call this once.
        fn toNative(self: *Ihdr) void {
            switch (native_endian) {
                .little => std.mem.byteSwapAllFields(Ihdr, self),
                .big => {},
            }
        }

        /// Must be called after `toNative`.
        fn validate(self: Ihdr) !void {
            if (self.width == 0 or self.height == 0)
                return error.ZeroExtentPng;

            switch (self.bit_depth) {
                1, 2, 4, 8, 16 => {},
                else => return error.InvalidBitDepthPng,
            }

            if (switch (self.color_type) {
                0 => false,
                2, 4, 6 => self.bit_depth < 8,
                3 => self.bit_depth == 16,
                else => return error.InvalidColorTypePng,
            }) return error.InvalidBitDepthForColorTypePng;

            if (self.compression_method != 0)
                return error.InvalidCompressionMethodPng;

            if (self.filter_method != 0)
                return error.InvalidFilterMethodPng;

            switch (self.interlace_method) {
                0 => {},
                1 => return error.InterlacingNotImplementedPng,
                else => return error.InvalidInterlaceMethodPng,
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
                // Grayscale w/o alpha, palette index.
                0, 3 => 1,
                // Truecolor w/o alpha.
                2 => 3,
                // Grayscale w/ alpha.
                4 => 2,
                // Truecolor w/ alpha.
                6 => 4,
                else => unreachable, // Assume that `ihdr.validate` was called.
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

        /// `reader` must be positioned at the beginning of the data
        /// in the first IDAT chunk.
        /// It returns the preamble of the next non-IDAT chunk.
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

                return .{
                    .length = chk_len,
                    .type = chk_type,
                };
            }
        }

        fn decode(self: *Idat, gpa: std.mem.Allocator, dest: anytype) !struct { ngl.Format, []u8 } {
            try self.decompress(gpa);
            try self.unfilter();
            return self.convert(dest);
        }

        /// Called by `decode`.
        /// Must happen before `unfilter`.
        fn decompress(self: *Idat, gpa: std.mem.Allocator) !void {
            var input = std.io.fixedBufferStream(self.data.items);
            var output = std.ArrayListUnmanaged(u8){};
            errdefer output.deinit(gpa);
            try std.compress.flate.inflate.decompress(.zlib, input.reader(), output.writer(gpa));
            self.data.deinit(gpa);
            self.data = output;
        }

        /// Called by `decode`.
        /// Must happen before `convert`.
        fn unfilter(self: *Idat) !void {
            var ln = self.data.items.ptr;
            switch (ln[0]) {
                // None/Up.
                0, 2 => {},
                // Sub/Paeth.
                1, 4 => {
                    for (self.bytes_per_pixel + 1..self.scanline_size) |i|
                        ln[i] +%= ln[i - self.bytes_per_pixel];
                },
                // Average.
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
                    // None.
                    0 => {},
                    // Sub.
                    1 => {
                        for (self.bytes_per_pixel + 1..self.scanline_size) |i|
                            ln[i] +%= ln[i - self.bytes_per_pixel];
                    },
                    // Up.
                    2 => {
                        for (1..self.scanline_size) |i|
                            ln[i] +%= prev_ln[i];
                    },
                    // Average.
                    3 => {
                        for (1..self.bytes_per_pixel + 1) |i|
                            ln[i] +%= prev_ln[i] / 2;
                        for (self.bytes_per_pixel + 1..self.scanline_size) |i| {
                            const left: u9 = ln[i - self.bytes_per_pixel];
                            const up: u9 = prev_ln[i];
                            ln[i] +%= @truncate((left + up) / 2);
                        }
                    },
                    // Paeth.
                    4 => {
                        for (1..self.bytes_per_pixel + 1) |i|
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

        /// Called by `decode`.
        /// This is the final step.
        // TODO: Currently this only handles gray8/rgb8/rgba8/rgb16.
        fn convert(self: *Idat, dest: anytype) !struct { ngl.Format, []u8 } {
            if (self.channels == 3 and self.bits_per_pixel == 24) {
                const w = self.scanline_size / 3;
                const h = self.image_height;
                var data = try dest.get(w * h * 4);
                for (0..h) |i| {
                    const from = self.data.items[w * 3 * i + i + 1 ..];
                    const to = data[w * 4 * i ..];
                    for (0..w) |j| {
                        @memcpy(to[j * 4 .. j * 4 + 3], from[j * 3 .. j * 3 + 3]);
                        to[j * 4 + 3] = 255;
                    }
                }
                return .{ .rgba8_srgb, data };
            }

            if (self.channels == 4 and self.bits_per_pixel == 32) {
                const w = self.scanline_size / 4;
                const h = self.image_height;
                var data = try dest.get(w * h * 4);
                for (0..h) |i| {
                    const from = self.data.items[w * 4 * i + i + 1 ..];
                    const to = data[w * 4 * i ..];
                    @memcpy(to[0 .. w * 4], from[0 .. w * 4]);
                }
                return .{ .rgba8_srgb, data };
            }

            // TODO: Too slow.
            if (self.channels == 3 and self.bits_per_pixel == 48) {
                const w = self.scanline_size / 6;
                const h = self.image_height;
                var data = try dest.get(w * h * 8);
                for (0..h) |i| {
                    const from = self.data.items[w * 6 * i + i + 1 ..];
                    const to = data[w * 8 * i ..];
                    for (0..w) |j| {
                        for (0..3) |k| {
                            var uint: u16 = undefined;
                            @memcpy(std.mem.asBytes(&uint), from[j * 6 + k * 2 ..][0..2]);
                            uint = std.mem.bigToNative(u16, uint);
                            const highp: f32 = @floatFromInt(uint);
                            const lowp: f16 = @floatCast(highp / 65535);
                            @memcpy(to[j * 8 + k * 2 ..][0..2], std.mem.asBytes(&lowp));
                        }
                        @memcpy(to[j * 8 + 6 ..][0..2], std.mem.asBytes(&@as(f16, 1)));
                    }
                }
                return .{ .rgba16_sfloat, data };
            }

            if (self.channels == 1 and self.bits_per_pixel == 8) {
                const w = self.scanline_size - 1;
                const h = self.image_height;
                var data = try dest.get(w * h);
                for (0..h) |i| {
                    const from = self.data.items[w * i + i + 1 ..];
                    const to = data[w * i ..];
                    @memcpy(to[0..w], from[0..w]);
                }
                return .{ .r8_srgb, data };
            }

            log.err(
                "idata.DataPng: TODO: Conversion from {} bpp, {}-channel data",
                .{ self.bits_per_pixel, self.channels },
            );
            return error.ConversionNotImplementedPng;
        }

        fn deinit(self: *Idat, gpa: std.mem.Allocator) void {
            self.data.deinit(gpa);
            self.* = undefined;
        }
    };

    /// `DataPng.data` will contain whatever `dest.get` returns.
    fn load(gpa: std.mem.Allocator, reader: anytype, dest: anytype) !DataPng {
        var self: DataPng = undefined;

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
        try ihdr.validate();
        self.width = ihdr.width;
        self.height = ihdr.height;

        while (true) {
            const chk_len = try rd.readInt(u32, .big);
            try buf.resize(gpa, 4);
            if (try rd.read(buf.items[0..4]) != 4)
                return error.BadPng;
            const chk_type = ChunkType.make(buf.items[0..4]);

            if (chk_type.eql(ChunkType.idat)) {
                var idat = Idat.init(ihdr);
                defer idat.deinit(gpa);
                _ = try idat.readChunks(gpa, &buf, chk_len, rd);
                const dec = try idat.decode(gpa, dest);
                self.format = dec[0];
                self.data = dec[1];
                // We have all we need.
                return self;
            }

            if (chk_type.eql(ChunkType.plte)) {
                // TODO
                return error.PlteNotImplementedPng;
            }

            if (chk_type.eql(ChunkType.iend)) {
                // This should be unreachable since we end on IDAT.
                return error.BadPng;
            }

            // TODO: Fail if the chunk is required.
            try rd.skipBytes(chk_len + 4, .{});
        }

        return error.BadPng;
    }
};

/// `dest` must implement the following function:
/// ```
/// pub fn get(self: @TypeOf(dest) size: u64) ![]u8
/// ```
/// to provide the destination for the decoded data.
/// The `size` parameter will be computed as follows:
/// ```
/// Data.width * Data.height * <Data.format's texel size>
/// ```
pub fn loadPng(gpa: std.mem.Allocator, path: []const u8, dest: anytype) !Data {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data_png = try DataPng.load(gpa, file.reader(), dest);
    return Data.fromPng(data_png);
}
