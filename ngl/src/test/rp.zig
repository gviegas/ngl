const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "RenderPass.init/deinit" {
    const dev = &context().device;

    const in_attach = ngl.RenderPass.Attachment{
        .format = .rgba8_unorm,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .dont_care,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const ms_attach = ngl.RenderPass.Attachment{
        .format = .rgba8_unorm,
        .samples = .@"4",
        .load_op = .clear,
        .store_op = .dont_care,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = .average,
        .combined = null,
        .may_alias = false,
    };

    const ldr_attach = ngl.RenderPass.Attachment{
        .format = .rgba8_unorm,
        .samples = .@"1",
        .load_op = .dont_care,
        .store_op = .store,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const hdr_attach = ngl.RenderPass.Attachment{
        .format = .rgba16_sfloat,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .dont_care,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const dep_attach = ngl.RenderPass.Attachment{
        .format = .d16_unorm,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .store, //.dont_care,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = null,
        .may_alias = false,
    };

    const ds_attach = ngl.RenderPass.Attachment{
        .format = for ([_]ngl.Format{
            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
        }) |fmt| {
            if (fmt.getFeatures(dev).optimal_tiling.depth_stencil_attachment)
                break fmt;
        } else unreachable,
        .samples = .@"1",
        .load_op = .clear,
        .store_op = .dont_care,
        .initial_layout = .unknown,
        .final_layout = .general,
        .resolve_mode = null,
        .combined = .{
            .stencil_load_op = .clear,
            .stencil_store_op = .dont_care,
        },
        .may_alias = false,
    };

    {
        const in: ngl.RenderPass.Index = 0;
        const ldr: ngl.RenderPass.Index = 1;
        const hdr: ngl.RenderPass.Index = 2;
        const dep: ngl.RenderPass.Index = 3;

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = in,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = .{
                .index = dep,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        const subp_2 = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = &.{.{
                .index = in,
                .layout = .shader_read_only_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .color_attachments = &.{
                .{
                    .index = ldr,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                },
                .{
                    .index = hdr,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                },
            },
            .depth_stencil_attachment = .{
                .index = dep,
                .layout = .depth_stencil_read_only_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        const depend = ngl.RenderPass.Dependency{
            .source_subpass = .{ .index = 0 },
            .dest_subpass = .{ .index = 1 },
            .source_stage_mask = .{ .color_attachment_output = true },
            .source_access_mask = .{ .memory_write = true },
            .dest_stage_mask = .{ .fragment_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = true,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                in_attach,
                ldr_attach,
                hdr_attach,
                dep_attach,
            },
            .subpasses = &.{ subp, subp_2 },
            .dependencies = &.{depend},
        });
        rp.deinit(gpa, dev);
    }

    {
        const ms: ngl.RenderPass.Index = 0;
        const ldr: ngl.RenderPass.Index = 1;

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = ms,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = .{ .index = ldr, .layout = .color_attachment_optimal },
            }},
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{ ms_attach, ldr_attach },
            .subpasses = &.{subp},
            .dependencies = null,
        });
        rp.deinit(gpa, dev);
    }

    {
        const dep: ngl.RenderPass.Index = 0;

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = null,
            .depth_stencil_attachment = .{
                .index = dep,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        const depend = ngl.RenderPass.Dependency{
            .source_subpass = .{ .index = 0 },
            .dest_subpass = .external,
            .source_stage_mask = .{ .early_fragment_tests = true, .late_fragment_tests = true },
            .source_access_mask = .{ .memory_write = true },
            .dest_stage_mask = .{ .fragment_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = true,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{dep_attach},
            .subpasses = &.{subp},
            .dependencies = &.{depend},
        });
        rp.deinit(gpa, dev);
    }

    {
        const in: ngl.RenderPass.Index = 0;
        const ldr: ngl.RenderPass.Index = 1;
        const dep: ngl.RenderPass.Index = 2;

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = in,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = .{
                .index = dep,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        const subp_2 = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = ldr,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = .{
                .index = dep,
                .layout = .depth_stencil_read_only_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = &.{in},
        };

        const subp_3 = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = &.{.{
                .index = in,
                .layout = .shader_read_only_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .color_attachments = &.{.{
                .index = ldr,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        };

        const depend = ngl.RenderPass.Dependency{
            .source_subpass = .{ .index = 0 },
            .dest_subpass = .{ .index = 1 },
            .source_stage_mask = .{ .all_graphics = true },
            .source_access_mask = .{ .memory_read = true, .memory_write = true },
            .dest_stage_mask = .{ .vertex_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = true,
        };

        const depend_2 = ngl.RenderPass.Dependency{
            .source_subpass = .{ .index = 1 },
            .dest_subpass = .{ .index = 2 },
            .source_stage_mask = .{ .color_attachment_output = true },
            .source_access_mask = .{ .memory_read = true, .memory_write = true },
            .dest_stage_mask = .{ .fragment_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = true,
        };

        const depend_3 = ngl.RenderPass.Dependency{
            .source_subpass = .external,
            .dest_subpass = .{ .index = 1 },
            .source_stage_mask = .{ .color_attachment_output = true },
            .source_access_mask = .{ .memory_read = true, .memory_write = true },
            .dest_stage_mask = .{ .vertex_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = true,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                in_attach,
                ldr_attach,
                dep_attach,
            },
            .subpasses = &.{
                subp,
                subp_2,
                subp_3,
            },
            .dependencies = &.{
                depend,
                depend_2,
                depend_3,
            },
        });
        rp.deinit(gpa, dev);
    }

    {
        const ds: ngl.RenderPass.Index = 0;
        const ldr: ngl.RenderPass.Index = 1;

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = ldr,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = .{
                .index = ds,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true, .stencil = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{ ds_attach, ldr_attach },
            .subpasses = &.{subp},
            .dependencies = null,
        });
        rp.deinit(gpa, dev);
    }

    {
        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = null,
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        };

        const depend = ngl.RenderPass.Dependency{
            .source_subpass = .external,
            .dest_subpass = .{ .index = 0 },
            .source_stage_mask = .{ .all_commands = true },
            .source_access_mask = .{ .memory_read = true, .memory_write = true },
            .dest_stage_mask = .{ .fragment_shader = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = false,
        };

        const depend_2 = ngl.RenderPass.Dependency{
            .source_subpass = .{ .index = 0 },
            .dest_subpass = .external,
            .source_stage_mask = .{ .fragment_shader = true },
            .source_access_mask = .{ .memory_read = true, .memory_write = true },
            .dest_stage_mask = .{ .all_commands = true },
            .dest_access_mask = .{ .memory_read = true, .memory_write = true },
            .by_region = false,
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = null,
            .subpasses = &.{subp},
            .dependencies = &.{ depend, depend_2 },
        });
        rp.deinit(gpa, dev);
    }
}

test "RenderPass.getRenderAreaGranularity" {
    const dev = &context().device;

    const desc = ngl.RenderPass.Desc{
        .attachments = &.{.{
            .format = .rgba8_unorm,
            .samples = .@"1",
            .load_op = .clear,
            .store_op = .store,
            .initial_layout = .unknown,
            .final_layout = .general,
            .resolve_mode = null,
            .combined = null,
            .may_alias = false,
        }},
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = 0,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        }},
        .dependencies = null,
    };

    var rp = try ngl.RenderPass.init(gpa, dev, desc);
    defer rp.deinit(gpa, dev);

    const gran = rp.getRenderAreaGranularity(dev);
    try testing.expect(!std.mem.eql(u32, &gran, &.{ 0, 0 }));
    try testing.expect(std.mem.eql(u32, &gran, &rp.getRenderAreaGranularity(dev)));

    var rp_2 = try ngl.RenderPass.init(gpa, dev, desc);
    defer rp_2.deinit(gpa, dev);

    try testing.expect(std.mem.eql(u32, &gran, &rp_2.getRenderAreaGranularity(dev)));
}
