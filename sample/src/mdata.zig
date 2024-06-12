const std = @import("std");
const log = std.log.scoped(.sample);

const ngl = @import("ngl");

pub const cube = struct {
    pub const index_type = ngl.Cmd.IndexType.u16;
    pub const topology = ngl.Cmd.PrimitiveTopology.triangle_list;
    pub const front_face = ngl.Cmd.FrontFace.clockwise;

    pub const Indices = [36]u16;

    pub const indices: Indices = .{
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

    pub const Positions = [24 * 3]f32;
    pub const Normals = [24 * 3]f32;
    pub const Uvs = [24 * 2]f32;

    pub const Vertices = struct {
        positions: Positions,
        normals: Normals,
        uvs: Uvs,
    };

    pub const vertices = Vertices{
        .positions = .{
            -1, -1, 1,
            -1, -1, -1,
            -1, 1,  -1,
            -1, 1,  1,

            1,  -1, -1,
            1,  -1, 1,
            1,  1,  1,
            1,  1,  -1,

            -1, -1, 1,
            1,  -1, 1,
            1,  -1, -1,
            -1, -1, -1,

            -1, 1,  -1,
            1,  1,  -1,
            1,  1,  1,
            -1, 1,  1,

            -1, -1, -1,
            1,  -1, -1,
            1,  1,  -1,
            -1, 1,  -1,

            1,  -1, 1,
            -1, -1, 1,
            -1, 1,  1,
            1,  1,  1,
        },

        .normals = [_]f32{ -1, 0, 0 } ** 4 ++
            [_]f32{ 1, 0, 0 } ** 4 ++
            [_]f32{ 0, -1, 0 } ** 4 ++
            [_]f32{ 0, 1, 0 } ** 4 ++
            [_]f32{ 0, 0, -1 } ** 4 ++
            [_]f32{ 0, 0, 1 } ** 4,

        .uvs = [_]f32{
            0, 0,
            1, 0,
            1, 1,
            0, 1,
        } ** 6,
    };
};

pub const plane = struct {
    pub const vertex_count = 4;
    pub const topology = ngl.Cmd.PrimitiveTopology.triangle_strip;
    pub const front_face = ngl.Cmd.FrontFace.clockwise;

    pub const Positions = [vertex_count * 3]f32;
    pub const Normals = [vertex_count * 3]f32;
    pub const Uvs = [vertex_count * 2]f32;

    pub const Vertices = struct {
        positions: Positions,
        normals: Normals,
        uvs: Uvs,
    };

    pub const vertices = Vertices{
        .positions = .{
            -1, 0, -1,
            -1, 0, 1,
            1,  0, -1,
            1,  0, 1,
        },

        .normals = [_]f32{ 0, -1, 0 } ** vertex_count,

        .uvs = .{
            0, 1,
            0, 0,
            1, 1,
            1, 0,
        },
    };
};

pub const Data = struct {
    indices: ?std.ArrayListUnmanaged(u32) = .{},
    positions: std.ArrayListUnmanaged([3]f32) = .{},
    normals: std.ArrayListUnmanaged([3]f32) = .{},
    uvs: std.ArrayListUnmanaged([2]f32) = .{},

    const Self = @This();

    fn fromObj(gpa: std.mem.Allocator, data_obj: DataObj, no_indices: bool) !Self {
        var self = Self{};

        if (no_indices) {
            self.indices = null;
            for (data_obj.faces.items) |face| {
                for ([_][3]u32{
                    face[0..3].*,
                    face[3..6].*,
                    face[6..9].*,
                }) |vert| {
                    try self.positions.append(gpa, data_obj.positions.items[vert[0]]);
                    try self.uvs.append(gpa, data_obj.uvs.items[vert[1]]);
                    try self.normals.append(gpa, data_obj.normals.items[vert[2]]);
                }
            }
        } else {
            var vert_map = std.AutoHashMap([3]u32, u32).init(gpa);
            defer vert_map.deinit();

            for (data_obj.faces.items) |face| {
                for ([_][3]u32{
                    face[0..3].*,
                    face[3..6].*,
                    face[6..9].*,
                }) |vert| {
                    const x = try vert_map.getOrPut(vert);
                    if (!x.found_existing) {
                        x.value_ptr.* = @intCast(self.positions.items.len);
                        try self.positions.append(gpa, data_obj.positions.items[vert[0]]);
                        try self.uvs.append(gpa, data_obj.uvs.items[vert[1]]);
                        try self.normals.append(gpa, data_obj.normals.items[vert[2]]);
                    }
                    try self.indices.?.append(gpa, x.value_ptr.*);
                }
            }

            if (self.indices.?.items.len % 3 != 0)
                return error.BadObj;

            //if (self.indices.?.items.len == self.positions.items.len) {
            //    self.indices.?.deinit(gpa);
            //    self.indices = null;
            //}
        }

        return self;
    }

    pub fn indexCount(self: Self) ?u32 {
        const inds = &(self.indices orelse return null);
        return @intCast(inds.items.len);
    }

    pub fn sizeOfIndices(self: Self) ?u64 {
        comptime if (@sizeOf(@TypeOf(self.indices.?.items[0])) != 4)
            unreachable;

        const inds = &(self.indices orelse return null);
        return @intCast(inds.items.len * 4);
    }

    pub fn vertexCount(self: Self) u32 {
        return @intCast(self.positions.items.len);
    }

    pub fn sizeOfVertices(self: Self) u64 {
        return self.positionSize() + self.uvSize() + self.normalSize();
    }

    pub fn sizeOfPositions(self: Self) u64 {
        comptime if (@sizeOf(@TypeOf(self.positions.items[0])) != 12)
            unreachable;

        return self.positions.items.len * 12;
    }

    pub fn sizeOfNormals(self: Self) u64 {
        comptime if (@sizeOf(@TypeOf(self.normals.items[0])) != 12)
            unreachable;

        return self.normals.items.len * 12;
    }

    pub fn sizeOfUvs(self: Self) u64 {
        comptime if (@sizeOf(@TypeOf(self.uvs.items[0])) != 8)
            unreachable;

        return self.uvs.items.len * 8;
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        if (self.indices) |*x|
            x.deinit(gpa);
        self.positions.deinit(gpa);
        self.normals.deinit(gpa);
        self.uvs.deinit(gpa);
    }
};

const DataObj = struct {
    positions: std.ArrayListUnmanaged([3]f32) = .{},
    uvs: std.ArrayListUnmanaged([2]f32) = .{},
    normals: std.ArrayListUnmanaged([3]f32) = .{},
    // Position/UV/Normal * 3.
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

/// Counter clockwise, -y up and z forward.
/// Must have normals and uvs.
/// Will not have indices.
pub fn loadObj(gpa: std.mem.Allocator, path: []const u8) !Data {
    const dir = std.fs.cwd();
    const file = try dir.openFile(path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var fwr = std.io.fixedBufferStream(&buf);
    var cwr = std.io.countingWriter(fwr.writer());
    const wr = cwr.writer();
    var brd = std.io.bufferedReader(file.reader());
    var rd = brd.reader();

    var data_obj = DataObj{};
    defer data_obj.deinit(gpa);

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
            try data_obj.parseV(gpa, &it);
        } else if (std.mem.eql(u8, str, "vt")) {
            try data_obj.parseVt(gpa, &it);
        } else if (std.mem.eql(u8, str, "vn")) {
            try data_obj.parseVn(gpa, &it);
        } else if (std.mem.eql(u8, str, "f")) {
            try data_obj.parseF(gpa, &it);
        } else if (str[0] != '#') {
            log.warn(
                \\mdata.{s}: Ignoring "{s}"
            , .{ @src().fn_name, buf[0..n] });
        }
    }

    return Data.fromObj(gpa, data_obj, true);
}
