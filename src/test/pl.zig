const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const shd_code = @import("shd_code.zig");

test "Pipeline.initGraphics/deinit" {
    const dev = &context().device;

    const stages = [2]ngl.ShaderStage.Desc{
        .{
            .stage = .vertex,
            .code = &shd_code.color_vert_spv,
            .name = "main",
        },
        .{
            .stage = .fragment,
            .code = &shd_code.color_frag_spv,
            .name = "main",
        },
    };

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.color_desc_bindings,
    });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    const vert_input = ngl.VertexInput{
        .bindings = &shd_code.color_input_bindings,
        .attributes = &shd_code.color_input_attributes,
        .topology = .triangle_list,
        .primitive_restart = false,
    };

    const vport = ngl.Viewport{
        .x = 0,
        .y = 0,
        .width = 470,
        .height = 280,
        .near = 0,
        .far = 1,
        // Should be the same as leaving unset
        .scissor = .{
            .x = 0,
            .y = 0,
            .width = 470,
            .height = 280,
        },
    };

    const raster = ngl.Rasterization{
        .polygon_mode = .fill,
        .cull_mode = .back,
        .clockwise = false,
        .depth_clamp = false,
        .depth_bias = null,
        .samples = .@"1",
        .sample_mask = 0x1,
        .alpha_to_coverage = false,
        .alpha_to_one = false,
    };

    const ds = ngl.DepthStencil{
        .depth_compare = .less_equal,
        .depth_write = true,
        .stencil_front = null,
        .stencil_back = null,
    };

    const col_blend = ngl.ColorBlend{
        .attachments = &.{.{
            // TODO: Need to query whether the format supports blending
            .blend = .{
                .color_source_factor = .source_alpha,
                .color_dest_factor = .one_minus_source_alpha,
                .color_op = .add,
                .alpha_source_factor = .one,
                .alpha_dest_factor = .zero,
                .alpha_op = .add,
            },
            .write = .all,
        }},
        .constants = .unused,
    };

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{
            .{
                .format = .rgba8_unorm,
                .samples = raster.samples,
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .undefined,
                .final_layout = .transfer_source_optimal,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
            .{
                .format = .d16_unorm,
                .samples = raster.samples,
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .depth_stencil_attachment_optimal,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
        },
        .subpasses = &.{.{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = 0,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = .{
                .index = 1,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        }},
        .dependencies = null,
    });
    defer rp.deinit(gpa, dev);

    var pl = try ngl.Pipeline.initGraphics(gpa, dev, .{
        .states = &.{.{
            .stages = &stages,
            .layout = &pl_layt,
            .vertex_input = &vert_input,
            .viewport = &vport,
            .rasterization = &raster,
            .depth_stencil = &ds,
            .color_blend = &col_blend,
            .render_pass = &rp,
            .subpass = 0,
        }},
        .cache = null,
    });
    pl[0].deinit(gpa, dev);
    gpa.free(pl);
}

test "Pipeline.initCompute/deinit" {
    const dev = &context().device;

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.checker_desc_bindings,
    });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var pl = try ngl.Pipeline.initCompute(gpa, dev, .{
        .states = &.{.{
            .stage = .{
                .stage = .compute,
                .code = &shd_code.checker_comp_spv,
                .name = "main",
            },
            .layout = &pl_layt,
        }},
        .cache = null,
    });
    pl[0].deinit(gpa, dev);
    gpa.free(pl);
}
