const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Buffer.init/deinit" {
    const dev = &context().device;

    var prim = try ngl.Buffer.init(gpa, dev, .{
        .size = 65536,
        .usage = .{
            .index_buffer = true,
            .vertex_buffer = true,
            .indirect_buffer = true,
        },
    });
    defer prim.deinit(gpa, dev);

    var unif = try ngl.Buffer.init(gpa, dev, .{
        .size = 8192,
        .usage = .{ .uniform_buffer = true },
    });
    unif.deinit(gpa, dev);

    var stg = try ngl.Buffer.init(gpa, dev, .{
        .size = 262144,
        .usage = .{ .transfer_source = true },
    });
    stg.deinit(gpa, dev);
}

test "Buffer allocation" {
    const dev = &context().device;

    const buf_desc = .{
        .size = 4096,
        .usage = .{ .storage_buffer = true },
    };

    var buf = try ngl.Buffer.init(gpa, dev, buf_desc);

    const mem_reqs = buf.getMemoryRequirements(dev);
    {
        errdefer buf.deinit(gpa, dev);
        try testing.expect(mem_reqs.size >= 4096);
        try testing.expect(mem_reqs.type_bits != 0);
    }

    var mem = blk: {
        errdefer buf.deinit(gpa, dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);

    // Should be able to bind a new buffer to the device allocation
    buf.deinit(gpa, dev);
    var new_buf = try ngl.Buffer.init(gpa, dev, buf_desc);
    defer new_buf.deinit(gpa, dev);
    try testing.expectEqual(new_buf.getMemoryRequirements(dev), mem_reqs);
    try new_buf.bind(dev, &mem, 0);
}

test "BufferView.init/deinit" {
    const dev = &context().device;

    var tb = try ngl.Buffer.init(gpa, dev, .{
        .size = 147456,
        .usage = .{ .storage_texel_buffer = true },
    });
    // It's invalid to create a view with no backing memory
    var tb_mem = blk: {
        errdefer tb.deinit(gpa, dev);
        const mem_reqs = tb.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try tb.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        tb.deinit(gpa, dev);
        dev.free(gpa, &tb_mem);
    }

    var tb_view = try ngl.BufferView.init(gpa, dev, .{
        .buffer = &tb,
        .format = .rgba8_unorm,
        .offset = 0,
        .range = null,
    });
    defer tb_view.deinit(gpa, dev);

    // Aliasing is allowed
    var tb_view_2 = try ngl.BufferView.init(gpa, dev, .{
        .buffer = &tb,
        .format = .r32_uint,
        .offset = 16384,
        .range = 65536,
    });
    tb_view_2.deinit(gpa, dev);
}
