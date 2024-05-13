const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "submission of multiple command buffers" {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;
    const queue = &dev.queues[queue_i];

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = queue });
    defer cmd_pool.deinit(gpa, dev);
    const cmd_bufs = (try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 5 }))[0..5];
    defer gpa.free(cmd_bufs);

    const width = 240;
    const height = 135;

    var image = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .r8_unorm,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .color_attachment = true,
            .transfer_source = true,
            .transfer_dest = true,
        },
        .misc = .{},
    });
    defer image.deinit(gpa, dev);
    const img_reqs = image.getMemoryRequirements(dev);
    var img_mem = try dev.alloc(gpa, .{
        .size = img_reqs.size,
        .type_index = img_reqs.findType(dev.*, .{ .device_local = true }, null).?,
    });
    defer dev.free(gpa, &img_mem);
    try image.bind(dev, &img_mem, 0);
    var view = try ngl.ImageView.init(gpa, dev, .{
        .image = &image,
        .type = .@"2d",
        .format = .r8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer view.deinit(gpa, dev);

    // Clear, `shaders[1]` draw, `shaders[2]` draw.
    const colors = [_]f32{ 1, 0.3, 0.6 };

    const shaders = try ngl.Shader.init(gpa, dev, &.{
        .{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = &vert_spv,
            .name = "main",
            .set_layouts = &.{},
            .push_constants = &.{},
            .specialization = null,
            .link = false,
        },
        .{
            .type = .fragment,
            .next = .{},
            .code = &frag_spv,
            .name = "main",
            .set_layouts = &.{},
            .push_constants = &.{},
            .specialization = .{
                .constants = &.{.{ .id = 0, .offset = 0, .size = 4 }},
                .data = @as([*]const u8, @ptrCast(&colors))[4..12],
            },
            .link = false,
        },
        .{
            .type = .fragment,
            .next = .{},
            .code = &frag_spv,
            .name = "main",
            .set_layouts = &.{},
            .push_constants = &.{},
            .specialization = .{
                .constants = &.{.{ .id = 0, .offset = 4, .size = 4 }},
                .data = @as([*]const u8, @ptrCast(&colors))[4..12],
            },
            .link = false,
        },
    });
    defer {
        for (shaders) |*shd|
            if (shd.*) |*s| s.deinit(gpa, dev) else |_| {};
        gpa.free(shaders);
    }

    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = width * height,
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    defer buf.deinit(gpa, dev);
    const buf_reqs = buf.getMemoryRequirements(dev);
    var buf_mem = try dev.alloc(gpa, .{
        .size = buf_reqs.size,
        .type_index = buf_reqs.findType(dev.*, .{
            .host_visible = true,
            .host_coherent = true,
        }, null).?,
    });
    defer dev.free(gpa, &buf_mem);
    try buf.bind(dev, &buf_mem, 0);
    const data = try buf_mem.map(dev, 0, width * height);

    var fence = try ngl.Fence.init(gpa, dev, .{ .status = .unsignaled });
    defer fence.deinit(gpa, dev);

    const blends = [2]ngl.Cmd.Blend{
        .{
            .color_source_factor = .one,
            .color_dest_factor = .one,
            .color_op = .reverse_subtract,
            .alpha_source_factor = .zero,
            .alpha_dest_factor = .zero,
            .alpha_op = .add,
        },
        .{
            .color_source_factor = .dest_color,
            .color_dest_factor = .one,
            .color_op = .reverse_subtract,
            .alpha_source_factor = .zero,
            .alpha_dest_factor = .zero,
            .alpha_op = .add,
        },
    };
    const subm_orders = [_][2]usize{ .{ 0, 1 }, .{ 1, 0 } };
    const expect_cols = blk: {
        const clr = colors[0];
        const fs0 = colors[1];
        const fs1 = colors[2];
        // Clear color -> `shaders[1]` color -> `shaders[2]` color.
        const x = clr * 1 - fs0 * 1;
        const f = x * 1 - fs1 * x;
        // Clear color -> `shaders[2]` color -> `shaders[1]` color.
        const y = clr * 1 - fs1 * clr;
        const s = y * 1 - fs0 * 1;
        break :blk [_]u8{ @round(f * 255), @round(s * 255) };
    };
    const deviation = 1;

    for (subm_orders, expect_cols) |order, col| {
        for ([_]bool{ false, true }) |split_subm| {
            @memset(data, @intFromFloat(255 * colors[0]));

            // Draw.
            for (cmd_bufs[0..2], shaders[1..3], blends) |*cmd_buf, *frag_shd, blend| {
                var cmd = try cmd_buf.begin(gpa, dev, .{
                    .one_time_submit = true,
                    .inheritance = null,
                });
                cmd.beginRendering(.{
                    .colors = &.{.{
                        .view = &view,
                        .layout = .color_attachment_optimal,
                        .load_op = .load,
                        .store_op = .store,
                        .clear_value = null,
                        .resolve = null,
                    }},
                    .depth = null,
                    .stencil = null,
                    .render_area = .{ .width = width, .height = height },
                    .layers = 1,
                    .contents = .@"inline",
                });
                cmd.setShaders(
                    &.{
                        .vertex,
                        .fragment,
                    },
                    &.{
                        if (shaders[0]) |*shd| shd else |err| return err,
                        if (frag_shd.*) |*shd| shd else |err| return err,
                    },
                );
                cmd.setVertexInput(&.{}, &.{});
                cmd.setPrimitiveTopology(.triangle_list);
                cmd.setViewports(&.{.{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                    .znear = 0,
                    .zfar = 0,
                }});
                cmd.setScissorRects(&.{.{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                }});
                cmd.setRasterizationEnable(true);
                cmd.setPolygonMode(.fill);
                cmd.setCullMode(.back);
                cmd.setFrontFace(.counter_clockwise);
                cmd.setSampleCount(.@"1");
                cmd.setSampleMask(0b1);
                cmd.setDepthBiasEnable(false);
                cmd.setDepthTestEnable(false);
                cmd.setDepthWriteEnable(false);
                cmd.setStencilTestEnable(false);
                cmd.setColorBlendEnable(0, &.{true});
                cmd.setColorBlend(0, &.{blend});
                cmd.setColorWrite(0, &.{.all});
                cmd.draw(3, 1, 0, 0);
                cmd.endRendering();
                try cmd.end();
            }

            // Clear image.
            {
                var cmd = try cmd_bufs[2].begin(gpa, dev, .{
                    .one_time_submit = true,
                    .inheritance = null,
                });
                cmd.barrier(&.{.{
                    .image = &.{.{
                        .source_stage_mask = .{},
                        .source_access_mask = .{},
                        .dest_stage_mask = .{ .copy = true },
                        .dest_access_mask = .{ .transfer_write = true },
                        .queue_transfer = null,
                        .old_layout = .unknown,
                        .new_layout = .transfer_dest_optimal,
                        .image = &image,
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .level = 0,
                            .levels = 1,
                            .layer = 0,
                            .layers = 1,
                        },
                    }},
                }});
                cmd.copyBufferToImage(&.{.{
                    .buffer = &buf,
                    .image = &image,
                    .image_layout = .transfer_dest_optimal,
                    .regions = &.{.{
                        .buffer_offset = 0,
                        .buffer_row_length = width,
                        .buffer_image_height = height,
                        .image_aspect = .color,
                        .image_level = 0,
                        .image_x = 0,
                        .image_y = 0,
                        .image_z_or_layer = 0,
                        .image_width = width,
                        .image_height = height,
                        .image_depth_or_layers = 1,
                    }},
                }});
                cmd.barrier(&.{.{
                    .image = &.{.{
                        .source_stage_mask = .{ .copy = true },
                        .source_access_mask = .{ .transfer_write = true },
                        .dest_stage_mask = .{ .color_attachment_output = true },
                        .dest_access_mask = .{
                            .color_attachment_read = true,
                            .color_attachment_write = true,
                        },
                        .queue_transfer = null,
                        .old_layout = .transfer_dest_optimal,
                        .new_layout = .color_attachment_optimal,
                        .image = &image,
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .level = 0,
                            .levels = 1,
                            .layer = 0,
                            .layers = 1,
                        },
                    }},
                }});
                try cmd.end();
            }

            // Synchronize draws.
            {
                var cmd = try cmd_bufs[3].begin(gpa, dev, .{
                    .one_time_submit = true,
                    .inheritance = null,
                });
                cmd.barrier(&.{.{
                    .global = &.{.{
                        .source_stage_mask = .{ .color_attachment_output = true },
                        .source_access_mask = .{ .color_attachment_write = true },
                        .dest_stage_mask = .{ .color_attachment_output = true },
                        .dest_access_mask = .{
                            .color_attachment_read = true,
                            .color_attachment_write = true,
                        },
                    }},
                }});
                try cmd.end();
            }

            // Copy result.
            {
                var cmd = try cmd_bufs[4].begin(gpa, dev, .{
                    .one_time_submit = true,
                    .inheritance = null,
                });
                cmd.barrier(&.{.{
                    .image = &.{.{
                        .source_stage_mask = .{ .color_attachment_output = true },
                        .source_access_mask = .{ .color_attachment_write = true },
                        .dest_stage_mask = .{ .copy = true },
                        .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
                        .queue_transfer = null,
                        .old_layout = .color_attachment_optimal,
                        .new_layout = .transfer_source_optimal,
                        .image = &image,
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .level = 0,
                            .levels = 1,
                            .layer = 0,
                            .layers = 1,
                        },
                    }},
                }});
                cmd.copyImageToBuffer(&.{.{
                    .buffer = &buf,
                    .image = &image,
                    .image_layout = .transfer_source_optimal,
                    .regions = &.{.{
                        .buffer_offset = 0,
                        .buffer_row_length = width,
                        .buffer_image_height = height,
                        .image_aspect = .color,
                        .image_level = 0,
                        .image_x = 0,
                        .image_y = 0,
                        .image_z_or_layer = 0,
                        .image_width = width,
                        .image_height = height,
                        .image_depth_or_layers = 1,
                    }},
                }});
                try cmd.end();
            }

            ctx.lockQueue(queue_i);

            // These should be equivalent.
            const subms: []const ngl.Queue.Submit = if (split_subm) &.{
                .{
                    .commands = &.{.{ .command_buffer = &cmd_bufs[2] }},
                    .wait = &.{},
                    .signal = &.{},
                },
                .{
                    .commands = &.{.{ .command_buffer = &cmd_bufs[order[0]] }},
                    .wait = &.{},
                    .signal = &.{},
                },
                .{
                    .commands = &.{.{ .command_buffer = &cmd_bufs[3] }},
                    .wait = &.{},
                    .signal = &.{},
                },
                .{
                    .commands = &.{.{ .command_buffer = &cmd_bufs[order[1]] }},
                    .wait = &.{},
                    .signal = &.{},
                },
                .{
                    .commands = &.{.{ .command_buffer = &cmd_bufs[4] }},
                    .wait = &.{},
                    .signal = &.{},
                },
            } else &.{.{
                .commands = &.{
                    .{ .command_buffer = &cmd_bufs[2] },
                    .{ .command_buffer = &cmd_bufs[order[0]] },
                    .{ .command_buffer = &cmd_bufs[3] },
                    .{ .command_buffer = &cmd_bufs[order[1]] },
                    .{ .command_buffer = &cmd_bufs[4] },
                },
                .wait = &.{},
                .signal = &.{},
            }};

            queue.submit(gpa, dev, &fence, subms) catch |err| {
                ctx.unlockQueue(queue_i);
                return err;
            };

            ctx.unlockQueue(queue_i);

            try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});
            try ngl.Fence.reset(gpa, dev, &.{&fence});
            try cmd_pool.reset(dev, .keep);

            try testing.expect(data[0] >= col -| deviation and data[0] <= col +| deviation);
            try testing.expect(std.mem.allEqual(u8, data, data[0]));
        }
    }
}

// #version 460 core
//
// void main() {
//     gl_Position = vec4(
//         float(gl_VertexIndex / 2) * 4.0 - 1.0,
//         float(gl_VertexIndex % 2) * 4.0 - 1.0,
//         0.0,
//         1.0);
// }
const vert_spv align(4) = [776]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x11, 0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2a, 0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x3,  0x0, 0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xe,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xe,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x10, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x10, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xe,  0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x40,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x21, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x12, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x87, 0x0,  0x5,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x14, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x6f, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x85, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x83, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0x18, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x8b, 0x0,  0x5,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x6f, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1c, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x85, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x83, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x50, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x1e, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x41, 0x0, 0x5,  0x0, 0x21, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x22, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0, 0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(constant_id = 0) const float color = 0.0;
//
// layout(location = 0) out float color_0;
//
// void main() {
//     color_0 = color;
// }
const frag_spv align(4) = [260]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x6,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x8,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x32, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};
