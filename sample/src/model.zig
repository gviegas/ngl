const std = @import("std");

const ngl = @import("ngl");

pub const cube = struct {
    pub const index_type = ngl.Cmd.IndexType.u16;
    pub const topology = ngl.Cmd.PrimitiveTopology.triangle_list;
    pub const front_face = ngl.Cmd.FrontFace.clockwise;

    pub const indices: [36]u16 = .{
        0,  1,  2,
        0,  2,  3,
        4,  5,  6,
        4,  6,  7,
        8,  9,  10,
        8,  10, 11,
        12, 13, 14,
        12, 14, 15,
        16, 17, 18,
        16, 18, 19,
        20, 21, 22,
        20, 22, 23,
    };

    pub const data: struct {
        const n = 24;
        position: [n * 3]f32 = .{
            // -x:
            -1, -1, 1,
            -1, -1, -1,
            -1, 1,  -1,
            -1, 1,  1,
            // x:
            1,  -1, -1,
            1,  -1, 1,
            1,  1,  1,
            1,  1,  -1,
            // -y:
            -1, -1, 1,
            1,  -1, 1,
            1,  -1, -1,
            -1, -1, -1,
            // y:
            -1, 1,  -1,
            1,  1,  -1,
            1,  1,  1,
            -1, 1,  1,
            // -z:
            -1, -1, -1,
            1,  -1, -1,
            1,  1,  -1,
            -1, 1,  -1,
            // z:
            1,  -1, 1,
            -1, -1, 1,
            -1, 1,  1,
            1,  1,  1,
        },
        normal: [n * 3]f32 = [_]f32{ -1, 0, 0 } ** 4 ++
            [_]f32{ 1, 0, 0 } ** 4 ++
            [_]f32{ 0, -1, 0 } ** 4 ++
            [_]f32{ 0, 1, 0 } ** 4 ++
            [_]f32{ 0, 0, -1 } ** 4 ++
            [_]f32{ 0, 0, 1 } ** 4,
        uv: [n * 2]f32 = [_]f32{
            0, 0,
            1, 0,
            1, 1,
            0, 1,
        } ** 6,
    } = .{};
};

pub const plane = struct {
    pub const vertex_count = 4;
    pub const topology = ngl.Cmd.PrimitiveTopology.triangle_strip;
    pub const front_face = ngl.Cmd.FrontFace.clockwise;

    pub const data: struct {
        const n = vertex_count;
        position: [n * 3]f32 = .{
            -1, 0, -1,
            -1, 0, 1,
            1,  0, -1,
            1,  0, 1,
        },
        normal: [n * 3]f32 = [_]f32{ 0, -1, 0 } ** n,
        uv: [n * 2]f32 = .{
            0, 1,
            0, 0,
            1, 1,
            1, 0,
        },
    } = .{};
};

/// -y up; z forward; ccw.
/// Must have normals and uvs.
pub fn loadObj(gpa: std.mem.Allocator, file_name: []const u8) !Model {
    const dir = std.fs.cwd();
    const file = try dir.openFile(file_name, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var fwr = std.io.fixedBufferStream(&buf);
    var cwr = std.io.countingWriter(fwr.writer());
    const wr = cwr.writer();
    var brd = std.io.bufferedReader(file.reader());
    var rd = brd.reader();

    var data = DataObj{};
    defer data.deinit(gpa);

    var pos: u64 = 0;
    while (true) {
        rd.streamUntilDelimiter(wr, '\n', buf.len) catch |err| {
            if (err != error.EndOfStream)
                return err;
            break;
        };

        const n = cwr.bytes_written - pos;
        defer {
            pos = cwr.bytes_written;
            fwr.reset();
        }

        var it = std.mem.tokenizeScalar(u8, buf[0..n], ' ');
        const str = it.next() orelse continue;

        if (std.mem.eql(u8, str, "v")) {
            try data.parseV(gpa, &it);
        } else if (std.mem.eql(u8, str, "vt")) {
            try data.parseVt(gpa, &it);
        } else if (std.mem.eql(u8, str, "vn")) {
            try data.parseVn(gpa, &it);
        } else if (std.mem.eql(u8, str, "f")) {
            try data.parseF(gpa, &it);
        }
    }

    return Model.generate(gpa, data, true);
}

const DataObj = struct {
    positions: std.ArrayListUnmanaged([3]f32) = .{},
    uvs: std.ArrayListUnmanaged([2]f32) = .{},
    normals: std.ArrayListUnmanaged([3]f32) = .{},
    // pos/uv/norm.
    faces: std.ArrayListUnmanaged([9]u32) = .{},

    const Self = @This();

    fn parseV(self: *Self, gpa: std.mem.Allocator, it: *std.mem.TokenIterator(u8, .scalar)) !void {
        const x = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVXCoord);
        const y = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVYCoord);
        const z = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVZCoord);
        if (it.next()) |n|
            if (n[0] != '#') {
                const w = try std.fmt.parseFloat(f32, n);
                if (w != 1)
                    return error.ParseVWCoord;
            };
        try self.positions.append(gpa, .{ x, y, z });
    }

    fn parseVt(self: *Self, gpa: std.mem.Allocator, it: *std.mem.TokenIterator(u8, .scalar)) !void {
        const u = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVtUCoord);
        const v = blk: {
            var v: f32 = 0;
            if (it.next()) |n|
                if (n[0] != '#') {
                    v = try std.fmt.parseFloat(f32, n);
                    if (it.next()) |m|
                        if (m[0] != '#') {
                            const w = try std.fmt.parseFloat(f32, m);
                            if (w != 0)
                                return error.ParseVtWCoord;
                        };
                };
            break :blk v;
        };
        try self.uvs.append(gpa, .{ u, v });
    }

    fn parseVn(self: *Self, gpa: std.mem.Allocator, it: *std.mem.TokenIterator(u8, .scalar)) !void {
        const x = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVn);
        const y = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVn);
        const z = try std.fmt.parseFloat(f32, it.next() orelse return error.ParseVn);
        try self.normals.append(gpa, .{ x, y, z });
    }

    fn parseF(self: *Self, gpa: std.mem.Allocator, it: *std.mem.TokenIterator(u8, .scalar)) !void {
        var it_2 = std.mem.tokenizeScalar(u8, it.next() orelse return error.ParseF, '/');
        const pa = (try std.fmt.parseInt(u32, it_2.next() orelse return error.ParseFP, 10));
        const ta = (try std.fmt.parseInt(u32, it_2.next() orelse return error.ParseFPt, 10));
        const na = (try std.fmt.parseInt(u32, it_2.next() orelse return error.ParseFPn, 10));

        var it_3 = std.mem.tokenizeScalar(u8, it.next() orelse return error.ParseF, '/');
        const pb = (try std.fmt.parseInt(u32, it_3.next() orelse return error.ParseFP, 10));
        const tb = (try std.fmt.parseInt(u32, it_3.next() orelse return error.ParseFPt, 10));
        const nb = (try std.fmt.parseInt(u32, it_3.next() orelse return error.ParseFPn, 10));

        var it_4 = std.mem.tokenizeScalar(u8, it.next() orelse return error.ParseF, '/');
        var pc = (try std.fmt.parseInt(u32, it_4.next() orelse return error.ParseFP, 10));
        var tc = (try std.fmt.parseInt(u32, it_4.next() orelse return error.ParseFPt, 10));
        var nc = (try std.fmt.parseInt(u32, it_4.next() orelse return error.ParseFPn, 10));

        try self.faces.append(gpa, .{
            pa - 1, ta - 1, na - 1,
            pb - 1, tb - 1, nb - 1,
            pc - 1, tc - 1, nc - 1,
        });

        while (it.next()) |n| {
            if (n[0] == '#')
                break;

            var it_5 = std.mem.tokenizeScalar(u8, n, '/');
            const pd = (try std.fmt.parseInt(u32, it_5.next() orelse return error.ParseFP, 10));
            const td = (try std.fmt.parseInt(u32, it_5.next() orelse return error.ParseFPt, 10));
            const nd = (try std.fmt.parseInt(u32, it_5.next() orelse return error.ParseFPn, 10));

            try self.faces.append(gpa, .{
                pa - 1, ta - 1, na - 1,
                pc - 1, tc - 1, nc - 1,
                pd - 1, td - 1, nd - 1,
            });

            pc = pd;
            tc = td;
            nc = nd;
        }
    }

    fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.positions.deinit(gpa);
        self.uvs.deinit(gpa);
        self.normals.deinit(gpa);
        self.faces.deinit(gpa);
    }
};

pub const Model = struct {
    positions: std.ArrayListUnmanaged([3]f32) = .{},
    uvs: std.ArrayListUnmanaged([2]f32) = .{},
    normals: std.ArrayListUnmanaged([3]f32) = .{},
    indices: ?std.ArrayListUnmanaged(u32) = .{},

    const Self = @This();

    fn generate(gpa: std.mem.Allocator, data: DataObj, no_indices: bool) !Self {
        var mdl = Self{};

        if (no_indices) {
            mdl.indices = null;
            for (data.faces.items) |face| {
                const a = face[0..3].*;
                const b = face[3..6].*;
                const c = face[6..9].*;
                inline for (.{ a, b, c }) |vert| {
                    try mdl.positions.append(gpa, data.positions.items[vert[0]]);
                    try mdl.uvs.append(gpa, data.uvs.items[vert[1]]);
                    try mdl.normals.append(gpa, data.normals.items[vert[2]]);
                }
            }
        } else {
            var vert_map = std.AutoHashMap([3]u32, u32).init(gpa);
            defer vert_map.deinit();

            for (data.faces.items) |face| {
                const a = face[0..3].*;
                const b = face[3..6].*;
                const c = face[6..9].*;
                inline for (.{ a, b, c }) |vert| {
                    const x = try vert_map.getOrPut(vert);
                    if (!x.found_existing) {
                        x.value_ptr.* = @intCast(mdl.positions.items.len);
                        try mdl.positions.append(gpa, data.positions.items[vert[0]]);
                        try mdl.uvs.append(gpa, data.uvs.items[vert[1]]);
                        try mdl.normals.append(gpa, data.normals.items[vert[2]]);
                    }
                    try mdl.indices.?.append(gpa, x.value_ptr.*);
                }
            }

            if (mdl.indices.?.items.len % 3 != 0)
                return error.Generate;

            //if (mdl.indices.?.items.len == mdl.positions.items.len) {
            //    mdl.indices.?.deinit(gpa);
            //    mdl.indices = null;
            //}
        }

        return mdl;
    }

    pub fn vertexCount(self: Self) u32 {
        return @intCast(self.positions.items.len);
    }

    pub fn vertexSize(self: Self) u64 {
        return self.positionSize() + self.uvSize() + self.normalSize();
    }

    pub fn positionSize(self: Self) u64 {
        if (@sizeOf(@TypeOf(self.positions.items[0])) != 12) @compileError("???");
        return self.positions.items.len * 12;
    }

    pub fn uvSize(self: Self) u64 {
        if (@sizeOf(@TypeOf(self.uvs.items[0])) != 8) @compileError("???");
        return self.uvs.items.len * 8;
    }

    pub fn normalSize(self: Self) u64 {
        if (@sizeOf(@TypeOf(self.normals.items[0])) != 12) @compileError("???");
        return self.normals.items.len * 12;
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.positions.deinit(gpa);
        self.uvs.deinit(gpa);
        self.normals.deinit(gpa);
        if (self.indices) |*x|
            x.deinit(gpa);
    }

    pub fn format(
        value: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (value.indices) |x| {
            const idx_type = if (value.positions.items.len < ~@as(u16, 0)) "u16" else "u32";
            try writer.print("pub const indices: [{}]{s} = .{{\n", .{ x.items.len, idx_type });
            for (0..x.items.len / 3) |i|
                try writer.print("    {}, {}, {},\n", .{
                    x.items[i * 3],
                    x.items[i * 3 + 1],
                    x.items[i * 3 + 2],
                });
            try writer.print("}};\n\n", .{});
        } else std.log.warn("(no indices)", .{});

        try writer.print("pub const data = Data{{}};\n\n", .{});

        try writer.print("pub const Data = struct {{\n", .{});
        try writer.print("    const n = {};\n", .{value.positions.items.len});
        try writer.print("    position: [n * 3]f32 = .{{\n", .{});
        for (value.positions.items) |pos|
            try writer.print("        {}, {}, {},\n", .{ pos[0], pos[1], pos[2] });
        try writer.print("    }},\n", .{});
        try writer.print("    normal: [n * 3]f32 = .{{\n", .{});
        for (value.normals.items) |norm|
            try writer.print("        {}, {}, {},\n", .{ norm[0], norm[1], norm[2] });
        try writer.print("    }},\n", .{});
        try writer.print("    uv: [n * 2]f32 = .{{\n", .{});
        for (value.uvs.items) |uv|
            try writer.print("        {}, {},\n", .{ uv[0], uv[1] });
        try writer.print("    }},\n}};\n", .{});
    }
};
