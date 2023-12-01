const ngl = @import("../ngl.zig");

pub const cube = struct {
    pub const index_type = ngl.CommandBuffer.Cmd.IndexType.u16;
    pub const topology = ngl.Primitive.Topology.triangle_list;
    pub const clockwise = true;

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
            // -x
            -1, -1, 1,
            -1, -1, -1,
            -1, 1,  -1,
            -1, 1,  1,
            // x
            1,  -1, -1,
            1,  -1, 1,
            1,  1,  1,
            1,  1,  -1,
            // -y
            -1, -1, 1,
            1,  -1, 1,
            1,  -1, -1,
            -1, -1, -1,
            // y
            -1, 1,  -1,
            1,  1,  -1,
            1,  1,  1,
            -1, 1,  1,
            // -z
            -1, -1, -1,
            1,  -1, -1,
            1,  1,  -1,
            -1, 1,  -1,
            // z
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
        tex_coord: [n * 2]f32 = [_]f32{
            0, 1,
            1, 1,
            1, 0,
            0, 0,
        } ** 6,
    } = .{};
};

pub const plane = struct {
    pub const vertex_count = 4;
    pub const topology = ngl.Primitive.Topology.triangle_strip;
    pub const clockwise = true;

    pub const data: struct {
        const n = vertex_count;
        position: [n * 3]f32 = .{
            -1, 0, -1,
            -1, 0, 1,
            1,  0, -1,
            1,  0, 1,
        },
        normal: [n * 3]f32 = [_]f32{ 0, -1, 0 } ** n,
        tex_coord: [n * 2]f32 = .{
            0, 1,
            0, 0,
            1, 1,
            1, 0,
        },
    } = .{};
};
