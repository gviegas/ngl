const ngl = @import("../ngl.zig");

pub const cube = struct {
    pub const index_type = ngl.CommandBuffer.Cmd.IndexType.u16;
    pub const topology = ngl.Primitive.Topology.triangle_list;
    pub const clockwise = false;

    pub const indices: [36]u16 = .{
        0,  1,  2,
        3,  4,  5,
        6,  7,  8,
        9,  10, 11,
        12, 13, 14,
        15, 16, 17,
        0,  18, 1,
        3,  19, 4,
        6,  20, 7,
        9,  21, 10,
        12, 22, 13,
        15, 23, 16,
    };

    pub const data: struct {
        const n = 24;
        position: [n * 3]f32 = .{
            1,  -1, -1,
            -1, -1, 1,
            -1, -1, -1,
            -1, -1, 1,
            1,  1,  1,
            -1, 1,  1,
            1,  -1, 1,
            1,  1,  -1,
            1,  1,  1,
            -1, 1,  -1,
            1,  1,  1,
            1,  1,  -1,
            -1, -1, -1,
            -1, 1,  1,
            -1, 1,  -1,
            1,  -1, -1,
            -1, 1,  -1,
            1,  1,  -1,
            1,  -1, 1,
            1,  -1, 1,
            1,  -1, -1,
            -1, 1,  1,
            -1, -1, 1,
            -1, -1, -1,
        },
        normal: [n * 3]f32 = .{
            0,  -1, 0,
            0,  -1, 0,
            0,  -1, 0,
            0,  0,  1,
            0,  0,  1,
            0,  0,  1,
            1,  0,  0,
            1,  0,  0,
            1,  0,  0,
            0,  1,  0,
            0,  1,  0,
            0,  1,  0,
            -1, 0,  0,
            -1, 0,  0,
            -1, 0,  0,
            0,  0,  -1,
            0,  0,  -1,
            0,  0,  -1,
            0,  -1, 0,
            0,  0,  1,
            1,  0,  0,
            0,  1,  0,
            -1, 0,  0,
            0,  0,  -1,
        },
        tex_coord: [n * 2]f32 = .{
            0.875, 0.5,
            0.625, 0.75,
            0.625, 0.5,
            0.625, 0.75,
            0.375, 1,
            0.375, 0.75,
            0.625, 0,
            0.375, 0.25,
            0.375, 0,
            0.375, 0.5,
            0.125, 0.75,
            0.125, 0.5,
            0.625, 0.5,
            0.375, 0.75,
            0.375, 0.5,
            0.625, 0.25,
            0.375, 0.5,
            0.375, 0.25,
            0.875, 0.75,
            0.625, 1,
            0.625, 0.25,
            0.375, 0.75,
            0.625, 0.75,
            0.625, 0.5,
        },
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
    } = .{};
};
