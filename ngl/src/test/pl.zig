const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Pipeline.initGraphics/deinit" {
    const dev = &context().device;

    const stages = [2]ngl.ShaderStage.Desc{
        .{
            .stage = .vertex,
            .code = &vert_spv,
            .name = "main",
        },
        .{
            .stage = .fragment,
            .code = &frag_spv,
            .name = "main",
        },
    };

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .uniform_buffer,
        .count = 1,
        .stage_mask = .{ .vertex = true },
        .immutable_samplers = null,
    }} });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    const prim = ngl.Primitive{
        .bindings = &.{.{
            .binding = 0,
            .stride = 12,
            .step_rate = .vertex,
        }},
        .attributes = &.{.{
            .location = 0,
            .binding = 0,
            .format = .rgb32_sfloat,
            .offset = 0,
        }},
        .topology = .triangle_list,
        .restart = false,
    };

    const raster = ngl.Rasterization{
        .polygon_mode = .fill,
        .cull_mode = .back,
        .clockwise = false,
        .depth_clamp = false,
        .depth_bias = false,
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
    };

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{
            .{
                .format = .rgba8_unorm,
                .samples = raster.samples,
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .unknown,
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
                .initial_layout = .unknown,
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
            .primitive = &prim,
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

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .storage_image,
        .count = 1,
        .stage_mask = .{ .compute = true },
        .immutable_samplers = null,
    }} });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var pl = try ngl.Pipeline.initCompute(gpa, dev, .{
        .states = &.{.{
            .stage = .{ .code = &comp_spv, .name = "main" },
            .layout = &pl_layt,
        }},
        .cache = null,
    });
    pl[0].deinit(gpa, dev);
    gpa.free(pl);
}

// #version 460 core
//
// layout(set = 0, binding = 0) uniform UniformBuffer {
//     mat4 m;
// } uniform_buffer;
//
// layout(location = 0) in vec3 position;
//
// void main() {
//     gl_Position = uniform_buffer.m * vec4(position, 1.0);
// }
const vert_spv align(4) = [868]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x48, 0x0,  0x4,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x5,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x23, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x47, 0x0, 0x3,  0x0, 0x11, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x22, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x21, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x1e, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x3,  0x0, 0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x15, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x2b, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x18, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x3,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x12, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x12, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x14, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x17, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x18, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x18, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x20, 0x0, 0x4,  0x0, 0x21, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x10, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x17, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x1f, 0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x91, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x16, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x22, 0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x22, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};

// #version 460 core
//
// layout(location = 0) out vec4 color_0;
//
// void main() {
//     color_0 = vec4(1.0);
// }
const frag_spv align(4) = [288]u8{
    0x3,  0x2, 0x23, 0x7,  0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0,  0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x6,  0x0,  0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x80, 0x3f, 0x2c, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0xa,  0x0, 0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x9,  0x0, 0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(local_size_x = 4, local_size_y = 4) in;
//
// layout(set = 0, binding = 0, rgba8) writeonly uniform image2D storage;
//
// void main() {
//     imageStore(storage, ivec2(gl_GlobalInvocationID.xy), vec4(1.0));
// }
const comp_spv align(4) = [644]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x6,  0x0, 0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x9,  0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x9,  0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x3,  0x0, 0x9,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x3,  0x0, 0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x19, 0x0,  0x9,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0x12, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x13, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x15, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x2c, 0x0, 0x7,  0x0, 0x15, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x16, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x18, 0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x19, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x2c, 0x0,  0x6,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x4f, 0x0, 0x7,  0x0, 0xf,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x7c, 0x0,  0x4,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x14, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x63, 0x0,  0x4,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x14, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};
