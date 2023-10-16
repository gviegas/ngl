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
            .transfer_source = false,
            .transfer_dest = false,
        },
    });
    defer prim.deinit(gpa, dev);

    var unif = try ngl.Buffer.init(gpa, dev, .{
        .size = 8192,
        .usage = .{
            .uniform_buffer = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
    });
    unif.deinit(gpa, dev);

    var stg = try ngl.Buffer.init(gpa, dev, .{
        .size = 262144,
        .usage = .{
            .transfer_source = true,
            .transfer_dest = false,
        },
    });
    stg.deinit(gpa, dev);
}

test "Buffer allocation" {
    const dev = &context().device;

    const buf_desc = .{
        .size = 4096,
        .usage = .{
            .storage_buffer = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
    };

    var buf = try ngl.Buffer.init(gpa, dev, buf_desc);

    const mem_reqs = buf.getMemoryRequirements(dev);
    {
        errdefer buf.deinit(gpa, dev);
        try testing.expect(mem_reqs.size >= 4096);
        try testing.expect(mem_reqs.mem_type_bits != 0);
    }

    const mem_idx = for (0..dev.mem_type_n) |i| {
        const idx: u5 = @intCast(i);
        if (mem_reqs.supportsMemoryType(idx)) break idx;
    } else unreachable;

    var mem = blk: {
        errdefer buf.deinit(gpa, dev);
        var mem = try dev.alloc(gpa, .{ .size = mem_reqs.size, .mem_type_index = mem_idx });
        errdefer dev.free(gpa, &mem);
        try buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);

    // Should be able to bind a new buffer to the device allocation
    buf.deinit(gpa, dev);
    var new_buf = try ngl.Buffer.init(gpa, dev, buf_desc);
    defer new_buf.deinit(gpa, dev);
    try testing.expectEqual(new_buf.getMemoryRequirements(dev), mem_reqs);
    try new_buf.bindMemory(dev, &mem, 0);
}

test "BufferView.init/deinit" {
    const dev = &context().device;

    var tb = try ngl.Buffer.init(gpa, dev, .{
        .size = 147456,
        .usage = .{
            .storage_texel_buffer = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
    });
    // It's invalid to create a view with no backing memory
    var tb_mem = blk: {
        errdefer tb.deinit(gpa, dev);
        const mem_reqs = tb.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .mem_type_index = for (0..dev.mem_type_n) |i| {
                const idx: u5 = @intCast(i);
                if (mem_reqs.supportsMemoryType(idx)) break idx;
            } else unreachable,
        });
        errdefer dev.free(gpa, &mem);
        try tb.bindMemory(dev, &mem, 0);
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
