const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Image.init/deinit" {
    const dev = &context().device;

    var @"1d" = try ngl.Image.init(gpa, dev, .{
        .type = .@"1d",
        .format = .r8_unorm,
        .width = 16,
        .height = 1,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    @"1d".deinit(gpa, dev);

    var @"2d" = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_srgb,
        .width = 1024,
        .height = 1024,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    defer @"2d".deinit(gpa, dev);

    var @"3d" = try ngl.Image.init(gpa, dev, .{
        .type = .@"3d",
        .format = .rgba8_unorm,
        .width = 64,
        .height = 64,
        .depth_or_layers = 16,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    @"3d".deinit(gpa, dev);
}

test "Image allocation" {
    const dev = &context().device;

    const img_desc = ngl.Image.Desc{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 512,
        .height = 512,
        .depth_or_layers = 4,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .storage_image = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = .undefined,
    };

    var image = try ngl.Image.init(gpa, dev, img_desc);

    const mem_reqs = image.getMemoryRequirements(dev);
    {
        errdefer image.deinit(gpa, dev);
        try testing.expect(mem_reqs.size >= 4 * 512 * 512 * 4);
        try testing.expect(mem_reqs.type_bits != 0);
    }

    var mem = blk: {
        errdefer image.deinit(gpa, dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try image.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);

    // Should be able to bind a new image to the device allocation
    image.deinit(gpa, dev);
    var new_img = try ngl.Image.init(gpa, dev, img_desc);
    defer new_img.deinit(gpa, dev);
    try testing.expectEqual(new_img.getMemoryRequirements(dev), mem_reqs);
    try new_img.bindMemory(dev, &mem, 0);
}

test "ImageView.init/deinit" {
    const dev = &context().device;

    var rt = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 1280,
        .height = 720,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .color_attachment = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = undefined,
    });
    // It's invalid to create a view with no backing memory
    var rt_mem = blk: {
        errdefer rt.deinit(gpa, dev);
        const mem_reqs = rt.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try rt.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        rt.deinit(gpa, dev);
        dev.free(gpa, &rt_mem);
    }

    var rt_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &rt,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer rt_view.deinit(gpa, dev);

    // Aliasing is allowed
    var rt_view_2 = try ngl.ImageView.init(gpa, dev, .{
        .image = &rt,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = null,
            .base_layer = 0,
            .layers = null,
        },
    });
    defer rt_view_2.deinit(gpa, dev);

    var spld = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 256,
        .height = 256,
        .depth_or_layers = 6,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
        .misc = .{
            .cube_compatible = true,
        },
        .initial_layout = undefined,
    });
    var spld_mem = blk: {
        errdefer spld.deinit(gpa, dev);
        const mem_reqs = spld.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try spld.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        spld.deinit(gpa, dev);
        dev.free(gpa, &spld_mem);
    }

    var spld_view_2d_array = try ngl.ImageView.init(gpa, dev, .{
        .image = &spld,
        .type = .@"2d_array",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 2,
            .layers = null,
        },
    });
    defer spld_view_2d_array.deinit(gpa, dev);

    var spld_view_cube = try ngl.ImageView.init(gpa, dev, .{
        .image = &spld,
        .type = .cube,
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 6,
        },
    });
    spld_view_cube.deinit(gpa, dev);
}
