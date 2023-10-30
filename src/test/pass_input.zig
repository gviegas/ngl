const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const queue_locks = &@import("test.zig").queue_locks;
const shd_code = @import("shd_code.zig");

test "subpass input" {
    const dev = &context().device;
    const queue_i = for (0..dev.queue_n) |i| {
        if (dev.queues[i].capabilities.graphics and dev.queues[i].capabilities.transfer) break i;
    } else unreachable;

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);

    const w = 40;
    const h = 56;

    const idx_data = [6]u16{
        0, 1, 2,
        0, 2, 3,
    };
    const idx_off = 0;
    const idx_size = idx_off + @sizeOf(@TypeOf(idx_data));
    if (idx_size & @as(usize, 3) != 0) unreachable;

    const pos_data = [12]f32{
        -1, 0,  0,
        0,  -1, 0,
        1,  0,  0,
        0,  1,  0,
    };
    const col_data = [4]f32{
        0.5,
        0.5,
        0.5,
        0.5,
    };
    const pos_data_2 = [6]f32{
        -3, -1,
        1,  -1,
        1,  3,
    };
    const pos_off = 0;
    const col_off = pos_off + @sizeOf(@TypeOf(pos_data));
    const pos_off_2 = col_off + @sizeOf(@TypeOf(col_data));
    const vert_size = pos_off_2 + @sizeOf(@TypeOf(pos_data_2));

    const unif_data = [8]f32{
        1, 1, 1, 1,
        0, 0, 0, undefined,
    };
    const unif_off = 0;
    const unif_size = unif_off + @sizeOf(@TypeOf(unif_data));

    const size = @max(w * h, idx_size + vert_size + unif_size);

    const copy_off: struct {
        unif: u64,
        idx: u64,
        pos: u64,
        col: u64,
        pos_2: u64,
    } = .{
        .unif = unif_off,
        .idx = unif_size + idx_off,
        .pos = unif_size + idx_size + pos_off,
        .col = unif_size + idx_size + col_off,
        .pos_2 = unif_size + idx_size + pos_off_2,
    };
    if (copy_off.pos_2 + @sizeOf(@TypeOf(pos_data_2)) - copy_off.pos != vert_size) unreachable;

    var inp_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .r8_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .color_attachment = true,
            .input_attachment = true,
            .transient_attachment = true,
            .transfer_source = false,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    var inp_mem = blk: {
        errdefer inp_img.deinit(gpa, dev);
        const mem_reqs = inp_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .lazily_allocated = true }, null) orelse
                mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try inp_img.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        inp_img.deinit(gpa, dev);
        dev.free(gpa, &inp_mem);
    }
    var inp_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &inp_img,
        .type = .@"2d",
        .format = .r8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer inp_view.deinit(gpa, dev);

    var col_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .r8_unorm,
        .width = w,
        .height = h,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .color_attachment = true,
            .transfer_source = true,
            .transfer_dest = false,
        },
        .misc = .{},
        .initial_layout = .undefined,
    });
    var col_mem = blk: {
        errdefer col_img.deinit(gpa, dev);
        const mem_reqs = col_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
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
        .format = .r8_unorm,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer col_view.deinit(gpa, dev);

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
        try stg_buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        stg_buf.deinit(gpa, dev);
        dev.free(gpa, &stg_mem);
    }

    var idx_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = idx_size,
        .usage = .{
            .index_buffer = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
    });
    var idx_mem = blk: {
        errdefer idx_buf.deinit(gpa, dev);
        const mem_reqs = idx_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try idx_buf.bindMemory(dev, &mem, 0);
        break :blk mem;
    };
    defer {
        idx_buf.deinit(gpa, dev);
        dev.free(gpa, &idx_mem);
    }

    var vert_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = vert_size,
        .usage = .{
            .vertex_buffer = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
    });
    var vert_mem = blk: {
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
        dev.free(gpa, &vert_mem);
    }

    var unif_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = unif_size,
        .usage = .{
            .uniform_buffer = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
    });
    var unif_mem = blk: {
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
        dev.free(gpa, &unif_mem);
    }

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.gen_desc_bindings,
    });
    defer set_layt.deinit(gpa, dev);

    var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
        .bindings = &shd_code.pass_input_desc_bindings,
    });
    defer set_layt_2.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{ &set_layt, &set_layt_2 },
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var rp = try ngl.RenderPass.init(gpa, dev, .{
        .attachments = &.{
            // `inp_view`
            .{
                .format = .r8_unorm,
                .samples = .@"1",
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .shader_read_only_optimal,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
            // `col_view`
            .{
                .format = .r8_unorm,
                .samples = .@"1",
                .load_op = .dont_care,
                .store_op = .store,
                .initial_layout = .undefined,
                .final_layout = .transfer_source_optimal,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
        },
        .subpasses = &.{
            // Write to `inp_view`
            .{
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
            },
            // Read from `inp_view`
            .{
                .pipeline_type = .graphics,
                .input_attachments = &.{.{
                    .index = 0,
                    .layout = .shader_read_only_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                }},
                .color_attachments = &.{.{
                    .index = 1,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                }},
                .depth_stencil_attachment = null,
                .preserve_attachments = null,
            },
        },
        .dependencies = &.{
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
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 1 },
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{ .vertex_attribute_input = true },
                .dest_access_mask = .{ .vertex_attribute_read = true },
                .by_region = false,
            },
            .{
                .source_subpass = .{ .index = 0 },
                .dest_subpass = .{ .index = 1 },
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .fragment_shader = true },
                .dest_access_mask = .{ .input_attachment_read = true },
                .by_region = true,
            },
            .{
                .source_subpass = .{ .index = 1 },
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

    var pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
        .states = &.{
            // Used in the first subpass
            .{
                .stages = &.{
                    .{
                        .stage = .vertex,
                        .code = &shd_code.gen_vert_spv,
                        .name = "main",
                    },
                    .{
                        .stage = .fragment,
                        .code = &shd_code.gen_frag_spv,
                        .name = "main",
                    },
                },
                .layout = &pl_layt,
                .vertex_input = &.{
                    .bindings = &shd_code.gen_input_bindings,
                    .attributes = &shd_code.gen_input_attributes,
                    .topology = .triangle_list,
                },
                .viewport = null, // Dynamic
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = true,
                    .samples = .@"1",
                },
                .depth_stencil = null,
                .color_blend = &.{
                    .attachments = &.{.{
                        .blend = null,
                        .write = .all,
                    }},
                    .constants = null,
                },
                .render_pass = &rp,
                .subpass = 0,
            },
            // Used in the second subpass
            .{
                .stages = &.{
                    .{
                        .stage = .vertex,
                        .code = &shd_code.screen_vert_spv,
                        .name = "main",
                    },
                    .{
                        .stage = .fragment,
                        .code = &shd_code.pass_input_frag_spv,
                        .name = "main",
                    },
                },
                .layout = &pl_layt,
                .vertex_input = &.{
                    .bindings = &shd_code.screen_input_bindings,
                    .attributes = &shd_code.screen_input_attributes,
                    .topology = .triangle_list,
                },
                .viewport = null, // Dynamic
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = true,
                    .samples = .@"1",
                },
                .depth_stencil = null,
                .color_blend = &.{
                    .attachments = &.{.{
                        .blend = null,
                        .write = .all,
                    }},
                    .constants = null,
                },
                .render_pass = &rp,
                .subpass = 1,
            },
        },
        .cache = null,
    });
    defer {
        for (pls) |*pl| pl.deinit(gpa, dev);
        gpa.free(pls);
    }

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 2,
        .pool_size = .{ .uniform_buffer = 1, .input_attachment = 1 },
    });
    defer desc_pool.deinit(gpa, dev);
    var desc_sets = try desc_pool.alloc(gpa, dev, .{ .layouts = &.{ &set_layt, &set_layt_2 } });
    defer gpa.free(desc_sets);

    try ngl.DescriptorSet.write(gpa, dev, &.{
        .{
            .descriptor_set = &desc_sets[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &unif_buf,
                .offset = unif_off,
                .range = unif_size,
            }} },
        },
        .{
            .descriptor_set = &desc_sets[1],
            .binding = 0,
            .element = 0,
            .contents = .{ .input_attachment = &.{.{
                .view = &inp_view,
                .layout = .shader_read_only_optimal,
            }} },
        },
    });

    var fb = try ngl.FrameBuffer.init(gpa, dev, .{
        .render_pass = &rp,
        .attachments = &.{ &inp_view, &col_view },
        .width = w,
        .height = h,
        .layers = 1,
    });
    defer fb.deinit(gpa, dev);

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        var s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    // Update index, vertex and uniform buffers using a staging buffer,
    // then record a 2-subpass render pass instance that generates an
    // input attachment in the first subpass and loads from it in the
    // second subpass, then copy the color attachment output from the
    // last subpass into the staging buffer

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf,
            .dest = &idx_buf,
            .regions = &.{.{
                .source_offset = copy_off.idx,
                .dest_offset = idx_off,
                .size = idx_size,
            }},
        },
        .{
            .source = &stg_buf,
            .dest = &vert_buf,
            .regions = &.{.{
                .source_offset = copy_off.pos,
                .dest_offset = pos_off,
                .size = vert_size,
            }},
        },
        .{
            .source = &stg_buf,
            .dest = &unif_buf,
            .regions = &.{.{
                .source_offset = copy_off.unif,
                .dest_offset = unif_off,
                .size = unif_size,
            }},
        },
    });

    cmd.beginRenderPass(.{
        .render_pass = &rp,
        .frame_buffer = &fb,
        .render_area = .{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
        },
        .clear_values = &.{
            .{ .color_f32 = .{ 1, 0, 0, 0 } }, // `inp_view`
            null, // `col_view`
        },
    }, .{ .contents = .inline_only });
    cmd.setViewport(.{
        .x = 0,
        .y = 0,
        .width = w,
        .height = h,
        .near = 0,
        .far = 1,
    });
    // Both pipelines have the same layout, but the first
    // uses only set #0 while the second uses only set #1
    cmd.setDescriptors(.graphics, &pl_layt, 0, &.{ &desc_sets[0], &desc_sets[1] });
    cmd.setPipeline(&pls[0]);
    cmd.setIndexBuffer(.u16, &idx_buf, idx_off, idx_size);
    cmd.setVertexBuffers(
        0,
        &.{ &vert_buf, &vert_buf },
        &.{ pos_off, col_off },
        &.{ @sizeOf(@TypeOf(pos_data)), @sizeOf(@TypeOf(col_data)) },
    );
    cmd.drawIndexed(6, 1, 0, 0, 0);
    cmd.nextSubpass(.{ .contents = .inline_only }, .{});
    cmd.setPipeline(&pls[1]);
    cmd.setVertexBuffers(0, &.{&vert_buf}, &.{pos_off_2}, &.{@sizeOf(@TypeOf(pos_data_2))});
    cmd.draw(3, 1, 0, 0);
    cmd.endRenderPass(.{});

    cmd.copyImageToBuffer(&.{.{
        .buffer = &stg_buf,
        .image = &col_img,
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

    var p = try stg_mem.map(dev, 0, null);
    {
        const off = copy_off.idx;
        const len = idx_size;
        const source = @as([*]const u8, @ptrCast(&idx_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }
    {
        const off = copy_off.pos;
        const len = @sizeOf(@TypeOf(pos_data));
        const source = @as([*]const u8, @ptrCast(&pos_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }
    {
        const off = copy_off.col;
        const len = @sizeOf(@TypeOf(col_data));
        const source = @as([*]const u8, @ptrCast(&col_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }
    {
        const off = copy_off.pos_2;
        const len = @sizeOf(@TypeOf(pos_data_2));
        const source = @as([*]const u8, @ptrCast(&pos_data_2))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }
    {
        const off = copy_off.unif;
        const len = unif_size;
        const source = @as([*]const u8, @ptrCast(&unif_data))[0..len];
        const dest = p[off .. off + len];
        @memcpy(dest, source);
    }

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

    // The first subpass cleared attachment #0 (`inp_view`) and drew onto it
    // The second subpass wrote every fragment of attachment #1 (`col_view`)
    // using attachment #0 as a subpass input attachment

    const s = p[0 .. w * h];

    const clear_col = 255;
    const vert_col = 128;

    const clear_col_n = std.mem.count(u8, s, &.{clear_col});
    const vert_col_n = std.mem.count(u8, s, &.{vert_col});

    // We didn't clear the final color attachment
    // We did clear the first color attachment (used as input afterwards)
    try testing.expectEqual(clear_col_n + vert_col_n, s.len);

    try testing.expectApproxEqAbs(@as(f64, @floatFromInt(clear_col_n)) / (w * h / 2), 1, 0.1);
    try testing.expectApproxEqAbs(@as(f64, @floatFromInt(vert_col_n)) / (w * h / 2), 1, 0.1);

    // This is meant to simplify testing; it's not required for correctness
    if (w & 1 != 0 or h & 1 != 0) @compileError("Use even values for `w` and `h`");
    for (0..h / 2) |i| {
        const j = h - i - 1;
        const a = s[i * w .. i * w + w];
        const b = s[j * w .. j * w + w];
        try testing.expect(std.mem.eql(u8, a, b));
        // Assume that it may be off by one texel
        var k: usize = 0;
        while (k < w / 2) : (k += 1) {
            if (a[k] == a[w - k - 1]) continue;
            k += 1;
            while (k < w / 2) : (k += 1) {
                try testing.expectEqual(a[k], vert_col);
                try testing.expectEqual(a[k], a[w - k - 1]);
            }
        }
    }
    {
        const n = std.mem.count(u8, s[0..w], &.{clear_col});
        const m = std.mem.count(u8, s[s.len / 2 .. s.len / 2 + w], &.{clear_col});
        try testing.expect(n > m);
    }

    if (false) {
        var str = std.ArrayList(u8).init(gpa);
        defer str.deinit();
        for (0..h) |y| {
            for (0..w) |x| {
                const i = (x + w * y) * 1;
                try str.appendSlice(switch (p[i]) {
                    clear_col => " ♢",
                    vert_col => " ♦",
                    else => unreachable,
                });
            }
            try str.append('\n');
        }
        std.debug.print("{s}", .{str.items});
    }
}
