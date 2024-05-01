const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "DescriptorSet.write" {
    const dev = &context().device;

    const shader_mask = ngl.Shader.Type.Flags{
        .vertex = true,
        .fragment = true,
        .compute = true,
    };

    var splr = try ngl.Sampler.init(gpa, dev, .{
        .normalized_coordinates = true,
        .u_address = .repeat,
        .v_address = .repeat,
        .w_address = .repeat,
        .border_color = null,
        .mag = .nearest,
        .min = .nearest,
        .mipmap = .nearest,
        .min_lod = 0,
        .max_lod = null,
        .max_anisotropy = null,
        .compare = null,
    });
    defer splr.deinit(gpa, dev);

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 1024,
        .height = 1024,
        .depth_or_layers = 2,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .sampled_image = true, .transfer_dest = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    var img_mem = blk: {
        errdefer image.deinit(gpa, dev);
        const mem_reqs = image.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try image.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        image.deinit(gpa, dev);
        dev.free(gpa, &img_mem);
    }
    var img_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &image,
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
    defer img_view.deinit(gpa, dev);
    var img_view_2 = try ngl.ImageView.init(gpa, dev, .{
        .image = &image,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 1,
            .layers = 1,
        },
    });
    defer img_view_2.deinit(gpa, dev);

    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = 163840,
        .usage = .{ .storage_texel_buffer = true, .uniform_buffer = true },
    });
    var buf_mem = blk: {
        errdefer buf.deinit(gpa, dev);
        const mem_reqs = buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{}, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        buf.deinit(gpa, dev);
        dev.free(gpa, &buf_mem);
    }
    var buf_view = try ngl.BufferView.init(gpa, dev, .{
        .buffer = &buf,
        .format = .rgba8_unorm,
        .offset = 16384,
        .range = 163840 - 16384,
    });
    defer buf_view.deinit(gpa, dev);

    var layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 2,
            .shader_mask = shader_mask,
            .immutable_samplers = &.{},
        },
        .{
            .binding = 1,
            .type = .storage_texel_buffer,
            .count = 1,
            .shader_mask = shader_mask,
            .immutable_samplers = &.{},
        },
        .{
            .binding = 2,
            .type = .uniform_buffer,
            .count = 2,
            .shader_mask = shader_mask,
            .immutable_samplers = &.{},
        },
    } });
    defer layt.deinit(gpa, dev);

    var layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 1,
            .type = .sampler,
            .count = 1,
            .shader_mask = shader_mask,
            .immutable_samplers = &.{},
        },
        .{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 1,
            .shader_mask = shader_mask,
            .immutable_samplers = &.{&splr},
        },
    } });
    defer layt_2.deinit(gpa, dev);

    var pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 2,
        .pool_size = .{
            .sampler = 1,
            .combined_image_sampler = 2 + 1,
            .storage_texel_buffer = 1,
            .uniform_buffer = 2,
        },
    });
    defer pool.deinit(gpa, dev);

    var sets = try pool.alloc(gpa, dev, .{ .layouts = &.{ &layt, &layt_2 } });
    defer gpa.free(sets);

    // Combined image/sampler (x2).
    const write_0_0 = ngl.DescriptorSet.Write{
        .descriptor_set = &sets[0],
        .binding = 0,
        .element = 0,
        .contents = .{ .combined_image_sampler = &.{
            .{
                .view = &img_view_2,
                .layout = .shader_read_only_optimal,
                .sampler = &splr,
            },
            .{
                .view = &img_view,
                .layout = .shader_read_only_optimal,
                .sampler = &splr,
            },
        } },
    };
    // Storage texel buffer.
    const write_0_1 = ngl.DescriptorSet.Write{
        .descriptor_set = &sets[0],
        .binding = 1,
        .element = 0,
        .contents = .{ .storage_texel_buffer = &.{&buf_view} },
    };
    // Uniform buffer (x2).
    const write_0_2 = ngl.DescriptorSet.Write{
        .descriptor_set = &sets[0],
        .binding = 2,
        .element = 0,
        .contents = .{ .uniform_buffer = &.{
            .{
                .buffer = &buf,
                .offset = 4096,
                .range = 1024,
            },
            .{
                .buffer = &buf,
                .offset = 0,
                .range = 2048,
            },
        } },
    };
    // Combined image/sampler w/ immutable sampler.
    const write_1_0 = ngl.DescriptorSet.Write{
        .descriptor_set = &sets[1],
        .binding = 0,
        .element = 0,
        .contents = .{ .combined_image_sampler = &.{.{
            .view = &img_view,
            .layout = .shader_read_only_optimal,
            .sampler = null,
        }} },
    };
    // Sampler.
    const write_1_1 = ngl.DescriptorSet.Write{
        .descriptor_set = &sets[1],
        .binding = 1,
        .element = 0,
        .contents = .{ .sampler = &.{&splr} },
    };

    try ngl.DescriptorSet.write(gpa, dev, &.{write_0_0});
    try ngl.DescriptorSet.write(gpa, dev, &.{write_0_1});
    try ngl.DescriptorSet.write(gpa, dev, &.{write_0_2});
    try ngl.DescriptorSet.write(gpa, dev, &.{write_1_0});
    try ngl.DescriptorSet.write(gpa, dev, &.{write_1_1});

    try ngl.DescriptorSet.write(gpa, dev, &.{
        write_0_0,
        write_0_1,
        write_0_2,
    });
    try ngl.DescriptorSet.write(gpa, dev, &.{ write_1_0, write_1_1 });

    try ngl.DescriptorSet.write(gpa, dev, &.{ write_0_2, write_1_1 });
    try ngl.DescriptorSet.write(gpa, dev, &.{write_0_1});
    try ngl.DescriptorSet.write(gpa, dev, &.{ write_1_0, write_0_0 });

    try ngl.DescriptorSet.write(gpa, dev, &.{
        write_1_0,
        write_1_1,
        write_0_0,
        write_0_1,
        write_0_2,
    });

    try ngl.DescriptorSet.write(gpa, dev, &.{
        .{
            .descriptor_set = &sets[0],
            .binding = 0,
            .element = 1,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &img_view_2,
                .layout = .shader_read_only_optimal,
                .sampler = &splr,
            }} },
        },
        .{
            .descriptor_set = &sets[0],
            .binding = 2,
            .element = 1,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &buf,
                .offset = 8192,
                .range = 256,
            }} },
        },
    });
}
