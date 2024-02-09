const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "drawIndirect command" {
    try testDrawIndirectCommand(false, @src().fn_name);
}

test "drawIndexedIndirect command" {
    try testDrawIndirectCommand(true, @src().fn_name);
}

fn testDrawIndirectCommand(comptime indexed: bool, comptime test_name: []const u8) !void {
    const ctx = context();
    const dev = &ctx.device;
    const core_feat = ngl.Feature.get(gpa, &ctx.instance, ctx.device_desc, .core).?;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;
    if (!indexed and !core_feat.draw.indirect_command)
        return error.SkipZigTest;
    if (indexed and !core_feat.draw.indexed_indirect_command)
        return error.SkipZigTest;

    const indir_size = 3 * @sizeOf(if (!indexed)
        ngl.Cmd.DrawIndirectCommand
    else
        ngl.Cmd.DrawIndexedIndirectCommand);
    var indir_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = indir_size,
        .usage = .{ .indirect_buffer = true, .transfer_dest = true },
    });
    defer indir_buf.deinit(gpa, dev);
    var indir_mem = blk: {
        const mem_reqs = indir_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try indir_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &indir_mem);

    const triangle = struct {
        const stride = @sizeOf(Vertex);
        const position_format = ngl.Format.rgb32_sfloat;
        const color_format = ngl.Format.rgba32_sfloat;
        const position_offset = @offsetOf(Vertex, "x");
        const color_offset = @offsetOf(Vertex, "r");
        const topology = ngl.Primitive.Topology.triangle_list;
        const clockwise = !indexed;

        const Vertex = packed struct {
            x: f32,
            y: f32,
            z: f32,
            r: f32,
            g: f32,
            b: f32,
            a: f32,

            fn init(position: [3]f32, color: [4]f32) Vertex {
                return .{
                    .x = position[0],
                    .y = position[1],
                    .z = position[2],
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                    .a = color[3],
                };
            }
        };

        const top_left_color = [4]f32{ 1, 0, 0, 1 };
        const bottom_right_color = [4]f32{ 0, 1, 0, 1 };

        // Each triangle will cover one quadrant of the render area
        const data: struct {
            top_left: [3]Vertex = .{
                Vertex.init(.{ 0, 0, 0 }, top_left_color),
                Vertex.init(.{ -2, 0, 0 }, top_left_color),
                Vertex.init(.{ 0, -2, 0 }, top_left_color),
            },
            bottom_right: [3]Vertex = .{
                Vertex.init(.{ 0, 0, 0 }, bottom_right_color),
                Vertex.init(.{ 2, 0, 0 }, bottom_right_color),
                Vertex.init(.{ 0, 2, 0 }, bottom_right_color),
            },
        } = .{};

        // Invert the winding order for indexed indirect draw
        const indices = if (indexed) [3]u16{ 2, 1, 0 } else {};
    };

    var vert_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = @sizeOf(@TypeOf(triangle.data)),
        .usage = .{ .vertex_buffer = true, .transfer_dest = true },
    });
    defer vert_buf.deinit(gpa, dev);
    var vert_mem = blk: {
        const mem_reqs = vert_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try vert_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &vert_mem);

    var idx_buf: ngl.Buffer = undefined;
    var idx_mem: ngl.Memory = undefined;
    if (indexed) {
        idx_buf = try ngl.Buffer.init(gpa, dev, .{
            .size = @sizeOf(@TypeOf(triangle.indices)),
            .usage = .{ .index_buffer = true, .transfer_dest = true },
        });
        errdefer idx_buf.deinit(gpa, dev);
        idx_mem = blk: {
            const mem_reqs = idx_buf.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try idx_buf.bind(dev, &mem, 0);
            break :blk mem;
        };
    }
    defer if (indexed) {
        idx_buf.deinit(gpa, dev);
        dev.free(gpa, &idx_mem);
    };

    const width = 32;
    const height = 24;

    var color_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .color_attachment = true, .transfer_source = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    defer color_img.deinit(gpa, dev);
    var color_mem = blk: {
        const mem_reqs = color_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try color_img.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &color_mem);
    var color_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &color_img,
        .type = .@"2d",
        .format = .rgba8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = null,
            .base_layer = 0,
            .layers = null,
        },
    });
    defer color_view.deinit(gpa, dev);

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
        .dependencies = null,
    });
    defer rp.deinit(gpa, dev);

    var fb = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp,
        .attachments = &.{&color_view},
        .width = width,
        .height = height,
        .layers = 1,
    });
    defer fb.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = null,
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var pl = blk: {
        const s = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{.{
                .stages = &.{
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
                },
                .layout = &pl_layt,
                .primitive = &.{
                    .bindings = &.{.{
                        .binding = 0,
                        .stride = triangle.stride,
                        .step_rate = .vertex,
                    }},
                    .attributes = &.{
                        .{
                            .location = 0,
                            .binding = 0,
                            .format = triangle.position_format,
                            .offset = triangle.position_offset,
                        },
                        .{
                            .location = 1,
                            .binding = 0,
                            .format = triangle.color_format,
                            .offset = triangle.color_offset,
                        },
                    },
                    .topology = triangle.topology,
                },
                .viewport = &.{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                    .near = 0,
                    .far = 0,
                },
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = triangle.clockwise,
                    .samples = .@"1",
                },
                .depth_stencil = null,
                .color_blend = &.{
                    .attachments = &.{.{ .blend = null, .write = .all }},
                    .constants = .unused,
                },
                .render_pass = &rp,
                .subpass = 0,
            }},
            .cache = null,
        });
        defer gpa.free(s);
        break :blk s[0];
    };
    defer pl.deinit(gpa, dev);

    const indir_stg_pad = blk: {
        const vert_align = @alignOf(@TypeOf(triangle.data));
        break :blk vert_align - (indir_size % vert_align);
    };
    const vert_stg_off = indir_size + indir_stg_pad;
    const idx_stg_off = vert_stg_off + @sizeOf(@TypeOf(triangle.data));
    const upld_size = vert_stg_off + idx_stg_off + @sizeOf(@TypeOf(triangle.indices));
    const rdbk_size = width * height * 4;

    var stg_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = @max(upld_size, rdbk_size),
        .usage = .{ .transfer_source = true, .transfer_dest = true },
    });
    defer stg_buf.deinit(gpa, dev);
    var stg_mem = blk: {
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
    defer dev.free(gpa, &stg_mem);
    const stg_data = try stg_mem.map(dev, 0, null);

    const indir_cmds = if (!indexed) blk: {
        const indir_cmd = ngl.Cmd.DrawIndirectCommand{
            .vertex_count = 3,
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        };
        break :blk [3]ngl.Cmd.DrawIndirectCommand{
            indir_cmd,
            .{
                .vertex_count = 0,
                .instance_count = 0,
                .first_vertex = 0,
                .first_instance = 0,
            },
            indir_cmd,
        };
    } else blk: {
        const indir_cmd = ngl.Cmd.DrawIndexedIndirectCommand{
            .index_count = 3,
            .instance_count = 1,
            .first_index = 0,
            .vertex_offset = 0,
            .first_instance = 0,
        };
        break :blk [3]ngl.Cmd.DrawIndexedIndirectCommand{
            indir_cmd,
            .{
                .index_count = 0,
                .instance_count = 0,
                .first_index = 0,
                .vertex_offset = 0,
                .first_instance = 0,
            },
            indir_cmd,
        };
    };
    comptime if (@sizeOf(@TypeOf(indir_cmds)) != indir_size) unreachable;
    @memcpy(stg_data, @as([*]const u8, @ptrCast(&indir_cmds))[0..@sizeOf(@TypeOf(indir_cmds))]);

    @memcpy(
        stg_data[vert_stg_off..],
        @as([*]const u8, @ptrCast(&triangle.data))[0..@sizeOf(@TypeOf(triangle.data))],
    );

    if (indexed) @memcpy(
        stg_data[idx_stg_off..],
        @as([*]const u8, @ptrCast(&triangle.indices))[0..@sizeOf(@TypeOf(triangle.indices))],
    );

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    const clear_val = ngl.Cmd.ClearValue{ .color_f32 = [_]f32{1} ** 4 };
    const drawCall = if (!indexed) ngl.Cmd.drawIndirect else ngl.Cmd.drawIndexedIndirect;

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.copyBuffer(&[_]ngl.Cmd.BufferCopy{
        .{
            .source = &stg_buf,
            .dest = &indir_buf,
            .regions = &.{.{
                .source_offset = 0,
                .dest_offset = 0,
                .size = indir_size,
            }},
        },
        .{
            .source = &stg_buf,
            .dest = &vert_buf,
            .regions = &.{.{
                .source_offset = vert_stg_off,
                .dest_offset = 0,
                .size = @sizeOf(@TypeOf(triangle.data)),
            }},
        },
    } ++ if (indexed) &[_]ngl.Cmd.BufferCopy{.{
        .source = &stg_buf,
        .dest = &idx_buf,
        .regions = &.{.{
            .source_offset = idx_stg_off,
            .dest_offset = 0,
            .size = @sizeOf(@TypeOf(triangle.indices)),
        }},
    }} else &[_]ngl.Cmd.BufferCopy{});
    cmd.pipelineBarrier(&.{.{
        .global_dependencies = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{
                .draw_indirect = true,
                .index_input = indexed,
                .vertex_attribute_input = true,
            },
            .dest_access_mask = .{
                .indirect_command_read = true,
                .index_read = indexed,
                .vertex_attribute_read = true,
            },
        }},
        .by_region = false,
    }});
    cmd.beginRenderPass(
        .{
            .render_pass = &rp,
            .frame_buffer = &fb,
            .render_area = .{
                .x = 0,
                .y = 0,
                .width = width,
                .height = height,
            },
            .clear_values = &.{clear_val},
        },
        .{ .contents = .inline_only },
    );
    cmd.setPipeline(&pl);
    if (indexed)
        cmd.setIndexBuffer(.u16, &idx_buf, 0, @sizeOf(@TypeOf(triangle.indices)));
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "top_left")},
        &.{@sizeOf(@TypeOf(triangle.data.top_left))},
    );
    drawCall(&cmd, &indir_buf, 0, 1, 0);
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "bottom_right")},
        &.{@sizeOf(@TypeOf(triangle.data.bottom_right))},
    );
    drawCall(&cmd, &indir_buf, indir_size - indir_size / 3, 1, 0);
    cmd.endRenderPass(.{});
    cmd.pipelineBarrier(&.{.{
        .global_dependencies = &.{.{
            .source_stage_mask = .{ .color_attachment_output = true },
            .source_access_mask = .{ .color_attachment_write = true },
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
        }},
        .by_region = true,
    }});
    cmd.copyImageToBuffer(&.{.{
        .buffer = &stg_buf,
        .image = &color_img,
        .image_layout = .transfer_source_optimal,
        .image_type = .@"2d",
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

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);
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

    const topl_col = [4]u8{
        255 * triangle.top_left_color[0],
        255 * triangle.top_left_color[1],
        255 * triangle.top_left_color[2],
        255 * triangle.top_left_color[3],
    };
    const botr_col = [4]u8{
        255 * triangle.bottom_right_color[0],
        255 * triangle.bottom_right_color[1],
        255 * triangle.bottom_right_color[2],
        255 * triangle.bottom_right_color[3],
    };
    const clear_col = [4]u8{
        255 * clear_val.color_f32[0],
        255 * clear_val.color_f32[1],
        255 * clear_val.color_f32[2],
        255 * clear_val.color_f32[3],
    };

    for (0..height / 2) |y| {
        for (0..width / 2) |x| {
            const topl = (y * width + x) * 4;
            const topr = topl + width / 2 * 4;
            const botr = topr + width * height / 2 * 4;
            const botl = botr - width / 2 * 4;
            try testing.expect(std.mem.eql(u8, stg_data[topl .. topl + 4], &topl_col));
            try testing.expect(std.mem.eql(u8, stg_data[topr .. topr + 4], &clear_col));
            try testing.expect(std.mem.eql(u8, stg_data[botr .. botr + 4], &botr_col));
            try testing.expect(std.mem.eql(u8, stg_data[botl .. botl + 4], &clear_col));
        }
    }

    if (indexed) return;

    if (@import("test.zig").writer) |writer| {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        try str.appendSlice("\n" ++ test_name ++ "\n");
        for (0..height) |y| {
            for (0..width) |x| {
                const i = (y * width + x) * 4;
                const b: []const u8 = stg_data[i .. i + 4];
                try str.appendSlice(
                    if (std.mem.eql(u8, b, &topl_col))
                        "🔴"
                    else if (std.mem.eql(u8, b, &botr_col))
                        "🔵"
                    else if (std.mem.eql(u8, b, &clear_col))
                        "⚪"
                    else
                        unreachable,
                );
            }
            try str.append('\n');
        }
        try writer.print("{s}", .{str.items});
    }
}

// #version 460 core
//
// layout(location = 0) in vec3 position;
// layout(location = 1) in vec4 color;
//
// layout(location = 0) out vec4 out_color;
//
// void main() {
//     out_color = color;
//     gl_Position = vec4(position, 1.0);
// }
const vert_spv align(4) = [752]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x9,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x10, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0x10, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x47, 0x0,  0x3,  0x0,  0x10, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0, 0x17, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x13, 0x0, 0x2,  0x0, 0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x6,  0x0, 0x10, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x12, 0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x0,  0x0,  0x80, 0x3f, 0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x15, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x18, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x19, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x12, 0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(location = 0) in vec4 color;
//
// layout(location = 0) out vec4 color_0;
//
// void main() {
//     color_0 = color;
// }
const frag_spv align(4) = [312]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x3,  0x0, 0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0, 0x38, 0x0,  0x1,  0x0,
};
