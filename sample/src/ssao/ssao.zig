const std = @import("std");
const assert = std.debug.assert;

const ngl = @import("ngl");
const pfm = ngl.pfm;

const Ctx = @import("Ctx");
const mdata = @import("mdata");
const gmath = @import("gmath");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.detectLeaks())
        @panic("Memory leak");

    try do(gpa.allocator());
}

pub const platform_desc = pfm.Platform.Desc{
    .width = pres_width,
    .height = pres_height,
};

const frame_n = 2;
const material_n = 1;
const teapot_n = 1;
const plane_n = 1;
const draw_n = teapot_n + plane_n;
const pres_width = 1024;
const pres_height = 576;
const rend_width = pres_width / 2;
const rend_height = pres_height / 2;

var ctx: Ctx = undefined;
var dev: *ngl.Device = undefined;
var plat: *pfm.Platform = undefined;

fn do(gpa: std.mem.Allocator) !void {
    ctx = try Ctx.init(gpa);
    defer ctx.deinit(gpa);
    dev = &ctx.device;
    plat = &ctx.platform;

    var col_s4 = try Color(.@"4").init(gpa);
    defer col_s4.deinit(gpa);

    var col_s1 = try Color(.@"1").init(gpa);
    defer col_s1.deinit(gpa);

    var norm_s4 = try Normal(.@"4").init(gpa);
    defer norm_s4.deinit(gpa);

    var norm_s1 = try Normal(.@"1").init(gpa);
    defer norm_s1.deinit(gpa);

    var depth = try Depth.init(gpa);
    defer depth.deinit(gpa);

    var rnd_spl = try RandomSampling.init(gpa);
    defer rnd_spl.deinit(gpa);

    var blur = try Blur(0).init(gpa);
    defer blur.deinit(gpa);

    var blur_2 = try Blur(1).init(gpa);
    defer blur_2.deinit(gpa);

    var tpot = try mdata.loadObj(gpa, "data/model/teapot_double_sided.obj");
    defer tpot.deinit(gpa);
    const plane = &mdata.plane;
    assert(tpot.indices == null);
    assert(!@hasDecl(plane.*, "indices"));

    const tpot_pos_off = 0;
    const tpot_norm_off = tpot_pos_off + tpot.sizeOfPositions();
    const plane_pos_off = tpot_norm_off + tpot.sizeOfNormals();
    const plane_norm_off = plane_pos_off + @sizeOf(plane.Positions);
    const vert_buf_size = plane_norm_off + @sizeOf(plane.Normals);
    var vert_buf = try Buffer(.device).init(gpa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(gpa);

    const cam_off = 0;
    const light_off = (cam_off + Camera.size + 255) & ~@as(u64, 255);
    const matl_off = (light_off + Light.size + 255) & ~@as(u64, 255);
    const model_off = matl_off + material_n * ((Material.size + 255) & ~@as(u64, 255));
    const unif_strd = model_off + draw_n * ((Model.size + 255) & ~@as(u64, 255));
    const unif_buf_size = frame_n * unif_strd;
    var unif_buf = try Buffer(.device).init(gpa, unif_buf_size, .{
        .uniform_buffer = true,
        .transfer_dest = true,
    });
    defer unif_buf.deinit(gpa);

    const vert_cpy_off = 0;
    const unif_cpy_off = (vert_cpy_off + vert_buf_size + 3) & ~@as(u64, 3);
    const rnd_cpy_off = (unif_cpy_off + unif_buf_size + 511) & ~@as(u64, 511);
    const stg_buf_size = rnd_cpy_off + RandomSampling.size;
    var stg_buf = try Buffer(.host).init(gpa, stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit(gpa);

    var desc = try Descriptor.init(gpa, &col_s1, &norm_s1, &depth, &rnd_spl, &blur, &blur_2);
    defer desc.deinit(gpa);

    const ao_params = AoParameters{
        .scale = 1,
        .bias = 0,
        .intensity = 0.75,
    };

    var shd = try Shader.init(gpa, &desc, ao_params);
    defer shd.deinit(gpa);

    var cq = try Command.init(gpa);
    defer cq.deinit(gpa);
    const one_queue = cq.multiqueue == null;

    const v = gmath.m4f.lookAt(.{ 0, -4, -4 }, .{ 0, 0, 0 }, .{ 0, -1, 0 });
    const p = gmath.m4f.perspective(
        std.math.pi / 4.0,
        @as(f32, rend_width) / rend_height,
        0.01,
        100,
    );

    const inv_p = gmath.m4f.invert(p);
    const camera = Camera.init(inv_p);

    const light_ws_pos = .{ 10, -10, -10 };
    const light_es_pos = gmath.m4f.mul(v, light_ws_pos ++ [1]f32{1})[0..3].*;
    const light = Light.init(light_es_pos);

    const matls = [material_n]Material{.{}};

    const models: [draw_n]Model = blk: {
        const xforms = [draw_n][16]f32{
            gmath.m4f.id,
            gmath.m4f.mul(gmath.m4f.t(0, 1, 0), gmath.m4f.s(20, 1, 20)),
        };
        var models: [draw_n]Model = undefined;
        for (&models, xforms) |*model, m| {
            const mv = gmath.m4f.mul(v, m);
            const mvp = gmath.m4f.mul(p, mv);
            const inv = gmath.m3f.invert(gmath.m4f.upperLeft(mv));
            const n = gmath.m3f.to3x4(gmath.m3f.transpose(inv), undefined);
            model.* = Model.init(mvp, mv, n);
        }
        break :blk models;
    };

    const vert_data = stg_buf.data[vert_cpy_off .. vert_cpy_off + vert_buf_size];
    @memcpy(
        vert_data[tpot_pos_off .. tpot_pos_off + tpot.sizeOfPositions()],
        std.mem.sliceAsBytes(tpot.positions.items),
    );
    @memcpy(
        vert_data[tpot_norm_off .. tpot_norm_off + tpot.sizeOfNormals()],
        std.mem.sliceAsBytes(tpot.normals.items),
    );
    @memcpy(
        vert_data[plane_pos_off .. plane_pos_off + @sizeOf(plane.Positions)],
        std.mem.asBytes(&plane.vertices.positions),
    );
    @memcpy(
        vert_data[plane_norm_off .. plane_norm_off + @sizeOf(plane.Normals)],
        std.mem.asBytes(&plane.vertices.normals),
    );

    const rnd_data = stg_buf.data[rnd_cpy_off .. rnd_cpy_off + RandomSampling.size];
    var rnd_source = std.Random.DefaultPrng.init(std.crypto.random.int(u64));
    const rnd_engine = rnd_source.random();
    for (0..rnd_data.len / @sizeOf(f16)) |i| {
        const len = @sizeOf(f16);
        const off = i * len;
        const val: f16 = @floatCast(rnd_engine.float(f32));
        @memcpy(rnd_data[off .. off + len], std.mem.asBytes(&val));
    }

    for (0..frame_n) |frame| {
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd .. unif_cpy_off + strd + unif_strd];

        camera.copy(data[cam_off .. cam_off + Camera.size]);
        light.copy(data[light_off .. light_off + Light.size]);

        for (matls, 0..) |matl, i| {
            const off = matl_off + i * ((Material.size + 255) & ~@as(u64, 255));
            matl.copy(data[off .. off + Material.size]);
        }

        for (models, 0..) |model, i| {
            const off = model_off + i * ((Model.size + 255) & ~@as(u64, 255));
            model.copy(data[off .. off + Model.size]);
        }
    }

    try desc.writeSet0(
        gpa,
        &col_s1,
        &norm_s1,
        &depth,
        &rnd_spl,
        &blur,
        &blur_2,
        &unif_buf.buffer,
        blk: {
            var offs: [frame_n]u64 = undefined;
            for (&offs, 0..) |*off, frame|
                off.* = frame * unif_strd + cam_off;
            break :blk offs;
        },
        blk: {
            var offs: [frame_n]u64 = undefined;
            for (&offs, 0..) |*off, frame|
                off.* = frame * unif_strd + light_off;
            break :blk offs;
        },
    );

    try desc.writeSet1(gpa, &unif_buf.buffer, blk: {
        var offs: [frame_n][material_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, matl| {
                off.* = frame * unif_strd + matl_off +
                    matl * ((Material.size + 255) & ~@as(u64, 255));
            };
        break :blk offs;
    });

    try desc.writeSet2(gpa, &unif_buf.buffer, blk: {
        var offs: [frame_n][draw_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, draw| {
                off.* = frame * unif_strd + model_off +
                    draw * ((Model.size + 255) & ~@as(u64, 255));
            };
        break :blk offs;
    });

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;

    var cmd = try cq.buffers[frame].begin(gpa, dev, .{
        .one_time_submit = true,
        .inheritance = null,
    });

    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf.buffer,
            .dest = &vert_buf.buffer,
            .regions = &.{.{
                .source_offset = vert_cpy_off,
                .dest_offset = 0,
                .size = vert_buf_size,
            }},
        },
        .{
            .source = &stg_buf.buffer,
            .dest = &unif_buf.buffer,
            .regions = &.{.{
                .source_offset = unif_cpy_off,
                .dest_offset = 0,
                .size = unif_buf_size,
            }},
        },
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
            .image = &rnd_spl.image,
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
        .buffer = &stg_buf.buffer,
        .image = &rnd_spl.image,
        .image_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .buffer_offset = rnd_cpy_off,
            .buffer_row_length = RandomSampling.extent,
            .buffer_image_height = RandomSampling.extent,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = RandomSampling.extent,
            .image_height = RandomSampling.extent,
            .image_depth_or_layers = RandomSampling.count,
        }},
    }});

    cmd.barrier(&.{.{
        .image = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{},
            .dest_access_mask = .{},
            .queue_transfer = null,
            .old_layout = .transfer_dest_optimal,
            .new_layout = .shader_read_only_optimal,
            .image = &rnd_spl.image,
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

    try ngl.Fence.reset(gpa, dev, &.{&cq.fences[frame]});

    {
        ctx.lockQueue(cq.queue_index);
        defer ctx.unlockQueue(cq.queue_index);

        try dev.queues[cq.queue_index].submit(gpa, dev, &cq.fences[frame], &.{.{
            .commands = &.{.{ .command_buffer = &cq.buffers[frame] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    while (true) {
        const input = plat.poll();
        if (input.done)
            break;

        const cmd_pool = &cq.pools[frame];
        const cmd_buf = &cq.buffers[frame];
        const sems = .{ &cq.semaphores[2 * frame], &cq.semaphores[2 * frame + 1] };
        const fnc = &cq.fences[frame];

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fnc});
        try ngl.Fence.reset(gpa, dev, &.{fnc});
        const next = try plat.swapchain.nextImage(dev, std.time.ns_per_s, sems[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });

        inline for (.{ .graphics, .compute }) |bp|
            cmd.setDescriptors(bp, &shd.layout, 0, &.{&desc.sets[0][frame]});
        cmd.setRasterizationEnable(true);
        cmd.setPolygonMode(.fill);
        cmd.setCullMode(.none);
        cmd.setSampleMask(~@as(u64, 0));
        cmd.setDepthBiasEnable(false);
        cmd.setStencilTestEnable(false);
        cmd.setColorBlendEnable(0, &.{ false, false });
        cmd.setColorWrite(0, &.{ .all, .all });

        cmd.setVertexInput(&.{
            .{
                .binding = 0,
                .stride = 3 * @sizeOf(f32),
                .step_rate = .vertex,
            },
            .{
                .binding = 1,
                .stride = 3 * @sizeOf(f32),
                .step_rate = .vertex,
            },
        }, &.{
            .{
                .location = 0,
                .binding = 0,
                .format = .rgb32_sfloat,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 1,
                .format = .rgb32_sfloat,
                .offset = 0,
            },
        });
        cmd.setViewports(&.{.{
            .x = 0,
            .y = 0,
            .width = rend_width,
            .height = rend_height,
            .znear = 0,
            .zfar = 1,
        }});
        cmd.setScissorRects(&.{.{
            .x = 0,
            .y = 0,
            .width = rend_width,
            .height = rend_height,
        }});
        cmd.setSampleCount(.@"4");
        cmd.setDepthTestEnable(true);
        cmd.setDepthCompareOp(.less);
        cmd.setDepthWriteEnable(true);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &col_s4.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &col_s1.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &norm_s4.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &norm_s1.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .early_fragment_tests = true },
                    .dest_access_mask = .{
                        .depth_stencil_attachment_read = true,
                        .depth_stencil_attachment_write = true,
                    },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .depth_stencil_attachment_optimal,
                    .image = &depth.image,
                    .range = .{
                        .aspect_mask = .{ .depth = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.beginRendering(.{
            .colors = &.{
                .{
                    .view = &col_s4.view,
                    .layout = .color_attachment_optimal,
                    .load_op = .clear,
                    .store_op = .dont_care,
                    .clear_value = .{ .color_f32 = .{ 0.5, 0.5, 0.5, 1 } },
                    .resolve = .{
                        .view = &col_s1.view,
                        .layout = .color_attachment_optimal,
                        .mode = .average,
                    },
                },
                .{
                    .view = &norm_s4.view,
                    .layout = .color_attachment_optimal,
                    .load_op = .clear,
                    .store_op = .dont_care,
                    .clear_value = .{ .color_f32 = .{ 0, 0, 1, 0 } },
                    .resolve = .{
                        .view = &norm_s1.view,
                        .layout = .color_attachment_optimal,
                        .mode = .average,
                    },
                },
            },
            .depth = .{
                .view = &depth.view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .depth_stencil = .{ 1, undefined } },
                .resolve = null,
            },
            .stencil = blk: {
                assert(!depth.format.getAspectMask().stencil);
                break :blk null;
            },
            .render_area = .{ .width = rend_width, .height = rend_height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.vertex, &shd.fragment });
        comptime assert(material_n == 1);
        cmd.setDescriptors(.graphics, &shd.layout, 1, &.{&desc.sets[1][frame][0]});

        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setVertexBuffers(
            0,
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ tpot_pos_off, tpot_norm_off },
            &.{ tpot.sizeOfPositions(), tpot.sizeOfNormals() },
        );
        cmd.setFrontFace(.counter_clockwise);
        for (0..teapot_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 2, &.{&desc.sets[2][frame][i]});
            cmd.draw(tpot.vertexCount(), 1, 0, 0);
        }

        cmd.setPrimitiveTopology(plane.topology);
        cmd.setVertexBuffers(
            0,
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ plane_pos_off, plane_norm_off },
            &.{ @sizeOf(plane.Positions), @sizeOf(plane.Normals) },
        );
        cmd.setFrontFace(plane.front_face);
        for (teapot_n..draw_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 2, &.{&desc.sets[2][frame][i]});
            cmd.draw(plane.vertex_count, 1, 0, 0);
        }

        cmd.endRendering();

        cmd.setShaders(&.{.vertex}, &.{&shd.screen});
        cmd.setVertexInput(&.{}, &.{});
        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setFrontFace(.clockwise);
        cmd.setSampleCount(.@"1");
        cmd.setDepthTestEnable(false);
        cmd.setDepthWriteEnable(false);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .color_attachment_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .image = &norm_s1.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{
                        .early_fragment_tests = true,
                        .late_fragment_tests = true,
                    },
                    .source_access_mask = .{ .depth_stencil_attachment_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .depth_stencil_attachment_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .image = &depth.image,
                    .range = .{
                        .aspect_mask = .{ .depth = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &blur.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.beginRendering(.{
            .colors = &.{.{
                .view = &blur.view,
                .layout = .color_attachment_optimal,
                .load_op = .dont_care,
                .store_op = .store,
                .clear_value = null,
                .resolve = null,
            }},
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = rend_width, .height = rend_height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{.fragment}, &.{&shd.ssao});
        cmd.draw(3, 1, 0, 0);

        cmd.endRendering();

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .color_attachment_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .image = &blur.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .general,
                    .image = &blur_2.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.setShaders(&.{.compute}, &.{&shd.blur});
        cmd.dispatch(rend_width, rend_height, 1);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .shader_read_only_optimal,
                    .new_layout = .general,
                    .image = &blur.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .shader_read_only_optimal,
                    .image = &blur_2.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.setShaders(&.{.compute}, &.{&shd.blur_2});
        cmd.dispatch(rend_width, rend_height, 1);

        cmd.setViewports(&.{.{
            .x = 0,
            .y = 0,
            .width = pres_width,
            .height = pres_height,
            .znear = 0,
            .zfar = 1,
        }});
        cmd.setScissorRects(&.{.{
            .x = 0,
            .y = 0,
            .width = pres_width,
            .height = pres_height,
        }});

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .color_attachment_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .image = &col_s1.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .shader_read_only_optimal,
                    .image = &blur.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{},
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &plat.images[next],
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.beginRendering(.{
            .colors = &.{.{
                .view = &plat.image_views[next],
                .layout = .color_attachment_optimal,
                .load_op = .dont_care,
                .store_op = .store,
                .clear_value = null,
                .resolve = null,
            }},
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = pres_width, .height = pres_height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{.fragment}, &.{&shd.final});
        cmd.draw(3, 1, 0, 0);

        cmd.endRendering();

        cmd.barrier(&.{.{
            .image = &.{.{
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .color_attachment_output = true },
                .dest_access_mask = .{},
                .queue_transfer = if (one_queue) null else .{
                    .source = &dev.queues[cq.queue_index],
                    .dest = &dev.queues[plat.queue_index],
                },
                .old_layout = .color_attachment_optimal,
                .new_layout = .present_source,
                .image = &plat.images[next],
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

        {
            ctx.lockQueue(cq.queue_index);
            defer ctx.unlockQueue(cq.queue_index);

            try dev.queues[cq.queue_index].submit(gpa, dev, fnc, &.{.{
                .commands = &.{.{ .command_buffer = cmd_buf }},
                .wait = &.{.{
                    .semaphore = sems[0],
                    .stage_mask = .{ .color_attachment_output = true },
                }},
                .signal = &.{.{
                    .semaphore = sems[1],
                    .stage_mask = .{ .color_attachment_output = true },
                }},
            }});
        }

        const pres: struct {
            sem: *ngl.Semaphore,
            queue: *ngl.Queue,
        } = blk: {
            if (one_queue)
                break :blk .{
                    .sem = sems[1],
                    .queue = &dev.queues[cq.queue_index],
                };

            const mq = &cq.multiqueue.?;

            try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&mq.fences[frame]});
            try ngl.Fence.reset(gpa, dev, &.{&mq.fences[frame]});

            try mq.pools[frame].reset(dev, .keep);
            cmd = try mq.buffers[frame].begin(gpa, dev, .{
                .one_time_submit = true,
                .inheritance = null,
            });

            cmd.barrier(&.{.{
                .image = &.{.{
                    .source_stage_mask = .{},
                    .source_access_mask = .{},
                    .dest_stage_mask = .{},
                    .dest_access_mask = .{},
                    .queue_transfer = .{
                        .source = &dev.queues[cq.queue_index],
                        .dest = &dev.queues[plat.queue_index],
                    },
                    .old_layout = .color_attachment_optimal,
                    .new_layout = .present_source,
                    .image = &plat.images[next],
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

            ctx.lockQueue(plat.queue_index);
            defer ctx.unlockQueue(plat.queue_index);

            try dev.queues[plat.queue_index].submit(gpa, dev, &mq.fences[frame], &.{.{
                .commands = &.{.{ .command_buffer = &mq.buffers[frame] }},
                .wait = &.{.{
                    .semaphore = sems[1],
                    .stage_mask = .{ .color_attachment_output = true },
                }},
                .signal = &.{.{
                    .semaphore = &mq.semaphores[frame],
                    .stage_mask = .{ .color_attachment_output = true },
                }},
            }});

            break :blk .{
                .sem = &mq.semaphores[frame],
                .queue = &dev.queues[plat.queue_index],
            };
        };

        try pres.queue.present(gpa, dev, &.{pres.sem}, &.{.{
            .swapchain = &plat.swapchain,
            .image_index = next,
        }});

        frame = (frame + 1) % frame_n;
    }

    try dev.wait();
}

fn Color(comptime msr: enum { @"4", @"1" }) type {
    return struct {
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,
        sampler: switch (msr) {
            .@"4" => void,
            .@"1" => ngl.Sampler,
        },

        const format = ngl.Format.rgba16_sfloat;
        const samples = @field(ngl.SampleCount, @tagName(msr));
        const set_index = 0;
        const binding = 0;

        fn init(gpa: std.mem.Allocator) ngl.Error!@This() {
            var img = try ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = format,
                .width = rend_width,
                .height = rend_height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = samples,
                .tiling = .optimal,
                .usage = .{
                    .sampled_image = msr == .@"1",
                    .color_attachment = true,
                    .transient_attachment = msr == .@"4",
                },
                .misc = .{},
            });
            errdefer img.deinit(gpa, dev);

            var mem = blk: {
                const reqs = img.getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = reqs.size,
                    .type_index = reqs.findType(dev.*, .{
                        .device_local = true,
                        .lazily_allocated = msr == .@"4",
                    }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try img.bind(dev, &mem, 0);
                break :blk mem;
            };
            errdefer dev.free(gpa, &mem);

            var view = try ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            });
            errdefer view.deinit(gpa, dev);

            const splr = switch (msr) {
                .@"4" => {},
                .@"1" => try ngl.Sampler.init(gpa, dev, .{
                    .normalized_coordinates = true,
                    .u_address = .clamp_to_edge,
                    .v_address = .clamp_to_edge,
                    .w_address = .clamp_to_edge,
                    .border_color = null,
                    .mag = .linear,
                    .min = .linear,
                    .mipmap = .nearest,
                    .min_lod = 0,
                    .max_lod = null,
                    .max_anisotropy = null,
                    .compare = null,
                }),
            };

            return .{
                .image = img,
                .memory = mem,
                .view = view,
                .sampler = splr,
            };
        }

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.view.deinit(gpa, dev);
            self.image.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
            switch (msr) {
                .@"4" => {},
                .@"1" => self.sampler.deinit(gpa, dev),
            }
        }
    };
}

fn Normal(comptime msr: enum { @"4", @"1" }) type {
    return struct {
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,
        sampler: switch (msr) {
            .@"4" => void,
            .@"1" => ngl.Sampler,
        },

        const format = ngl.Format.rgba16_sfloat;
        const samples = @field(ngl.SampleCount, @tagName(msr));
        const set_index = 0;
        const binding = 1;

        fn init(gpa: std.mem.Allocator) ngl.Error!@This() {
            var img = try ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = format,
                .width = rend_width,
                .height = rend_height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = samples,
                .tiling = .optimal,
                .usage = .{
                    .sampled_image = msr == .@"1",
                    .color_attachment = true,
                    .transient_attachment = msr == .@"4",
                },
                .misc = .{},
            });
            errdefer img.deinit(gpa, dev);

            var mem = blk: {
                const reqs = img.getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = reqs.size,
                    .type_index = reqs.findType(dev.*, .{
                        .device_local = true,
                        .lazily_allocated = msr == .@"4",
                    }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try img.bind(dev, &mem, 0);
                break :blk mem;
            };
            errdefer dev.free(gpa, &mem);

            var view = try ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            });
            errdefer view.deinit(gpa, dev);

            const splr = switch (msr) {
                .@"4" => {},
                .@"1" => try ngl.Sampler.init(gpa, dev, .{
                    .normalized_coordinates = true,
                    .u_address = .clamp_to_edge,
                    .v_address = .clamp_to_edge,
                    .w_address = .clamp_to_edge,
                    .border_color = null,
                    .mag = .linear,
                    .min = .linear,
                    .mipmap = .nearest,
                    .min_lod = 0,
                    .max_lod = null,
                    .max_anisotropy = null,
                    .compare = null,
                }),
            };

            return .{
                .image = img,
                .memory = mem,
                .view = view,
                .sampler = splr,
            };
        }

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.view.deinit(gpa, dev);
            self.image.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
            switch (msr) {
                .@"4" => {},
                .@"1" => self.sampler.deinit(gpa, dev),
            }
        }
    };
}

const Depth = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const samples = ngl.SampleCount.@"4";
    const set_index = 0;
    const binding = 2;

    fn init(gpa: std.mem.Allocator) ngl.Error!Depth {
        const fmt, const filt = for ([_]ngl.Format{
            .d32_sfloat,
            .x8_d24_unorm,
            .d16_unorm,
        }) |fmt| {
            const opt = fmt.getFeatures(dev).optimal_tiling;
            if (opt.depth_stencil_attachment)
                break .{
                    fmt,
                    @as(
                        ngl.Sampler.Filter,
                        if (opt.sampled_image_filter_linear) .linear else .nearest,
                    ),
                };
        } else unreachable;

        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = rend_width,
            .height = rend_height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .depth_stencil_attachment = true,
            },
            .misc = .{},
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
            .type = .@"2d",
            .format = fmt,
            .range = .{
                .aspect_mask = .{ .depth = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });
        errdefer view.deinit(gpa, dev);

        const splr = try ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .clamp_to_edge,
            .v_address = .clamp_to_edge,
            .w_address = .clamp_to_edge,
            .border_color = null,
            .mag = filt,
            .min = filt,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        });

        return .{
            .format = fmt,
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *Depth, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const RandomSampling = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rg16_sfloat;
    const extent = 128;
    const count: i32 = 1 * 1;
    const size = @sizeOf(f16) * 2 * count * extent * extent;
    const set_index = 0;
    const binding = 3;

    fn init(gpa: std.mem.Allocator) ngl.Error!RandomSampling {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = if (count > 1) .@"3d" else .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = count,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .transfer_dest = true,
            },
            .misc = .{},
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
            .type = if (count > 1) .@"3d" else .@"2d",
            .format = format,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });
        errdefer view.deinit(gpa, dev);

        const splr = try ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .repeat,
            .v_address = .repeat,
            .w_address = .repeat,
            .border_color = null,
            .mag = .linear,
            .min = .linear,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        });

        return .{
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *RandomSampling, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

fn Blur(comptime index: u1) type {
    return struct {
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,
        sampler: ngl.Sampler,

        const format = ngl.Format.rgba8_unorm;
        const combined = struct {
            const set_index = 0;
            const binding = switch (index) {
                0 => 4,
                1 => 6,
            };
        };
        const storage = struct {
            const set_index = 0;
            const binding = switch (index) {
                0 => 7,
                1 => 5,
            };
        };

        fn init(gpa: std.mem.Allocator) ngl.Error!@This() {
            var img = try ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = format,
                .width = rend_width,
                .height = rend_height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = .@"1",
                .tiling = .optimal,
                .usage = .{
                    .sampled_image = true,
                    .storage_image = true,
                    .color_attachment = index == 0,
                },
                .misc = .{},
            });
            errdefer img.deinit(gpa, dev);

            var mem = blk: {
                const reqs = img.getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = reqs.size,
                    .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try img.bind(dev, &mem, 0);
                break :blk mem;
            };
            errdefer dev.free(gpa, &mem);

            var view = try ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            });
            errdefer view.deinit(gpa, dev);

            const splr = try ngl.Sampler.init(gpa, dev, .{
                .normalized_coordinates = true,
                .u_address = .clamp_to_edge,
                .v_address = .clamp_to_edge,
                .w_address = .clamp_to_edge,
                .border_color = null,
                .mag = .linear,
                .min = .linear,
                .mipmap = .nearest,
                .min_lod = 0,
                .max_lod = null,
                .max_anisotropy = null,
                .compare = null,
            });

            return .{
                .image = img,
                .memory = mem,
                .view = view,
                .sampler = splr,
            };
        }

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.view.deinit(gpa, dev);
            self.image.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
            self.sampler.deinit(gpa, dev);
        }
    };
}

fn Buffer(comptime kind: enum { host, device }) type {
    return struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,
        data: switch (kind) {
            .host => []u8,
            .device => void,
        },

        fn init(gpa: std.mem.Allocator, size: u64, usage: ngl.Buffer.Usage) ngl.Error!@This() {
            var buf = try ngl.Buffer.init(gpa, dev, .{
                .size = size,
                .usage = usage,
            });
            errdefer buf.deinit(gpa, dev);

            const reqs = buf.getMemoryRequirements(dev);
            const props: ngl.Memory.Properties = switch (kind) {
                .host => .{
                    .host_visible = true,
                    .host_coherent = true,
                },
                .device => .{ .device_local = true },
            };
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, props, null).?,
            });
            errdefer dev.free(gpa, &mem);

            try buf.bind(dev, &mem, 0);
            const data = switch (kind) {
                .host => try mem.map(dev, 0, size),
                .device => {},
            };

            return .{
                .buffer = buf,
                .memory = mem,
                .data = data,
            };
        }

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.buffer.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
        }
    };
}

const Descriptor = struct {
    set_layouts: [3]ngl.DescriptorSetLayout,
    pool: ngl.DescriptorPool,
    sets: struct {
        [frame_n]ngl.DescriptorSet,
        [frame_n][material_n]ngl.DescriptorSet,
        [frame_n][draw_n]ngl.DescriptorSet,
    },

    fn init(
        gpa: std.mem.Allocator,
        color: *Color(.@"1"),
        normal: *Normal(.@"1"),
        depth: *Depth,
        random_sampling: *RandomSampling,
        blur: *Blur(0),
        blur_2: *Blur(1),
    ) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = Color(.@"1").binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&color.sampler},
                },
                .{
                    .binding = Normal(.@"1").binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&normal.sampler},
                },
                .{
                    .binding = Depth.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&depth.sampler},
                },
                .{
                    .binding = RandomSampling.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&random_sampling.sampler},
                },
                .{
                    .binding = Blur(0).combined.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&blur.sampler},
                },
                .{
                    .binding = Blur(1).combined.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{&blur_2.sampler},
                },
                .{
                    .binding = Blur(0).storage.binding,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = Blur(1).storage.binding,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = Camera.binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = Light.binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);

        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{.{
                .binding = Material.binding,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .fragment = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var set_layt_3 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{.{
                .binding = Model.binding,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .vertex = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_3.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = frame_n * (1 + material_n + draw_n),
            .pool_size = .{
                .combined_image_sampler = frame_n * 6,
                .sampled_image = frame_n * 2,
                .uniform_buffer = frame_n * (2 + material_n + draw_n),
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = try pool.alloc(gpa, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** (frame_n * material_n) ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_3} ** (frame_n * draw_n),
        });
        defer gpa.free(sets);

        return .{
            .set_layouts = .{ set_layt, set_layt_2, set_layt_3 },
            .pool = pool,
            .sets = .{
                sets[0..frame_n].*,
                blk: {
                    var dest: [frame_n][material_n]ngl.DescriptorSet = undefined;
                    var source = sets[frame_n..];
                    for (&dest) |*d| {
                        d.* = source[0..material_n].*;
                        source = source[material_n..];
                    }
                    break :blk dest;
                },
                blk: {
                    var dest: [frame_n][draw_n]ngl.DescriptorSet = undefined;
                    var source = sets[frame_n * (1 + material_n) ..];
                    for (&dest) |*d| {
                        d.* = source[0..draw_n].*;
                        source = source[draw_n..];
                    }
                    break :blk dest;
                },
            },
        };
    }

    fn writeSet0(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        color: *Color(.@"1"),
        normal: *Normal(.@"1"),
        depth: *Depth,
        random_sampling: *RandomSampling,
        blur: *Blur(0),
        blur_2: *Blur(1),
        uniform_buffer: *ngl.Buffer,
        camera_offsets: [frame_n]u64,
        light_offsets: [frame_n]u64,
    ) ngl.Error!void {
        var writes: [10 * frame_n]ngl.DescriptorSet.Write = undefined;
        const comb_col = writes[0..frame_n];
        const comb_norm = writes[frame_n .. 2 * frame_n];
        const comb_dep = writes[2 * frame_n .. 3 * frame_n];
        const comb_rnd = writes[3 * frame_n .. 4 * frame_n];
        const comb_blur = writes[4 * frame_n .. 5 * frame_n];
        const comb_blur_2 = writes[5 * frame_n .. 6 * frame_n];
        const stor_blur = writes[6 * frame_n .. 7 * frame_n];
        const stor_blur_2 = writes[7 * frame_n .. 8 * frame_n];
        const unif_cam = writes[8 * frame_n .. 9 * frame_n];
        const unif_light = writes[9 * frame_n .. 10 * frame_n];

        const Isw = ngl.DescriptorSet.Write.ImageSamplerWrite;
        var isw_arr: [6 * frame_n]Isw = undefined;
        var isw: []Isw = &isw_arr;

        const Iw = ngl.DescriptorSet.Write.ImageWrite;
        var iw_arr: [2 * frame_n]Iw = undefined;
        var iw: []Iw = &iw_arr;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [2 * frame_n]Bw = undefined;
        var bw: []Bw = &bw_arr;

        inline for (
            .{
                Color(.@"1"),
                Normal(.@"1"),
                Depth,
                RandomSampling,
                Blur(0).combined,
                Blur(1).combined,
            },
            .{
                &color.view,
                &normal.view,
                &depth.view,
                &random_sampling.view,
                &blur.view,
                &blur_2.view,
            },
            .{
                comb_col,
                comb_norm,
                comb_dep,
                comb_rnd,
                comb_blur,
                comb_blur_2,
            },
        ) |T, view, combs|
            for (combs, &self.sets[0]) |*comb, *set| {
                isw[0] = .{
                    .view = view,
                    .layout = .shader_read_only_optimal,
                    .sampler = null,
                };
                comb.* = .{
                    .descriptor_set = set,
                    .binding = T.binding,
                    .element = 0,
                    .contents = .{ .combined_image_sampler = isw[0..1] },
                };
                isw = isw[1..];
            };

        inline for (
            .{ Blur(0).storage, Blur(1).storage },
            .{ &blur.view, &blur_2.view },
            .{ stor_blur, stor_blur_2 },
        ) |T, view, stors|
            for (stors, &self.sets[0]) |*stor, *set| {
                iw[0] = .{
                    .view = view,
                    .layout = .general,
                };
                stor.* = .{
                    .descriptor_set = set,
                    .binding = T.binding,
                    .element = 0,
                    .contents = .{ .storage_image = iw[0..1] },
                };
                iw = iw[1..];
            };

        inline for (
            .{ Camera, Light },
            .{ &camera_offsets, &light_offsets },
            .{ unif_cam, unif_light },
        ) |T, offs, unifs|
            for (unifs, &self.sets[0], offs) |*unif, *set, off| {
                bw[0] = .{
                    .buffer = uniform_buffer,
                    .offset = off,
                    .range = T.size,
                };
                unif.* = .{
                    .descriptor_set = set,
                    .binding = T.binding,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };
                bw = bw[1..];
            };

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn writeSet1(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        material_offsets: [frame_n][material_n]u64,
    ) ngl.Error!void {
        try self.writeSet1Or2(Material, gpa, uniform_buffer, material_offsets);
    }

    fn writeSet2(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        model_offsets: [frame_n][draw_n]u64,
    ) ngl.Error!void {
        try self.writeSet1Or2(Model, gpa, uniform_buffer, model_offsets);
    }

    fn writeSet1Or2(
        self: *Descriptor,
        comptime T: type,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        offsets: switch (T) {
            Material => [frame_n][material_n]u64,
            Model => [frame_n][draw_n]u64,
            else => unreachable,
        },
    ) ngl.Error!void {
        const n = switch (T) {
            Material => frame_n * material_n,
            Model => frame_n * draw_n,
            else => unreachable,
        };

        var writes: [n]ngl.DescriptorSet.Write = undefined;
        var w: []ngl.DescriptorSet.Write = &writes;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [n]Bw = undefined;
        var bw: []Bw = &bw_arr;

        for (&self.sets[T.set_index], offsets) |*sets, offs|
            for (sets, offs) |*set, off| {
                bw[0] = .{
                    .buffer = uniform_buffer,
                    .offset = off,
                    .range = T.size,
                };
                w[0] = .{
                    .descriptor_set = set,
                    .binding = T.binding,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };
                bw = bw[1..];
                w = w[1..];
            };

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn deinit(self: *Descriptor, gpa: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Shader = struct {
    vertex: ngl.Shader,
    fragment: ngl.Shader,
    screen: ngl.Shader,
    ssao: ngl.Shader,
    blur: ngl.Shader,
    blur_2: ngl.Shader,
    final: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(
        gpa: std.mem.Allocator,
        descriptor: *Descriptor,
        ao_parameters: AoParameters,
    ) ngl.Error!Shader {
        const dapi = ctx.gpu.getDriverApi();

        const vert_code_spv align(4) = @embedFile("shader/vert.spv").*;
        const vert_code = switch (dapi) {
            .vulkan => &vert_code_spv,
        };

        const frag_code_spv align(4) = @embedFile("shader/frag.spv").*;
        const frag_code = switch (dapi) {
            .vulkan => &frag_code_spv,
        };

        const scrn_code_spv align(4) = @embedFile("shader/screen.vert.spv").*;
        const scrn_code = switch (dapi) {
            .vulkan => &scrn_code_spv,
        };

        const ssao_code_spv align(4) = @embedFile("shader/ssao.frag.spv").*;
        const ssao_code = switch (dapi) {
            .vulkan => &ssao_code_spv,
        };

        const blur_code_spv align(4) = @embedFile("shader/blur.comp.spv").*;
        const blur_code = switch (dapi) {
            .vulkan => &blur_code_spv,
        };

        const blur_2_code_spv align(4) = @embedFile("shader/blur_2.comp.spv").*;
        const blur_2_code = switch (dapi) {
            .vulkan => &blur_2_code_spv,
        };

        const final_code_spv align(4) = @embedFile("shader/final.frag.spv").*;
        const final_code = switch (dapi) {
            .vulkan => &final_code_spv,
        };

        const set_layts = &.{
            &descriptor.set_layouts[0],
            &descriptor.set_layouts[1],
            &descriptor.set_layouts[2],
        };

        const shaders = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .vertex,
                .next = .{ .fragment = true },
                .code = vert_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
            .{
                .type = .fragment,
                .next = .{},
                .code = frag_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
        });
        defer gpa.free(shaders);
        errdefer for (shaders) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const scrn_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = scrn_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = null,
            .link = false,
        }});
        defer gpa.free(scrn_shd);
        errdefer if (scrn_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        const ssao_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .fragment,
            .next = .{},
            .code = ssao_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = ao_parameters.specialization(),
            .link = false,
        }});
        defer gpa.free(ssao_shd);
        errdefer if (ssao_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        const blur_shds = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .compute,
                .next = .{},
                .code = blur_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = false,
            },
            .{
                .type = .compute,
                .next = .{},
                .code = blur_2_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = false,
            },
        });
        defer gpa.free(blur_shds);
        errdefer for (blur_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const final_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .fragment,
            .next = .{},
            .code = final_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = null,
            .link = false,
        }});
        defer gpa.free(final_shd);
        errdefer if (final_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        var layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(gpa, dev);

        return .{
            .vertex = try shaders[0],
            .fragment = try shaders[1],
            .screen = try scrn_shd[0],
            .ssao = try ssao_shd[0],
            .blur = try blur_shds[0],
            .blur_2 = try blur_shds[1],
            .final = try final_shd[0],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, gpa: std.mem.Allocator) void {
        for ([_]*ngl.Shader{
            &self.vertex,
            &self.fragment,
            &self.screen,
            &self.ssao,
            &self.blur,
            &self.blur_2,
            &self.final,
        }) |shd|
            shd.deinit(gpa, dev);

        self.layout.deinit(gpa, dev);
    }
};

const Command = struct {
    queue_index: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [2 * frame_n]ngl.Semaphore,
    fences: [frame_n]ngl.Fence,
    multiqueue: ?struct {
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        semaphores: [frame_n]ngl.Semaphore,
        fences: [frame_n]ngl.Fence,
    },

    fn init(gpa: std.mem.Allocator) ngl.Error!Command {
        const pres = plat.queue_index;
        const rend = blk: {
            const capab = dev.queues[pres].capabilities;
            break :blk if (capab.graphics and capab.compute)
                pres
            else
                dev.findQueue(.{
                    .graphics = true,
                    .compute = true,
                }, null) orelse return ngl.Error.NotSupported;
        };

        const doInit = struct {
            fn doInit(gpa_: std.mem.Allocator, queue: *ngl.Queue, dest: anytype) ngl.Error!void {
                for (&dest.pools, 0..) |*pool, i|
                    pool.* = ngl.CommandPool.init(gpa_, dev, .{ .queue = queue }) catch |err| {
                        for (0..i) |j|
                            dest.pools[j].deinit(gpa_, dev);
                        return err;
                    };
                errdefer for (&dest.pools) |*pool|
                    pool.deinit(gpa_, dev);

                for (&dest.buffers, &dest.pools) |*buf, *pool| {
                    const s = try pool.alloc(gpa_, dev, .{
                        .level = .primary,
                        .count = 1,
                    });
                    buf.* = s[0];
                    gpa_.free(s);
                }

                for (&dest.semaphores, 0..) |*sem, i|
                    sem.* = ngl.Semaphore.init(gpa_, dev, .{}) catch |err| {
                        for (0..i) |j|
                            dest.semaphores[j].deinit(gpa_, dev);
                        return err;
                    };
                errdefer for (&dest.semaphores) |*sem|
                    sem.deinit(gpa_, dev);

                for (&dest.fences, 0..) |*fnc, i|
                    fnc.* = ngl.Fence.init(gpa_, dev, .{ .status = .signaled }) catch |err| {
                        for (0..i) |j|
                            dest.fences[j].deinit(gpa_, dev);
                        return err;
                    };
            }
        }.doInit;

        var self: Command = undefined;
        self.queue_index = rend;
        try doInit(gpa, &dev.queues[rend], &self);
        if (pres == rend) {
            self.multiqueue = null;
        } else {
            self.multiqueue = .{
                .pools = undefined,
                .buffers = undefined,
                .semaphores = undefined,
                .fences = undefined,
            };
            doInit(gpa, &dev.queues[pres], &self.multiqueue.?) catch |err| {
                for (&self.pools) |*pool|
                    pool.deinit(gpa, dev);
                for (&self.semaphores) |*sem|
                    sem.deinit(gpa, dev);
                for (&self.fences) |*fnc|
                    fnc.deinit(gpa, dev);
                return err;
            };
        }
        return self;
    }

    fn deinit(self: *Command, gpa: std.mem.Allocator) void {
        const doDeinit = struct {
            fn doDeinit(gpa_: std.mem.Allocator, dest: anytype) void {
                for (&dest.pools) |*pool|
                    pool.deinit(gpa_, dev);
                for (&dest.semaphores) |*sem|
                    sem.deinit(gpa_, dev);
                for (&dest.fences) |*fnc|
                    fnc.deinit(gpa_, dev);
            }
        }.doDeinit;

        doDeinit(gpa, self);
        if (self.multiqueue) |*x|
            doDeinit(gpa, x);
    }
};

const AoParameters = packed struct {
    scale: f32,
    bias: f32,
    intensity: f32,

    const scale_id = 0;
    const bias_id = 1;
    const intensity_id = 2;

    // NOTE: Self-reference.
    fn specialization(self: *const AoParameters) ngl.Shader.Specialization {
        return .{
            .constants = &.{
                .{
                    .id = scale_id,
                    .offset = @offsetOf(AoParameters, "scale"),
                    .size = @sizeOf(@TypeOf(self.scale)),
                },
                .{
                    .id = bias_id,
                    .offset = @offsetOf(AoParameters, "bias"),
                    .size = @sizeOf(@TypeOf(self.bias)),
                },
                .{
                    .id = intensity_id,
                    .offset = @offsetOf(AoParameters, "intensity"),
                    .size = @sizeOf(@TypeOf(self.intensity)),
                },
            },
            .data = std.mem.asBytes(self),
        };
    }
};

const Camera = struct {
    inv_p: [16]f32,

    const size = @sizeOf(@typeInfo(Camera).Struct.fields[0].type);
    const set_index = 0;
    const binding = 8;

    fn init(inverse_p: [16]f32) Camera {
        var self: Camera = undefined;
        @memcpy(self.inv_p[0..16], &inverse_p);
        return self;
    }

    fn copy(self: Camera, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.inv_p));
    }
};

const Light = packed struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    _pos_pad: f32 = 0,
    col_r: f32 = 1,
    col_g: f32 = 1,
    col_b: f32 = 1,
    intensity: f32 = 100,

    const size = @sizeOf(Light);
    const set_index = 0;
    const binding = 9;

    fn init(position: [3]f32) Light {
        return Light{
            .pos_x = position[0],
            .pos_y = position[1],
            .pos_z = position[2],
        };
    }

    fn copy(self: Light, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Material = packed struct {
    col_r: f32 = 0.5803921568627451,
    col_g: f32 = 0.4901960784313725,
    col_b: f32 = 0.4588235294117647,
    col_a: f32 = 1,
    metallic: f32 = 0,
    smoothness: f32 = 0.75,
    reflectance: f32 = 0.5,

    const size = @sizeOf(Material);
    const set_index = 1;
    const binding = 0;

    fn copy(self: Material, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Model = struct {
    mvp_mv_n: [16 + 16 + 12]f32,

    const size = @sizeOf(@typeInfo(Model).Struct.fields[0].type);
    const set_index = 2;
    const binding = 0;

    fn init(mvp: [16]f32, mv: [16]f32, n: [12]f32) Model {
        var self: Model = undefined;
        @memcpy(self.mvp_mv_n[0..16], &mvp);
        @memcpy(self.mvp_mv_n[16..32], &mv);
        @memcpy(self.mvp_mv_n[32..44], &n);
        return self;
    }

    fn copy(self: Model, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.mvp_mv_n));
    }
};
