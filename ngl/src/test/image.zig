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
        .usage = .{ .sampled_image = true, .transfer_dest = true },
        .misc = .{},
        .initial_layout = .unknown,
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
        .usage = .{ .sampled_image = true, .transfer_dest = true },
        .misc = .{},
        .initial_layout = .unknown,
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
        .usage = .{ .sampled_image = true, .transfer_dest = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    @"3d".deinit(gpa, dev);
}

test "Image capabilities" {
    const ctx = context();
    const dev = &ctx.device;
    const core = ngl.Feature.get(gpa, ctx.gpu, .core).?;
    const CoreFeat = @TypeOf(core);

    const expect = struct {
        const U = @typeInfo(ngl.SampleCount.Flags).Struct.backing_integer.?;

        fn dimensions(capabilities: ngl.Image.Capabilities, core_feat: CoreFeat) !void {
            try testing.expect(capabilities.max_width >= core_feat.image.max_2d_extent);
            try testing.expect(capabilities.max_height >= core_feat.image.max_2d_extent);
            try testing.expect(capabilities.max_depth_or_layers >= core_feat.image.max_layers);
        }

        fn sampleCounts(
            capabilities: ngl.Image.Capabilities,
            format_name: []const u8,
            aspect_mask: ngl.Image.Aspect.Flags,
            usage: ngl.Image.Usage,
            core_feat: CoreFeat,
        ) !void {
            const flags: U = @bitCast(capabilities.sample_counts);
            var min = ~@as(U, 0);

            if (usage.color_attachment or usage.depth_stencil_attachment) {
                if (aspect_mask.color) {
                    min &= if (std.mem.indexOf(u8, format_name, "int") == null)
                        @bitCast(core_feat.rendering.color_sample_counts)
                    else
                        @bitCast(core_feat.rendering.integer_sample_counts);
                } else if (aspect_mask.depth) {
                    min &= @bitCast(core_feat.rendering.depth_sample_counts);
                    if (aspect_mask.stencil)
                        min &= @bitCast(core_feat.rendering.stencil_sample_counts);
                } else if (aspect_mask.stencil) {
                    min &= @bitCast(core_feat.rendering.stencil_sample_counts);
                } else unreachable;
            }

            if (usage.sampled_image) {
                if (aspect_mask.color) {
                    min &= if (std.mem.indexOf(u8, format_name, "int") == null)
                        @bitCast(core_feat.image.sampled_color_sample_counts)
                    else
                        @bitCast(core_feat.image.sampled_integer_sample_counts);
                } else if (aspect_mask.depth) {
                    min &= @bitCast(core_feat.image.sampled_depth_sample_counts);
                    if (aspect_mask.stencil)
                        min &= @bitCast(core_feat.image.sampled_stencil_sample_counts);
                } else if (aspect_mask.stencil) {
                    min &= @bitCast(core_feat.image.sampled_stencil_sample_counts);
                } else unreachable;
            }

            if (usage.storage_image)
                min &= @bitCast(core_feat.image.storage_sample_counts);

            try testing.expect(flags & min == min);
        }
    };

    inline for (@typeInfo(ngl.Format).Enum.fields) |f| {
        const feats = @field(ngl.Format.min_features, f.name);
        if (feats.color_attachment) {
            const usage = ngl.Image.Usage{
                .color_attachment = true,
                .sampled_image = feats.sampled_image,
                .storage_image = feats.storage_image,
            };
            const capabs = try ngl.Image.getCapabilities(
                dev,
                .@"2d",
                @field(ngl.Format, f.name),
                .optimal,
                usage,
                .{},
            );
            try expect.dimensions(capabs, core);
            try expect.sampleCounts(capabs, f.name, .{ .color = true }, usage, core);
        } else if (feats.depth_stencil_attachment) {
            // Currently, this is the only format in `Format.min_features`
            // that must support depth/stencil attachments.
            if (@field(ngl.Format, f.name) != .d16_unorm)
                @compileError("Update Image capabilities test");
            const usage = ngl.Image.Usage{
                .depth_stencil_attachment = true,
                .sampled_image = feats.sampled_image,
            };
            const capabs = try ngl.Image.getCapabilities(
                dev,
                .@"2d",
                @field(ngl.Format, f.name),
                .optimal,
                usage,
                .{},
            );
            try expect.dimensions(capabs, core);
            try expect.sampleCounts(capabs, f.name, .{ .depth = true }, usage, core);
        }
    }

    inline for (@typeInfo(ngl.Format).Enum.fields) |f| {
        const feats = @field(ngl.Format.min_features, f.name);
        if (feats.color_attachment or feats.depth_stencil_attachment)
            continue;
        const asp_mask: ngl.Image.Aspect.Flags = switch (@field(ngl.Format, f.name)) {
            .d16_unorm => unreachable,

            .d32_sfloat,
            .x8_d24_unorm,
            => .{ .depth = true },

            .s8_uint => .{ .stencil = true },

            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
            => .{ .depth = true, .stencil = true },

            else => .{ .color = true },
        };
        const usage = .{
            .sampled_image = true,
            .storage_image = feats.storage_image,
            .color_attachment = asp_mask.color,
            .depth_stencil_attachment = asp_mask.depth or asp_mask.stencil,
        };
        if (ngl.Image.getCapabilities(
            dev,
            .@"2d",
            @field(ngl.Format, f.name),
            .optimal,
            usage,
            .{},
        )) |capabs| {
            try expect.dimensions(capabs, core);
            try expect.sampleCounts(capabs, f.name, asp_mask, usage, core);
        } else |_| {}
    }
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
        .usage = .{ .sampled_image = true, .storage_image = true },
        .misc = .{},
        .initial_layout = .unknown,
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
        try image.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);

    // Should be able to bind a new image to the device allocation
    image.deinit(gpa, dev);
    var new_img = try ngl.Image.init(gpa, dev, img_desc);
    defer new_img.deinit(gpa, dev);
    try testing.expectEqual(new_img.getMemoryRequirements(dev), mem_reqs);
    try new_img.bind(dev, &mem, 0);
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
        .usage = .{ .color_attachment = true },
        .misc = .{},
        .initial_layout = undefined,
    });
    // It's invalid to create a view with no backing memory.
    var rt_mem = blk: {
        errdefer rt.deinit(gpa, dev);
        const mem_reqs = rt.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try rt.bind(dev, &mem, 0);
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
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer rt_view.deinit(gpa, dev);

    // Aliasing is allowed.
    var rt_view_2 = try ngl.ImageView.init(gpa, dev, .{
        .image = &rt,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
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
        .usage = .{ .sampled_image = true, .transfer_dest = true },
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
        try spld.bind(dev, &mem, 0);
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
            .level = 0,
            .levels = 1,
            .layer = 2,
            .layers = 4,
        },
    });
    defer spld_view_2d_array.deinit(gpa, dev);

    var spld_view_cube = try ngl.ImageView.init(gpa, dev, .{
        .image = &spld,
        .type = .cube,
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 6,
        },
    });
    spld_view_cube.deinit(gpa, dev);
}
