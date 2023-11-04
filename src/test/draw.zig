const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;
const shd_code = @import("shd_code.zig");

test "draw primitive" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.graphics and dev.queues[i].capabilities.transfer) break i;
    } else return error.SkipZigTest;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const clear_col = [4]f32{ 1, 1, 1, 1 };
    const vert_col = [4]f32{ 0, 0, 0, 1 };
    const clear_col_un: u32 = 0xff_ff_ff_ff;
    const vert_col_un = comptime std.mem.bigToNative(u32, 0x00_00_00_ff);

    const w = 64;
    const h = 36;

    const unif_data = [16]f32{
        1, 0,  0, 0,
        0, -1, 0, 0,
        0, 0,  1, 0,
        0, 0,  0, 1,
    };
    const unif_size = blk: {
        const sz = @sizeOf(@TypeOf(unif_data));
        break :blk (sz + 255) & ~@as(u64, 255);
    };

    const vert_data = [3]packed struct {
        x: f32,
        y: f32,
        z: f32,
        r: f32 = vert_col[0],
        g: f32 = vert_col[1],
        b: f32 = vert_col[2],
        a: f32 = vert_col[3],
    }{
        .{ .x = -1, .y = -1, .z = 0.5 },
        .{ .x = 1, .y = -1, .z = 0.5 },
        .{ .x = 0, .y = 1, .z = 0.5 },
    };
    const vert_size = blk: {
        const sz = @sizeOf(@TypeOf(vert_data));
        break :blk (sz + 255) & ~@as(u64, 255);
    };
    if (@sizeOf(@TypeOf(vert_data[0])) != shd_code.color_prim_bindings[0].stride)
        @compileError("Fix vertex input stride");

    const size = @max(w * h * 4, unif_size + vert_size);

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .color_attachment = true, .transfer_source = true },
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
        try image.bindMemory(dev, &mem, 0);
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
        try unif_buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        unif_buf.deinit(gpa, dev);
        dev.free(gpa, &unif_buf_mem);
    }

    var vert_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = unif_size,
        .usage = .{ .vertex_buffer = true, .transfer_dest = true },
    });
    var vert_buf_mem = blk: {
        errdefer vert_buf.deinit(gpa, dev);
        const mem_reqs = vert_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try vert_buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        vert_buf.deinit(gpa, dev);
        dev.free(gpa, &vert_buf_mem);
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
        try stg_buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        stg_buf.deinit(gpa, dev);
        dev.free(gpa, &stg_buf_mem);
    }

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.color_desc_bindings,
    });
    defer set_layt.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{.{
            .format = .rgba8_unorm,
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
            .color_attachments = &.{.{
                .index = 0,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = null,
            }},
            .depth_stencil_attachment = null,
            .preserve_attachments = null,
        }},
        .dependencies = &.{
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{ .vertex_attribute_input = true, .vertex_shader = true },
                .dest_access_mask = .{ .vertex_attribute_read = true, .uniform_read = true },
                .by_region = false,
            },
            .{
                .source_subpass = .{ .index = 0 },
                .dest_subpass = .external,
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                .by_region = false,
            },
        },
    });
    defer rp.deinit(gpa, dev);

    const stages = [2]ngl.ShaderStage.Desc{
        .{
            .stage = .fragment,
            .code = &shd_code.color_frag_spv,
            .name = "main",
        },
        .{
            .stage = .vertex,
            .code = &shd_code.color_vert_spv,
            .name = "main",
        },
    };

    const prim = ngl.Primitive{
        .bindings = &shd_code.color_prim_bindings,
        .attributes = &shd_code.color_prim_attributes,
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
        .cull_mode = .front, // Due to the uniform's transform
        .clockwise = true,
        .samples = .@"1",
    };

    // No depth/stencil state

    const col_blend = ngl.ColorBlend{
        .attachments = &.{.{ .blend = null, .write = .all }},
        .constants = .unused,
    };

    var pl = blk: {
        var s = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{.{
                .stages = &stages,
                .layout = &pl_layt,
                .primitive = &prim,
                .viewport = &vport,
                .rasterization = &raster,
                .depth_stencil = null,
                .color_blend = &col_blend,
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
        .max_sets = 1,
        .pool_size = .{ .uniform_buffer = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_set = blk: {
        var s = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
        defer gpa.free(s);
        break :blk s[0];
    };

    try ngl.DescriptorSet.write(gpa, dev, &.{.{
        .descriptor_set = &desc_set,
        .binding = shd_code.color_desc_bindings[0].binding,
        .element = 0,
        .contents = .{ .uniform_buffer = &.{.{
            .buffer = &unif_buf,
            .offset = 0,
            .range = unif_size,
        }} },
    }});

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
        const len = @sizeOf(@TypeOf(unif_data));
        const source = @as([*]const u8, @ptrCast(&unif_data))[0..len];
        const dest = p[0..len];
        @memcpy(dest, source);
    }
    {
        const len = @sizeOf(@TypeOf(vert_data));
        const source = @as([*]const u8, @ptrCast(&vert_data))[0..len];
        const dest = p[unif_size .. unif_size + len];
        @memcpy(dest, source);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Update uniform and vertex buffers using a staging buffer,
    // then record a render pass instance that draws to a single
    // color attachment, then copy this attachment back to the
    // staging buffer

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf,
            .dest = &unif_buf,
            .regions = &.{.{
                .source_offset = 0,
                .dest_offset = 0,
                .size = unif_size, // Note `unif_size`
            }},
        },
        .{
            .source = &stg_buf,
            .dest = &vert_buf,
            .regions = &.{.{
                .source_offset = unif_size,
                .dest_offset = 0,
                .size = vert_size, // Note `vert_size`
            }},
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
        .clear_values = &.{.{ .color_f32 = clear_col }},
    }, .{ .contents = .inline_only });
    cmd.setPipeline(&pl);
    cmd.setDescriptors(.graphics, &pl_layt, 0, &.{&desc_set});
    cmd.setVertexBuffers(0, &.{&vert_buf}, &.{0}, &.{vert_size}); // Note `vert_size`
    cmd.draw(3, 1, 0, 0);
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
            .image_aspect = .color,
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
        queue_locks[queue_i].lock();
        defer queue_locks[queue_i].unlock();

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    // What the render pass did:
    // 1. Cleared the color attachment to `clear_col` values
    // 2. Drew an inverted triangle in clip coordinates (assuming a
    //    top-left origin) using `vert_col` as vertex color and
    //    with a transform that flips the vertex positions

    const s = @as([*]const u32, @ptrCast(@alignCast(p)))[0 .. w * h];

    const clear_col_n = std.mem.count(u32, s, &.{clear_col_un});
    const vert_col_n = std.mem.count(u32, s, &.{vert_col_un});

    try testing.expect(clear_col_n != 0);
    try testing.expect(vert_col_n != 0);
    try testing.expectEqual(clear_col_n + vert_col_n, w * h);

    // The uniform's transform must have flipped the triangle
    // such that it's no longer inverted
    const tip_beg = std.mem.indexOfScalar(u32, s, vert_col_un).?;
    const tip_len = std.mem.indexOfScalar(u32, s[tip_beg..], clear_col_un).?;
    const base_end = std.mem.lastIndexOfScalar(u32, s, vert_col_un).?;
    const base_len = base_end - std.mem.lastIndexOfScalar(u32, s[0..base_end], clear_col_un).?;
    try testing.expect(tip_len < base_len);
    var prev_len = tip_len;
    for (1 + tip_beg / w..1 + base_end / w) |i| {
        const len = std.mem.count(u32, s[i * w .. i * w + w], &.{vert_col_un});
        try testing.expect(len >= prev_len);
        prev_len = len;
    }

    // TODO: May need to relax this (even more)
    try testing.expectApproxEqAbs(
        @as(f64, @floatFromInt(clear_col_n)) / @as(f64, @floatFromInt(vert_col_n)),
        1,
        if (w & 1 == 0 and h & 1 == 0) 0 else 0.1,
    );

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ @src().fn_name ++ "\n");
        for (0..h) |y| {
            for (0..w) |x| {
                const i = (x + w * y) * 4;
                const data = @as([*]const u32, @ptrCast(@alignCast(p + i)))[0];
                try str.appendSlice(switch (data) {
                    clear_col_un => " 🂿",
                    vert_col_un => " 🃟",
                    else => unreachable,
                });
            }
            try str.append('\n');
        }
        try writer.print("{s}", .{str.items});
    }
}
