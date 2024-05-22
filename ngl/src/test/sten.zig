const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "stencil test" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;

    var fence = try ngl.Fence.init(gpa, dev, .{ .status = .unsignaled });
    defer fence.deinit(gpa, dev);

    const w = 32;
    const h = 20;

    const copy_sten_off = (w * h * 2 + 255) & ~@as(u64, 255);

    const col_data = [1]u16{
        0xbee, // I'm the color of the provoking vertex.
    } ++ [_]u16{undefined} ** 5;
    const pos_data = [18 + 6]i8{
        // First draw (front-facing; passes depth test).
        127,  -128, 0,   undefined,
        127,  127,  0,   undefined,
        0,    127,  0,   undefined,
        // Second draw (back-facing; fails depth test).
        -128, -128, 127, undefined,
        -128, 127,  127, undefined,
        0,    127,  127, undefined,
    };
    const vert_size = @sizeOf(@TypeOf(col_data)) + @sizeOf(@TypeOf(pos_data));

    const size = @max(copy_sten_off + w * h, vert_size);

    var col_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .r16_uint,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .color_attachment = true, .transfer_source = true },
        .misc = .{},
    });
    var col_mem = blk: {
        errdefer col_img.deinit(gpa, dev);
        const mem_reqs = col_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try col_img.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        col_img.deinit(gpa, dev);
        dev.free(gpa, &col_mem);
    }
    var col_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &col_img,
        .type = .@"2d",
        .format = .r16_uint,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer col_view.deinit(gpa, dev);

    const ds_fmt = for ([_]ngl.Format{
        .d16_unorm_s8_uint,
        .d24_unorm_s8_uint,
        .d32_sfloat_s8_uint,
    }) |fmt| {
        if (fmt.getFeatures(dev).optimal_tiling.depth_stencil_attachment)
            break fmt;
    } else unreachable;
    var ds_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = ds_fmt,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment = true, .transfer_source = true },
        .misc = .{},
    });
    var ds_mem = blk: {
        errdefer ds_img.deinit(gpa, dev);
        const mem_reqs = ds_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try ds_img.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        ds_img.deinit(gpa, dev);
        dev.free(gpa, &ds_mem);
    }
    var ds_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &ds_img,
        .type = .@"2d",
        .format = ds_fmt,
        .range = .{
            .aspect_mask = .{ .depth = true, .stencil = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer ds_view.deinit(gpa, dev);

    var stg_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = size,
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    var stg_mem = blk: {
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
        dev.free(gpa, &stg_mem);
    }

    var vert_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = vert_size,
        .usage = .{ .vertex_buffer = true, .transfer_dest = true },
    });
    var vert_mem = blk: {
        errdefer vert_buf.deinit(gpa, dev);
        const mem_reqs = vert_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try vert_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        vert_buf.deinit(gpa, dev);
        dev.free(gpa, &vert_mem);
    }

    var p = try stg_mem.map(dev, 0, size);
    {
        const off = 0;
        const len = @sizeOf(@TypeOf(col_data));
        const source = @as([*]const u8, @ptrCast(&col_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }
    {
        const off = @sizeOf(@TypeOf(col_data));
        const len = @sizeOf(@TypeOf(pos_data));
        const source = @as([*]const u8, @ptrCast(&pos_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }

    const shaders = try ngl.Shader.init(gpa, dev, &.{
        .{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = &vert_spv,
            .name = "main",
            .set_layouts = &.{},
            .push_constants = &.{},
            .specialization = null,
            .link = true,
        },
        .{
            .type = .fragment,
            .next = .{},
            .code = &frag_spv,
            .name = "main",
            .set_layouts = &.{},
            .push_constants = &.{},
            .specialization = null,
            .link = true,
        },
    });
    defer {
        for (shaders) |*shd|
            (shd.* catch continue).deinit(gpa, dev);
        gpa.free(shaders);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Copy vertex data into a vertex buffer using a staging buffer,
    // then record a render pass instance with color and combined
    // depth/stencil attachments that draws front and back-facing
    // primitives, then copy the color and stencil output into the
    // staging buffer.

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.copyBuffer(&.{.{
        .source = &stg_buf,
        .dest = &vert_buf,
        .regions = &.{.{
            .source_offset = 0,
            .dest_offset = 0,
            .size = vert_size,
        }},
    }});

    cmd.barrier(&.{.{
        .buffer = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{ .vertex_attribute_input = true },
            .dest_access_mask = .{ .vertex_attribute_read = true },
            .queue_transfer = null,
            .buffer = &vert_buf,
            .offset = 0,
            .size = vert_size,
        }},
        .image = &.{
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .color_attachment_output = true },
                .dest_access_mask = .{ .color_attachment_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .color_attachment_optimal,
                .image = &col_img,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .early_fragment_tests = true, .late_fragment_tests = true },
                .dest_access_mask = .{
                    .depth_stencil_attachment_read = true,
                    .depth_stencil_attachment_write = true,
                },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .depth_stencil_attachment_optimal,
                .image = &ds_img,
                .range = .{
                    .aspect_mask = .{ .depth = true, .stencil = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
        },
    }});

    cmd.setShaders(
        &.{
            .vertex,
            .fragment,
        },
        &.{
            &(try shaders[0]),
            &(try shaders[1]),
        },
    );

    cmd.setVertexInput(
        &.{
            .{
                .binding = 0,
                .stride = (3 + (1)) * 1,
                .step_rate = .vertex,
            },
            .{
                .binding = 1,
                .stride = (1 + (1)) * 2,
                .step_rate = .vertex,
            },
        },
        &.{
            .{
                .location = 0,
                .binding = 1,
                .format = .r16_uint,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 0,
                .format = .rgb8_snorm,
                .offset = 0,
            },
        },
    );
    cmd.setPrimitiveTopology(.triangle_list);

    cmd.setViewports(&.{.{
        .x = 0,
        .y = 0,
        .width = w,
        .height = h,
        .znear = 0,
        .zfar = 1,
    }});
    cmd.setScissorRects(&.{.{
        .x = 0,
        .y = 0,
        .width = w,
        .height = h,
    }});

    cmd.setRasterizationEnable(true);
    cmd.setPolygonMode(.fill);
    // Don't cull anything since we want to check
    // the stencil attachment updates.
    cmd.setCullMode(.none);
    cmd.setFrontFace(.clockwise);
    cmd.setSampleCount(.@"1");
    cmd.setSampleMask(0b1);
    cmd.setDepthBiasEnable(false);
    cmd.setColorBlendEnable(0, &.{false});
    cmd.setColorWrite(0, &.{.all});

    cmd.setDepthTestEnable(true);
    cmd.setDepthCompareOp(.less);
    cmd.setDepthWriteEnable(true);
    cmd.setStencilTestEnable(true);

    // The front-facing primitive must pass the
    // stencil and depth tests.
    cmd.setStencilOp(.front, .zero, .increment_clamp, .zero, .greater);
    cmd.setStencilReadMask(.front, 0x0f);
    cmd.setStencilWriteMask(.front, 0x0f);

    // The back-facing primitive must pass the
    // stencil test and fail the depth test.
    cmd.setStencilOp(.back, .zero, .zero, .decrement_clamp, .equal);
    cmd.setStencilReadMask(.back, 0xf0);
    cmd.setStencilWriteMask(.back, 0xf0);

    cmd.setStencilReference(.front_and_back, 0x8f);

    // Binding #1 is the same for both draws.
    cmd.setVertexBuffers(1, &.{&vert_buf}, &.{0}, &.{@sizeOf(@TypeOf(col_data))});

    cmd.beginRendering(.{
        .colors = &.{.{
            .view = &col_view,
            .layout = .color_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .color_u32 = .{ 2, 0, 0, 0 } },
            .resolve = null,
        }},
        .depth = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 0.5, undefined } },
            .resolve = null,
        },
        .stencil = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ undefined, 0x80 } },
            .resolve = null,
        },
        .render_area = .{ .width = w, .height = h },
        .layers = 1,
        .contents = .@"inline",
    });

    for ([_]u64{
        @sizeOf(@TypeOf(col_data)),
        @sizeOf(@TypeOf(col_data)) + @sizeOf(@TypeOf(pos_data)) / 2,
    }) |vb_off| {
        cmd.setVertexBuffers(0, &.{&vert_buf}, &.{vb_off}, &.{@sizeOf(@TypeOf(pos_data)) / 2});
        cmd.draw(3, 1, 0, 0);
    }

    cmd.endRendering();

    cmd.barrier(&.{.{
        .image = &.{
            .{
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                .queue_transfer = null,
                .old_layout = .color_attachment_optimal,
                .new_layout = .transfer_source_optimal,
                .image = &col_img,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
            .{
                .source_stage_mask = .{ .early_fragment_tests = true, .late_fragment_tests = true },
                .source_access_mask = .{ .depth_stencil_attachment_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                .queue_transfer = null,
                .old_layout = .depth_stencil_attachment_optimal,
                .new_layout = .transfer_source_optimal,
                .image = &ds_img,
                .range = .{
                    .aspect_mask = .{ .depth = true, .stencil = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
        },
    }});

    cmd.copyImageToBuffer(&.{
        .{
            .buffer = &stg_buf,
            .image = &col_img,
            .image_layout = .transfer_source_optimal,
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
        },
        .{
            .buffer = &stg_buf,
            .image = &ds_img,
            .image_layout = .transfer_source_optimal,
            .regions = &.{.{
                .buffer_offset = copy_sten_off,
                .buffer_row_length = w,
                .buffer_image_height = h,
                .image_aspect = .stencil,
                .image_level = 0,
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 0,
                .image_width = w,
                .image_height = h,
                .image_depth_or_layers = 1,
            }},
        },
    });

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

    // The front-facing primitive must have passed the stencil test
    // and the depth test, so both the color and stencil attachments
    // must have been written.
    //
    // The back-facing primitive must have passed the stencil test
    // and failed the depth test, so only the stencil attachment
    // must have been written.

    if ((w * h) & 3 != 0) @compileError("Use a dimension multiple of four to ease testing");
    if (w / h >= 2 or h / w >= 2) @compileError("Use a sensible aspect ratio to ease testing");

    const col_out = @as([*]const u16, @ptrCast(@alignCast(p)))[0 .. w * h];

    const clear_col = 2;
    const vert_col = col_data[0];
    const clear_col_n = std.mem.count(u16, col_out, &.{clear_col});
    const vert_col_n = std.mem.count(u16, col_out, &.{vert_col});

    try testing.expectEqual(clear_col_n + vert_col_n, w * h);
    try testing.expectEqual(clear_col_n, 3 * vert_col_n);

    const sten_out = p[copy_sten_off .. copy_sten_off + w * h];

    const stenValue = struct {
        fn f(param: struct {
            stencil_op: ngl.Cmd.StencilOp,
            write_mask: u8,
            attachment: u8,
        }) u8 {
            const gen = switch (param.stencil_op) {
                .increment_clamp => param.attachment +| 1,
                .decrement_clamp => param.attachment -| 1,
                else => unreachable,
            };
            return (param.attachment & ~param.write_mask) | (gen & param.write_mask);
        }
    }.f;
    const clear_sten = 0x80;
    const sten_front = comptime stenValue(.{
        .stencil_op = .increment_clamp,
        .write_mask = 0xf,
        .attachment = 0x80,
    });
    const sten_back = comptime stenValue(.{
        .stencil_op = .decrement_clamp,
        .write_mask = 0xf0,
        .attachment = 0x80,
    });
    const clear_sten_n = std.mem.count(u8, sten_out, &.{clear_sten});
    const sten_front_n = std.mem.count(u8, sten_out, &.{sten_front});
    const sten_back_n = std.mem.count(u8, sten_out, &.{sten_back});

    try testing.expectEqual(clear_sten_n + sten_front_n + sten_back_n, w * h);
    try testing.expectEqual(clear_sten_n, sten_front_n + sten_back_n);
    try testing.expectEqual(sten_front_n, sten_back_n);

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ @src().fn_name ++ "\n");
        try str.appendSlice("color:\n");
        for (0..h) |y| {
            for (0..w) |x| {
                const i = (x + w * y) * 2;
                const data = @as(*const u16, @ptrCast(@alignCast(p[i..]))).*;
                try str.appendSlice(switch (data) {
                    clear_col => "⚫",
                    vert_col => "🐝",
                    else => unreachable,
                });
            }
            try str.append('\n');
        }
        try str.appendSlice("stencil:\n");
        for (0..h) |y| {
            for (0..w) |x| {
                const i = copy_sten_off + (x + w * y) * 1;
                const data = p[i];
                try str.appendSlice(switch (data) {
                    clear_sten => "⚫",
                    sten_front => "🟡",
                    sten_back => "⚪",
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
// layout(location = 0) in uint color;
// layout(location = 1) in vec3 position;
//
// layout(location = 0) out Vertex {
//     uint color;
// } vertex;
//
// void main() {
//     vertex.color = color;
//     gl_Position = vec4(position, 1.0);
// }
const vert_spv align(4) = [828]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x9,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x47, 0x0,  0x3,  0x0,  0x7,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0x15, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x15, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0x15, 0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x3,  0x0, 0x15, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x1e, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x3,  0x0, 0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,
    0xa,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0xa,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x16, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x16, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x18, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x19, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x19, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x20, 0x0, 0x4,  0x0, 0x21, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x10, 0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x11, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0x21, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(location = 0) in Vertex {
//     flat uint color;
// } vertex;
//
// layout(location = 0) out uint color_0;
//
// void main() {
//     color_0 = vertex.color;
// }
const frag_spv align(4) = [408]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x8,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x15, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x2b, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,
    0x41, 0x0, 0x5,  0x0, 0xe,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x8,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0, 0x38, 0x0,  0x1,  0x0,
};
