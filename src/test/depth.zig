const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "depth-only rendering" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.graphics) break i;
    } else return error.SkipZigTest;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const w = 48;
    const h = 30;

    const unif_data = [2][16]f32{
        .{
            0.5,  0,    0, 0,
            0,    0.5,  0, 0,
            0,    0,    1, 0,
            0.25, 0.25, 0, 1,
        },
        .{
            0.5,   0,     0,   0,
            0,     0.5,   0,   0,
            0,     0,     1,   0,
            -0.25, -0.25, 0.5, 1,
        },
    };
    const unif_size = blk: {
        const sz = @sizeOf(@TypeOf(unif_data));
        break :blk 2 * ((sz / 2 + 255) & ~@as(u64, 255));
    };
    const unif_off = [2]u64{ 0, unif_size / 2 };

    const idx_data = [6]u16{
        0, 1, 2,
        2, 3, 0,
    };
    const vert_data = [12]f32{
        -1, -1, 0,
        1,  -1, 0,
        1,  1,  0,
        -1, 1,  0,
    };
    const prim_size = blk: {
        const idx_sz = @sizeOf(@TypeOf(idx_data));
        const vert_sz = @sizeOf(@TypeOf(vert_data));
        break :blk (idx_sz + vert_sz + 3) & ~@as(u64, 3);
    };
    const vert_off = 0;
    const idx_off = prim_size - @sizeOf(@TypeOf(idx_data));

    const size = @max(w * h * 2, unif_size + prim_size);

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .d16_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment = true, .transfer_source = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    var img_mem = blk: {
        errdefer image.deinit(gpa, dev);
        const mem_reqs = image.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
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
        .format = .d16_unorm,
        .range = .{
            .aspect_mask = .{ .depth = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer img_view.deinit(gpa, dev);

    var unif_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = unif_size,
        .usage = .{ .uniform_buffer = true, .transfer_dest = true },
    });
    var unif_buf_mem = blk: {
        errdefer unif_buf.deinit(gpa, dev);
        const mem_reqs = unif_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try unif_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        unif_buf.deinit(gpa, dev);
        dev.free(gpa, &unif_buf_mem);
    }

    var prim_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = prim_size,
        .usage = .{
            .index_buffer = true,
            .vertex_buffer = true,
            .transfer_dest = true,
        },
    });
    var prim_buf_mem = blk: {
        errdefer prim_buf.deinit(gpa, dev);
        const mem_reqs = prim_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try prim_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        prim_buf.deinit(gpa, dev);
        dev.free(gpa, &prim_buf_mem);
    }

    var stg_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    var stg_buf_mem = blk: {
        errdefer stg_buf.deinit(gpa, dev);
        const mem_reqs = stg_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try stg_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        stg_buf.deinit(gpa, dev);
        dev.free(gpa, &stg_buf_mem);
    }

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

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{.{
            .format = .d16_unorm,
            .samples = .@"1",
            .load_op = .clear,
            .store_op = .store,
            .initial_layout = .unknown,
            .final_layout = .transfer_source_optimal,
            .resolve_mode = null,
            .combined = null,
            .may_alias = false,
        }},
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
        .dependencies = &.{
            .{
                .source_subpass = .{ .index = 0 },
                .dest_subpass = .external,
                .source_stage_mask = .{ .early_fragment_tests = true, .late_fragment_tests = true },
                .source_access_mask = .{ .depth_stencil_attachment_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                .by_region = false,
            },
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{
                    .index_input = true,
                    .vertex_attribute_input = true,
                    .vertex_shader = true,
                },
                .dest_access_mask = .{
                    .index_read = true,
                    .vertex_attribute_read = true,
                    .uniform_read = true,
                },
                .by_region = false,
            },
        },
    });
    defer rp.deinit(gpa, dev);

    // Vertex stage only
    const stages = [_]ngl.ShaderStage.Desc{.{
        .stage = .vertex,
        .code = &vert_spv,
        .name = "main",
    }};

    const prim = ngl.Primitive{
        .bindings = &.{.{
            .binding = 0,
            .stride = 3 * 4,
            .step_rate = .vertex,
        }},
        .attributes = &.{.{
            .location = 0,
            .binding = 0,
            .format = .rgb32_sfloat,
            .offset = 0,
        }},
        .topology = .triangle_list,
    };

    const vport = ngl.Viewport{
        .x = 0,
        .y = 0,
        .width = w,
        .height = h,
        .near = 0,
        .far = 1,
    };

    const raster = ngl.Rasterization{
        .polygon_mode = .fill,
        .cull_mode = .back,
        .clockwise = true,
        .samples = .@"1",
    };

    const ds = ngl.DepthStencil{
        .depth_compare = .less,
        .depth_write = true,
        .stencil_front = null,
        .stencil_back = null,
    };

    // No color blend state

    var pl = blk: {
        const s = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{.{
                .stages = &stages,
                .layout = &pl_layt,
                .primitive = &prim,
                .viewport = &vport,
                .rasterization = &raster,
                .depth_stencil = &ds,
                .color_blend = null,
                .render_pass = &rp,
                .subpass = 0,
            }},
            .cache = null,
        });
        defer gpa.free(s);
        break :blk s[0];
    };
    defer pl.deinit(gpa, dev);

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 2,
        .pool_size = .{ .uniform_buffer = 2 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_sets = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{ &set_layt, &set_layt } });
    defer gpa.free(desc_sets);

    try ngl.DescriptorSet.write(gpa, dev, &.{
        .{
            .descriptor_set = &desc_sets[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &unif_buf,
                .offset = unif_off[0],
                .range = @sizeOf(@TypeOf(unif_data[0])),
            }} },
        },
        .{
            .descriptor_set = &desc_sets[1],
            .binding = 0,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &unif_buf,
                .offset = unif_off[1],
                .range = @sizeOf(@TypeOf(unif_data[1])),
            }} },
        },
    });

    var fb = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp,
        .attachments = &.{&img_view},
        .width = w,
        .height = h,
        .layers = 1,
    });
    defer fb.deinit(gpa, dev);

    // Keep mapped
    var p = try stg_buf_mem.map(dev, 0, null);
    {
        const len = @sizeOf(@TypeOf(unif_data[0]));
        const source = @as([*]const u8, @ptrCast(&unif_data[0]))[0..len];
        const dest = p[unif_off[0] .. unif_off[0] + len];
        @memcpy(dest, source);
    }
    {
        const len = @sizeOf(@TypeOf(unif_data[1]));
        const source = @as([*]const u8, @ptrCast(&unif_data[1]))[0..len];
        const dest = p[unif_off[1] .. unif_off[1] + len];
        @memcpy(dest, source);
    }
    {
        const len = @sizeOf(@TypeOf(vert_data));
        const source = @as([*]const u8, @ptrCast(&vert_data))[0..len];
        const dest = p[unif_size + vert_off .. unif_size + vert_off + len];
        @memcpy(dest, source);
    }
    {
        const len = @sizeOf(@TypeOf(idx_data));
        const source = @as([*]const u8, @ptrCast(&idx_data))[0..len];
        const dest = p[unif_size + idx_off .. unif_size + idx_off + len];
        @memcpy(dest, source);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Update uniform, index and vertex buffers using a staging buffer,
    // then record a render pass instance containing depth attachment
    // only, then copy this attachment back to the staging buffer

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf,
            .dest = &unif_buf,
            .regions = &.{
                .{
                    .source_offset = unif_off[0],
                    .dest_offset = unif_off[0],
                    .size = @sizeOf(@TypeOf(unif_data[0])),
                },
                .{
                    .source_offset = unif_off[1],
                    .dest_offset = unif_off[1],
                    .size = @sizeOf(@TypeOf(unif_data[1])),
                },
            },
        },
        .{
            .source = &stg_buf,
            .dest = &prim_buf,
            .regions = &.{
                .{
                    .source_offset = unif_size + vert_off,
                    .dest_offset = vert_off,
                    .size = @sizeOf(@TypeOf(vert_data)),
                },
                .{
                    .source_offset = unif_size + idx_off,
                    .dest_offset = idx_off,
                    .size = @sizeOf(@TypeOf(idx_data)),
                },
            },
        },
    });

    // No memory barrier necessary here

    cmd.beginRenderPass(.{
        .render_pass = &rp,
        .frame_buffer = &fb,
        .render_area = .{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
        },
        .clear_values = &.{.{ .depth_stencil = .{ 1, undefined } }},
    }, .{ .contents = .inline_only });
    cmd.setPipeline(&pl);
    cmd.setIndexBuffer(.u16, &prim_buf, idx_off, @sizeOf(@TypeOf(idx_data)));
    cmd.setVertexBuffers(0, &.{&prim_buf}, &.{vert_off}, &.{@sizeOf(@TypeOf(vert_data))});
    cmd.setDescriptors(.graphics, &pl_layt, 0, &.{&desc_sets[0]});
    cmd.drawIndexed(6, 1, 0, 0, 0);
    cmd.setDescriptors(.graphics, &pl_layt, 0, &.{&desc_sets[1]});
    cmd.drawIndexed(6, 1, 0, 0, 0);
    cmd.endRenderPass(.{});

    // No memory barrier necessary here

    cmd.copyImageToBuffer(&.{.{
        .buffer = &stg_buf,
        .image = &image,
        .image_layout = .transfer_source_optimal,
        .image_type = .@"2d",
        .regions = &.{.{
            .buffer_offset = 0,
            .buffer_row_length = w,
            .buffer_image_height = h,
            .image_aspect = .depth,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = w,
            .image_height = h,
            .image_depth_or_layers = 1,
        }},
    }});

    try cmd.end();

    {
        ctx.lockQueue(queue_i);
        defer ctx.unlockQueue(queue_i);

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    // The staging buffer should now contain the result of the depth test
    // that was performed during the render pass, with texels having one
    // of three possible values:
    // - The clear depth value (1.0, i.e. 65535) or
    // - The depth value of the first draw (0) or
    // - The depth value of the second draw (0.5, i.e. 32768)

    const s = @as([*]const u16, @ptrCast(@alignCast(p)))[0 .. w * h];

    const clear_dep: u16 = 65535;
    const vert_dep = [2]u16{
        0,
        32768, // Due to the uniform's transform
    };

    const clear_dep_n = std.mem.count(u16, s, &.{clear_dep});
    const vert_dep_n = [2]usize{
        std.mem.count(u16, s, &.{vert_dep[0]}),
        std.mem.count(u16, s, &.{vert_dep[1]}),
    };

    try testing.expectEqual(clear_dep_n + vert_dep_n[0] + vert_dep_n[1], w * h);
    try testing.expect(vert_dep_n[0] > vert_dep_n[1]);
    try testing.expect(clear_dep > vert_dep_n[0] + vert_dep_n[1]);
    try testing.expect(clear_dep_n / (vert_dep_n[0] + vert_dep_n[1]) < 2);

    // The drawn rectangles were transformed in such a way that they
    // partially intersect one another in the XY plane, and where
    // they intersect, the depth value must be zero (i.e., the depth
    // value from the first draw)
    try testing.expectApproxEqAbs(
        @as(f64, @floatFromInt(vert_dep_n[0])) / @as(f64, @floatFromInt(vert_dep_n[1])),
        4.0 / 3.0,
        0.1,
    );

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ @src().fn_name ++ "\n");
        for (0..h) |y| {
            for (0..w) |x| {
                const i = (x + w * y) * 2;
                const data = @as([*]const u16, @ptrCast(@alignCast(p + i)))[0];
                try str.appendSlice(switch (data) {
                    clear_dep => " ⋅",
                    vert_dep[0] => " ■",
                    vert_dep[1] => " □",
                    else => unreachable,
                });
            }
            try str.append('\n');
        }
        try writer.print("{s}", .{str.items});
    }
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
//     const vec4 pos = uniform_buffer.m * vec4(position, 1.0);
//     gl_Position = pos;
// }
const vert_spv align(4) = [928]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x48, 0x0,  0x4,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x5,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x47, 0x0,  0x3,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x15, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x3,  0x0, 0x20, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x3,  0x0, 0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x18, 0x0,  0x4,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0xa,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0xa,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0x0,  0x0,  0x80, 0x3f, 0x15, 0x0,  0x4,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x21, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x21, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x24, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x13, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x16, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x17, 0x0,  0x0,  0x0,  0x91, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x12, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1c, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x23, 0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x24, 0x0,  0x0,  0x0,
    0x25, 0x0, 0x0,  0x0, 0x22, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x25, 0x0, 0x0,  0x0, 0x23, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};
