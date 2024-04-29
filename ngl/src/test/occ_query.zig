const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "occlusion query without draws" {
    const dev = &context().device;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;

    const query_count = 5;
    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = query_count,
    });
    defer query_pool.deinit(gpa, dev);
    const query_layt = query_pool.type.getLayout(dev, query_count, false);
    const query_layt_avail = query_pool.type.getLayout(dev, query_count, true);

    const buf_size = 2 * (query_layt.size + query_layt_avail.size);
    var buf = try ngl.Buffer.init(gpa, dev, .{
        .size = buf_size,
        .usage = .{ .transfer_dest = true },
    });
    defer buf.deinit(gpa, dev);
    var mem = blk: {
        const mem_reqs = buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &mem);
    const data = (try mem.map(dev, 0, null))[0..buf_size];
    @memset(data, 255);

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.resetQueryPool(&query_pool, 0, query_count);
    cmd.beginQuery(&query_pool, 4, .{});
    cmd.endQuery(&query_pool, 4);
    cmd.beginQuery(&query_pool, 0, .{});
    cmd.endQuery(&query_pool, 0);
    cmd.beginQuery(&query_pool, 2, .{});
    cmd.endQuery(&query_pool, 2);
    cmd.beginQuery(&query_pool, 1, .{});
    cmd.endQuery(&query_pool, 1);
    cmd.beginQuery(&query_pool, 3, .{});
    cmd.endQuery(&query_pool, 3);
    cmd.copyQueryPoolResults(&query_pool, 2, 3, &buf, 2 * query_layt.size, .{
        .wait = false,
        .with_availability = true,
    });
    cmd.copyQueryPoolResults(&query_pool, 0, 2, &buf, 0, .{});
    cmd.copyQueryPoolResults(&query_pool, 0, query_count, &buf, query_layt.size, .{});
    cmd.copyQueryPoolResults(&query_pool, 4, 1, &buf, buf_size - query_layt_avail.size, .{
        .wait = false,
        .with_availability = true,
    });
    try cmd.end();

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);
    {
        context().lockQueue(queue_i);
        defer context().unlockQueue(queue_i);

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    var query_resolve = ngl.QueryResolve(.occlusion){};
    defer query_resolve.free(gpa);

    try query_resolve.resolve(gpa, dev, 0, 2, false, data);
    try testing.expectEqual(query_resolve.resolved_results.len, 2);
    for (query_resolve.resolved_results) |r|
        try testing.expectEqual(r.samples_passed, 0);

    try query_resolve.resolve(gpa, dev, 0, query_count, false, data[query_layt.size..]);
    try testing.expectEqual(query_resolve.resolved_results.len, query_count);
    for (query_resolve.resolved_results) |r|
        try testing.expectEqual(r.samples_passed, 0);

    try query_resolve.resolve(gpa, dev, 0, 3, true, data[2 * query_layt.size ..]);
    try testing.expectEqual(query_resolve.resolved_results.len, 3);
    for (query_resolve.resolved_results) |r|
        if (r.samples_passed) |x| try testing.expectEqual(x, 0);

    try query_resolve.resolve(gpa, dev, 0, 1, true, data[buf_size - query_layt_avail.size ..]);
    try testing.expectEqual(query_resolve.resolved_results.len, 1);
    if (query_resolve.resolved_results[0].samples_passed) |x|
        try testing.expectEqual(x, 0);

    var query_resolve_2 = ngl.QueryResolve(.occlusion){};
    defer query_resolve_2.free(gpa);

    try query_resolve_2.resolve(gpa, dev, 1, query_count - 1, false, data[query_layt.size..]);
    try testing.expectEqual(query_resolve_2.resolved_results.len, query_count - 1);
    try query_resolve.resolve(gpa, dev, 0, query_count, false, data[query_layt.size..]);
    for (query_resolve_2.resolved_results, query_resolve.resolved_results[1..]) |x, y|
        try testing.expectEqual(x, y);

    try query_resolve_2.resolve(gpa, dev, 1, 2, true, data[2 * query_layt.size ..]);
    try testing.expectEqual(query_resolve_2.resolved_results.len, 2);
    try query_resolve.resolve(gpa, dev, 0, 3, true, data[2 * query_layt.size ..]);
    for (query_resolve_2.resolved_results, query_resolve.resolved_results[1..]) |x, y|
        try testing.expectEqual(x, y);
}

test "occlusion query" {
    try testOcclusionQuery(false);
}

test "occlusion query precise" {
    try testOcclusionQuery(true);
}

fn testOcclusionQuery(comptime precise: bool) !void {
    const ctx = context();
    const dev = &ctx.device;
    const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;
    if (precise) {
        const core_feat = ngl.Feature.get(gpa, ctx.gpu, .core).?;
        if (!core_feat.query.occlusion_precise) return error.SkipZigTest;
    }

    const query_count = 4;
    var query_pool = try ngl.QueryPool.init(gpa, dev, .{
        .query_type = .occlusion,
        .query_count = query_count,
    });
    defer query_pool.deinit(gpa, dev);

    const query_buf_size = query_pool.type.getLayout(dev, query_count, false).size;
    var query_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = query_buf_size,
        .usage = .{ .transfer_dest = true },
    });
    defer query_buf.deinit(gpa, dev);
    var query_mem = blk: {
        const mem_reqs = query_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try query_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &query_mem);
    const query_data = (try query_mem.map(dev, 0, null))[0..query_buf_size];
    @memset(query_data, 255);

    const triangle = struct {
        const format = ngl.Format.rgb32_sfloat;
        const topology = ngl.Cmd.PrimitiveTopology.triangle_list;
        const front_face = .clockwise;

        // Each triangle will cover one half of the render area.
        const data: struct {
            left: [3 * 3]f32 = .{
                0,  -3, 0,
                0,  1,  0,
                -2, 1,  0,
            },
            right: [3 * 3]f32 = .{
                0, -3, 0,
                2, 1,  0,
                0, 1,  0,
            },
        } = .{};
    };

    const vert_buf_size = @sizeOf(@TypeOf(triangle.data));
    var vert_buf = try ngl.Buffer.init(gpa, dev, .{
        .size = vert_buf_size,
        .usage = .{ .vertex_buffer = true },
    });
    defer vert_buf.deinit(gpa, dev);
    var vert_mem = blk: {
        const mem_reqs = vert_buf.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{
                .host_visible = true,
                .host_coherent = true,
            }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try vert_buf.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &vert_mem);
    const vert_data = (try vert_mem.map(dev, 0, null))[0..vert_buf_size];
    @memcpy(vert_data, @as([*]const u8, @ptrCast(&triangle.data))[0..vert_buf_size]);

    const width = 256;
    const height = 192;
    comptime if (width & 1 != 0) unreachable;

    var color_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .color_attachment = true },
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
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer color_view.deinit(gpa, dev);

    var depth_img = try ngl.Image.init(gpa, dev, .{
        .type = .@"2d",
        .format = .d16_unorm,
        .width = width,
        .height = height,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment = true },
        .misc = .{},
        .initial_layout = .unknown,
    });
    defer depth_img.deinit(gpa, dev);
    var depth_mem = blk: {
        const mem_reqs = depth_img.getMemoryRequirements(dev);
        var mem = try dev.alloc(gpa, .{
            .size = mem_reqs.size,
            .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
        });
        errdefer dev.free(gpa, &mem);
        try depth_img.bind(dev, &mem, 0);
        break :blk mem;
    };
    defer dev.free(gpa, &depth_mem);
    var depth_view = try ngl.ImageView.init(gpa, dev, .{
        .image = &depth_img,
        .type = .@"2d",
        .format = .d16_unorm,
        .range = .{
            .aspect_mask = .{ .depth = true },
            .level = 0,
            .levels = 1,
            .layer = 0,
            .layers = 1,
        },
    });
    defer depth_view.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = null,
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var shaders = try ngl.Shader.init(gpa, dev, &.{
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
            if (shd.*) |*s| s.deinit(gpa, dev) else |_| {};
        gpa.free(shaders);
    }

    var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[queue_i] });
    defer cmd_pool.deinit(gpa, dev);
    var cmd_buf = blk: {
        const s = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(s);
        break :blk s[0];
    };

    var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
    cmd.resetQueryPool(&query_pool, 0, query_count);
    cmd.setShaders(&.{.fragment}, &.{if (shaders[1]) |*shd| shd else |err| return err});
    cmd.setViewports(&.{.{
        .x = 0,
        .y = 0,
        .width = width,
        .height = height,
        .znear = 0,
        .zfar = 1,
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
    cmd.setFrontFace(triangle.front_face);
    cmd.setSampleCount(.@"1");
    cmd.setSampleMask(~@as(u64, 0));
    cmd.setDepthBiasEnable(false);
    cmd.setDepthTestEnable(true);
    cmd.setDepthCompareOp(.less);
    cmd.setDepthWriteEnable(true);
    cmd.setStencilTestEnable(false);
    cmd.setColorBlendEnable(0, &.{false});
    cmd.setColorWrite(0, &.{.all});
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{
            .{
                .source_stage_mask = .{},
                .source_access_mask = .{},
                .dest_stage_mask = .{ .color_attachment_output = true },
                .dest_access_mask = .{ .color_attachment_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .color_attachment_optimal,
                .image = &color_img,
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
                .dest_stage_mask = .{
                    .early_fragment_tests = true,
                    .late_fragment_tests = true,
                },
                .dest_access_mask = .{
                    .depth_stencil_attachment_read = true,
                    .depth_stencil_attachment_write = true,
                },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .depth_stencil_attachment_optimal,
                .image = &depth_img,
                .range = .{
                    .aspect_mask = .{ .depth = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
        },
        .by_region = false,
    }});
    cmd.beginRendering(.{
        .colors = &.{.{
            .view = &color_view,
            .layout = .color_attachment_optimal,
            .load_op = .dont_care,
            .store_op = .dont_care,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = .{
            .view = &depth_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = width, .height = height },
        .layers = 1,
        .contents = .@"inline",
    });
    cmd.setShaders(&.{.vertex}, &.{if (shaders[0]) |*shd| shd else |err| return err});
    cmd.setVertexInput(&.{.{
        .binding = 0,
        .stride = 12,
        .step_rate = .vertex,
    }}, &.{.{
        .location = 0,
        .binding = 0,
        .format = triangle.format,
        .offset = 0,
    }});
    cmd.setPrimitiveTopology(triangle.topology);

    // samples_passed == width / 2 * height (or > 0).
    cmd.beginQuery(&query_pool, 0, .{ .precise = precise });
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "left")},
        &.{@sizeOf(@TypeOf(triangle.data.left))},
    );
    cmd.draw(3, 1, 0, 0);
    cmd.endQuery(&query_pool, 0);

    // samples_passed == 0.
    cmd.beginQuery(&query_pool, 1, .{ .precise = precise });
    cmd.draw(3, 1, 0, 0);
    cmd.endQuery(&query_pool, 1);

    // samples_passed == width / 2 * height (or > 0).
    cmd.beginQuery(&query_pool, 2, .{ .precise = precise });
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "right")},
        &.{@sizeOf(@TypeOf(triangle.data.right))},
    );
    cmd.draw(3, 1, 0, 0);
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "left")},
        &.{@sizeOf(@TypeOf(triangle.data.left))},
    );
    cmd.draw(3, 1, 0, 0);
    cmd.endQuery(&query_pool, 2);

    // samples_passed == 0.
    cmd.beginQuery(&query_pool, 3, .{ .precise = precise });
    cmd.draw(3, 1, 0, 0);
    cmd.setVertexBuffers(
        0,
        &.{&vert_buf},
        &.{@offsetOf(@TypeOf(triangle.data), "right")},
        &.{@sizeOf(@TypeOf(triangle.data.right))},
    );
    cmd.draw(3, 1, 0, 0);
    cmd.endQuery(&query_pool, 3);

    cmd.endRendering();
    cmd.copyQueryPoolResults(&query_pool, 0, query_count, &query_buf, 0, .{});
    try cmd.end();

    var fence = try ngl.Fence.init(gpa, dev, .{});
    defer fence.deinit(gpa, dev);
    {
        context().lockQueue(queue_i);
        defer context().unlockQueue(queue_i);

        try dev.queues[queue_i].submit(gpa, dev, &fence, &.{.{
            .commands = &.{.{ .command_buffer = &cmd_buf }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

    var query_resolve = ngl.QueryResolve(.occlusion){};
    defer query_resolve.free(gpa);
    try query_resolve.resolve(gpa, dev, 0, query_count, false, query_data);

    const expected: [query_count]struct {
        op: enum { equal, greater },
        value: u64,
    } = if (precise) .{
        .{ .op = .equal, .value = width / 2 * height },
        .{ .op = .equal, .value = 0 },
        .{ .op = .equal, .value = width / 2 * height },
        .{ .op = .equal, .value = 0 },
    } else .{
        .{ .op = .greater, .value = 0 },
        .{ .op = .equal, .value = 0 },
        .{ .op = .greater, .value = 0 },
        .{ .op = .equal, .value = 0 },
    };

    for (query_resolve.resolved_results, expected) |r, e| {
        const spls_passed = r.samples_passed orelse unreachable;
        switch (e.op) {
            .greater => try testing.expect(spls_passed > e.value),
            .equal => try testing.expectEqual(spls_passed, e.value),
        }
    }
}

// #version 460 core
//
// layout(location = 0) in vec3 position;
//
// void main() {
//     gl_Position = vec4(position, 1.0);
// }
const vert_spv align(4) = [636]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,
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
    0x17, 0x0, 0x4,  0x0, 0x10, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x20, 0x0, 0x4,  0x0, 0x19, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0x19, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
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
