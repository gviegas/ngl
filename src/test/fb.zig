const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "FrameBuffer.init/deinit" {
    const dev = &context().device;

    const col_attach = ngl.RenderPass.Attachment{
        .format = .rgba8_unorm,
        .samples = .@"1",
        .load_op = .load,
        .store_op = .store,
        .initial_layout = .undefined,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const col_attach_2 = ngl.RenderPass.Attachment{
        .format = .rgba8_unorm,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .store,
        .initial_layout = .undefined,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const dep_attach = ngl.RenderPass.Attachment{
        .format = .d16_unorm,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .store,
        .initial_layout = .undefined,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{
            col_attach,
            col_attach_2,
            dep_attach,
        },
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{
                .{
                    .index = 0,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                },
                .{
                    .index = 1,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                },
            },
            .depth_stencil_attachment = .{
                .index = 2,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        }},
        .dependencies = null,
    });
    defer rp.deinit(gpa, dev);

    var rp_2 = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{col_attach_2},
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{
                null,
                .{
                    .index = 0,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                },
            },
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        }},
        .dependencies = null,
    });
    defer rp_2.deinit(gpa, dev);

    var rp_3 = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{dep_attach},
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = null,
            .depth_stencil_attachment = .{
                .index = 0,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        }},
        .dependencies = null,
    });
    defer rp_3.deinit(gpa, dev);

    var rp_4 = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = null,
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = null,
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        }},
        .dependencies = &.{.{
            .source_subpass = .{ .index = 0 },
            .dest_subpass = .external,
            .source_stage_mask = .{ .vertex_shader = true },
            .source_access_mask = .{ .memory_write = true },
            .dest_stage_mask = .{ .vertex_attribute_input = true },
            .dest_access_mask = .{ .memory_read = true },
            .by_region = false,
        }},
    });
    defer rp_4.deinit(gpa, dev);

    const w = 480;
    const h = 270;

    var col_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 2,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .color_attachment = true,
            .input_attachment = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    var col_mem = blk: {
        errdefer col_img.deinit(gpa, dev);
        const reqs = col_img.getMemoryRequirements(dev);
        const idx = for (0..dev.mem_type_n) |i| {
            const idx: ngl.Memory.TypeIndex = @intCast(i);
            if (reqs.supportsMemoryType(idx)) break idx;
        } else unreachable;
        var mem = try dev.alloc(gpa, .{ .size = reqs.size, .mem_type_index = idx });
        errdefer dev.free(gpa, &mem);
        try col_img.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        col_img.deinit(gpa, dev);
        dev.free(gpa, &col_mem);
    }
    var col_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &col_img,
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
    defer col_view.deinit(gpa, dev);
    var col_view_2 = try ngl.ImageView.init(gpa, dev, .{
        .image = &col_img,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 1,
            .layers = 1,
        },
    });
    defer col_view_2.deinit(gpa, dev);

    var dep_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .d16_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .depth_stencil_attachment = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    var dep_mem = blk: {
        errdefer dep_img.deinit(gpa, dev);
        const reqs = dep_img.getMemoryRequirements(dev);
        const idx = for (0..dev.mem_type_n) |i| {
            const idx: ngl.Memory.TypeIndex = @intCast(i);
            if (reqs.supportsMemoryType(idx)) break idx;
        } else unreachable;
        var mem = try dev.alloc(gpa, .{ .size = reqs.size, .mem_type_index = idx });
        errdefer dev.free(gpa, &mem);
        try dep_img.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        dep_img.deinit(gpa, dev);
        dev.free(gpa, &dep_mem);
    }
    var dep_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &dep_img,
        .type = .@"2d",
        .format = .d16_unorm,
        .range = .{
            .aspect_mask = .{ .depth = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer dep_view.deinit(gpa, dev);

    var fb = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp,
        .attachments = &.{
            &col_view,
            &col_view_2,
            &dep_view,
        },
        .width = w,
        .height = h,
        .layers = 1,
    });
    defer fb.deinit(gpa, dev);

    var fb_2 = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp_2,
        .attachments = &.{&col_view_2},
        .width = w,
        .height = h,
        .layers = 1,
    });
    fb_2.deinit(gpa, dev);

    var fb_3 = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp_3,
        .attachments = &.{&dep_view},
        .width = w,
        .height = h,
        .layers = 1,
    });
    defer fb_3.deinit(gpa, dev);

    var fb_4 = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp_4,
        .attachments = null,
        .width = w,
        .height = h,
        .layers = 1,
    });
    fb_4.deinit(gpa, dev);
}
