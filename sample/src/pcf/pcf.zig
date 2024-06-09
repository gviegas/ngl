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
    .width = width,
    .height = height,
};

const frame_n = 2;
const lattice_n = 1;
const plane_n = 1;
const draw_n = lattice_n + plane_n;
const material_n = draw_n;
comptime {
    assert(material_n == draw_n);
}
const width = 1024;
const height = 576;

var ctx: Ctx = undefined;
var dev: *ngl.Device = undefined;
var plat: *pfm.Platform = undefined;

fn do(gpa: std.mem.Allocator) !void {
    ctx = try Ctx.init(gpa);
    defer ctx.deinit(gpa);
    dev = &ctx.device;
    plat = &ctx.platform;

    var color = try Color.init(gpa);
    defer color.deinit(gpa);

    var depth = try Depth.init(gpa);
    defer depth.deinit(gpa);

    var shdw_map = try ShadowMap.init(gpa);
    defer shdw_map.deinit(gpa);

    var rnd_spl = try RandomSampling.init(gpa);
    defer rnd_spl.deinit(gpa);

    var desc = try Descriptor.init(gpa, &shdw_map, &rnd_spl);
    defer desc.deinit(gpa);

    var shd = try Shader.init(gpa, &desc);
    defer shd.deinit(gpa);

    var cq = try Command.init(gpa);
    defer cq.deinit(gpa);
    const one_queue = cq.multiqueue == null;

    var latt = try mdata.loadObj(gpa, "data/model/lattice.obj");
    defer latt.deinit(gpa);
    const plane = &mdata.plane;
    assert(latt.indices == null);
    comptime assert(!@hasDecl(plane.*, "indices"));

    const latt_pos_off = 0;
    const latt_norm_off = latt_pos_off + latt.sizeOfPositions();
    const plane_pos_off = latt_norm_off + latt.sizeOfNormals();
    const plane_norm_off = plane_pos_off + @sizeOf(plane.Positions);
    const latt_size = plane_pos_off;
    const plane_size = plane_norm_off + @sizeOf(plane.Normals) - plane_pos_off;
    const vert_buf_size = latt_size + plane_size;
    var vert_buf = try Buffer(.device).init(gpa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(gpa);

    const light_off = 0;
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
    const unif_cpy_off = (vert_cpy_off + vert_buf_size + 255) & ~@as(u64, 255);
    const rnd_cpy_off = (unif_cpy_off + unif_buf_size + 255) & ~@as(u64, 255);
    const stg_buf_size = rnd_cpy_off + RandomSampling.size;
    var stg_buf = try Buffer(.host).init(gpa, stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit(gpa);

    const v = gmath.lookAt(.{ 0, -4, -4 }, .{ 0, 0, 0 }, .{ 0, -1, 0 });
    const p = gmath.perspective(std.math.pi / 4.0, @as(f32, width) / height, 0.01, 100);

    const light_world_pos = .{ -12, -10, 3 };
    const light_view_pos = gmath.mulMV(4, v, light_world_pos ++ [1]f32{1})[0..3].*;
    const light_col = .{ 1, 1, 1 };
    const intensity = 100;
    const light = Light.init(light_view_pos, light_col, intensity);

    const shdw_v = gmath.lookAt(light_world_pos, .{ 0, 0, 0 }, .{ 0, -1, 0 });
    const shdw_p = gmath.frustum(-0.25, 0.25, -0.25, 0.25, 1, 100);
    const shdw_vp = gmath.mulM(4, shdw_p, shdw_v);
    const vps = gmath.mulM(4, .{
        0.5, 0,   0, 0,
        0,   0.5, 0, 0,
        0,   0,   1, 0,
        0.5, 0.5, 0, 1,
    }, shdw_vp);
    const draws = blk: {
        const xforms = [draw_n][16]f32{
            gmath.identity(4),
            .{
                20, 0, 0,  0,
                0,  1, 0,  0,
                0,  0, 20, 0,
                0,  1, 0,  1,
            },
        };
        const matls = [draw_n]Material{
            Material.init(.{ 0.9843137, 0.8470588, 0.7372549, 1 }, 1, 0.6666667, 0),
            Material.init(.{ 0.7529412, 0.7490196, 0.7333333, 1 }, 0, 0.4, 0.5),
        };
        var draws: [draw_n]Draw = undefined;
        for (&draws, xforms, matls) |*draw, m, matl| {
            const shdw_mvp = gmath.mulM(4, shdw_vp, m);
            const s = gmath.mulM(4, vps, m);
            const mv = gmath.mulM(4, v, m);
            const inv = gmath.invert3(gmath.upperLeft(4, mv));
            const n = .{
                inv[0], inv[3], inv[6], undefined,
                inv[1], inv[4], inv[7], undefined,
                inv[2], inv[5], inv[8], undefined,
            };
            const mvp = gmath.mulM(4, p, mv);
            draw.* = .{
                .model = Model.init(shdw_mvp, s, mvp, mv, n),
                .material = matl,
            };
        }
        break :blk draws;
    };

    const vert_data = stg_buf.data[vert_cpy_off .. vert_cpy_off + vert_buf_size];
    @memcpy(
        vert_data[latt_pos_off .. latt_pos_off + latt.sizeOfPositions()],
        std.mem.sliceAsBytes(latt.positions.items),
    );
    @memcpy(
        vert_data[latt_norm_off .. latt_norm_off + latt.sizeOfNormals()],
        std.mem.sliceAsBytes(latt.normals.items),
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
        const ub = &unif_buf.buffer;
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd .. unif_cpy_off + strd + unif_strd];

        try desc.writeIs(ShadowMap, gpa, frame, &shdw_map.view, .shader_read_only_optimal, null);

        try desc.writeIs(
            RandomSampling,
            gpa,
            frame,
            &rnd_spl.view,
            .shader_read_only_optimal,
            null,
        );

        try desc.writeUb(Light, gpa, frame, null, ub, strd + light_off);
        light.copy(data[light_off .. light_off + Light.size]);

        for (draws, 0..) |draw, i| {
            const off = matl_off + i * ((Material.size + 255) & ~@as(u64, 255));
            try desc.writeUb(Material, gpa, frame, i, ub, strd + off);
            draw.material.copy(data[off .. off + Material.size]);

            const off_2 = model_off + i * ((Model.size + 255) & ~@as(u64, 255));
            try desc.writeUb(Model, gpa, frame, i, ub, strd + off_2);
            draw.model.copy(data[off_2 .. off_2 + Model.size]);
        }
    }

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

        cmd.setDescriptors(.graphics, &shd.layout, 0, &.{&desc.sets[0][frame]});
        cmd.setRasterizationEnable(true);
        cmd.setPolygonMode(.fill);
        cmd.setSampleMask(~@as(u64, 0));
        cmd.setDepthTestEnable(true);
        cmd.setDepthCompareOp(.less);
        cmd.setDepthWriteEnable(true);
        cmd.setStencilTestEnable(false);
        cmd.setColorBlendEnable(0, &.{false});
        cmd.setColorWrite(0, &.{.all});

        cmd.barrier(&.{.{
            .image = &.{.{
                .source_stage_mask = .{ .fragment_shader = true },
                .source_access_mask = .{ .shader_sampled_read = true },
                .dest_stage_mask = .{
                    .early_fragment_tests = true,
                    .late_fragment_tests = true,
                },
                .dest_access_mask = .{ .depth_stencil_attachment_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .depth_stencil_attachment_optimal,
                .image = &shdw_map.image,
                .range = .{
                    .aspect_mask = .{ .depth = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            }},
        }});

        cmd.beginRendering(.{
            .colors = &.{},
            .depth = .{
                .view = &shdw_map.view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .depth_stencil = .{ 1, undefined } },
                .resolve = null,
            },
            .stencil = blk: {
                assert(!shdw_map.format.getAspectMask().stencil);
                break :blk null;
            },
            .render_area = .{ .width = ShadowMap.extent, .height = ShadowMap.extent },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{.vertex}, &.{&shd.shadow_map});
        cmd.setVertexInput(&.{.{
            .binding = 0,
            .stride = 3 * @sizeOf(f32),
            .step_rate = .vertex,
        }}, &.{.{
            .location = 0,
            .binding = 0,
            .format = .rgb32_sfloat,
            .offset = 0,
        }});
        cmd.setViewports(&.{.{
            .x = 0,
            .y = 0,
            .width = ShadowMap.extent,
            .height = ShadowMap.extent,
            .znear = 0,
            .zfar = 1,
        }});
        cmd.setScissorRects(&.{.{
            .x = 0,
            .y = 0,
            .width = ShadowMap.extent,
            .height = ShadowMap.extent,
        }});
        cmd.setSampleCount(.@"1");
        cmd.setDepthBiasEnable(true);
        cmd.setDepthBias(0.01, 16, if (shdw_map.depth_bias_clamp) 1 else 0);

        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setVertexBuffers(0, &.{&vert_buf.buffer}, &.{latt_pos_off}, &.{latt.sizeOfPositions()});
        cmd.setCullMode(.front);
        cmd.setFrontFace(.counter_clockwise);
        for (0..lattice_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 2, &.{&desc.sets[2][frame][i]});
            cmd.draw(latt.vertexCount(), 1, 0, 0);
        }

        cmd.setPrimitiveTopology(plane.topology);
        cmd.setVertexBuffers(
            0,
            &.{&vert_buf.buffer},
            &.{plane_pos_off},
            &.{@sizeOf(plane.Positions)},
        );
        cmd.setCullMode(.back);
        cmd.setFrontFace(plane.front_face);
        for (lattice_n..draw_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 2, &.{&desc.sets[2][frame][i]});
            cmd.draw(plane.vertex_count, 1, 0, 0);
        }

        cmd.endRendering();

        cmd.barrier(&.{.{
            .image = &.{
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
                    .image = &shdw_map.image,
                    .range = .{
                        .aspect_mask = .{ .depth = true },
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
                    .image = &color.image,
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
                .{
                    .source_stage_mask = .{ .late_fragment_tests = true },
                    .source_access_mask = .{ .depth_stencil_attachment_write = true },
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
            .colors = &.{.{
                .view = &color.view,
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .color_f32 = .{ 0.5, 0.5, 0.5, 1 } },
                .resolve = .{
                    .view = &plat.image_views[next],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            }},
            .depth = .{
                .view = &depth.view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .depth_stencil = .{ 1, undefined } },
                .resolve = null,
            },
            .stencil = blk: {
                assert(!depth.format.getAspectMask().stencil);
                break :blk null;
            },
            .render_area = .{ .width = width, .height = height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.vertex, &shd.fragment });
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
        cmd.setCullMode(.back);
        cmd.setSampleCount(Color.samples);
        cmd.setDepthBiasEnable(false);

        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setVertexBuffers(
            0,
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ latt_pos_off, latt_norm_off },
            &.{ latt.sizeOfPositions(), latt.sizeOfNormals() },
        );
        cmd.setFrontFace(.counter_clockwise);
        for (0..lattice_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{
                &desc.sets[1][frame][i],
                &desc.sets[2][frame][i],
            });
            cmd.draw(latt.vertexCount(), 1, 0, 0);
        }

        cmd.setPrimitiveTopology(plane.topology);
        cmd.setVertexBuffers(
            0,
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ plane_pos_off, plane_norm_off },
            &.{ @sizeOf(plane.Positions), @sizeOf(plane.Normals) },
        );
        cmd.setFrontFace(plane.front_face);
        for (lattice_n..draw_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{
                &desc.sets[1][frame][i],
                &desc.sets[2][frame][i],
            });
            cmd.draw(plane.vertex_count, 1, 0, 0);
        }

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

const Color = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    const samples = ngl.SampleCount.@"4";

    fn init(gpa: std.mem.Allocator) ngl.Error!Color {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = plat.format.format,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{
                .color_attachment = true,
                .transient_attachment = true,
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
                    .lazily_allocated = true,
                }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        const view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
            .type = .@"2d",
            .format = plat.format.format,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });

        return .{
            .image = img,
            .memory = mem,
            .view = view,
        };
    }

    fn deinit(self: *Color, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const Depth = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    const samples = Color.samples;

    fn init(gpa: std.mem.Allocator) ngl.Error!Depth {
        const fmt = for ([_]ngl.Format{
            .d32_sfloat,
            .x8_d24_unorm,
            .d16_unorm,
        }) |fmt| {
            const opt = fmt.getFeatures(dev).optimal_tiling;
            if (opt.depth_stencil_attachment)
                break fmt;
        } else unreachable;

        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{
                .depth_stencil_attachment = true,
                .transient_attachment = true,
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
                    .lazily_allocated = true,
                }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        const view = try ngl.ImageView.init(gpa, dev, .{
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

        return .{
            .format = fmt,
            .image = img,
            .memory = mem,
            .view = view,
        };
    }

    fn deinit(self: *Depth, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const ShadowMap = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,
    depth_bias_clamp: bool,

    const extent = 1024;
    const set_index = 0;
    const binding = 0;

    fn init(gpa: std.mem.Allocator) ngl.Error!ShadowMap {
        const fmt, const hw_pcf = for ([_]ngl.Format{
            .d32_sfloat,
            .x8_d24_unorm,
            .d16_unorm,
        }) |fmt| {
            const opt = fmt.getFeatures(dev).optimal_tiling;
            const hw_pcf = opt.sampled_image_filter_linear;
            if (opt.sampled_image and opt.depth_stencil_attachment)
                break .{ fmt, hw_pcf };
        } else unreachable;

        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = extent,
            .height = extent,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
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
            .u_address = .clamp_to_border,
            .v_address = .clamp_to_border,
            .w_address = .clamp_to_border,
            .border_color = .opaque_white_float,
            .mag = if (hw_pcf) .linear else .nearest,
            .min = if (hw_pcf) .linear else .nearest,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = .less,
        });

        return .{
            .format = fmt,
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
            .depth_bias_clamp = ngl.Feature.get(gpa, ctx.gpu, .core).?
                .rasterization.depth_bias_clamp,
        };
    }

    fn deinit(self: *ShadowMap, gpa: std.mem.Allocator) void {
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
    const extent = 64;
    const count: i32 = 6 * 6;
    const size = @sizeOf(f16) * 2 * count * extent * extent;
    const set_index = 0;
    const binding = 1;

    fn init(gpa: std.mem.Allocator) ngl.Error!RandomSampling {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"3d",
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
            .type = .@"3d",
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
        shadow_map: *ShadowMap,
        random_sampling: *RandomSampling,
    ) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = ShadowMap.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&shadow_map.sampler},
                },
                .{
                    .binding = RandomSampling.binding,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&random_sampling.sampler},
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
                .combined_image_sampler = frame_n * 2,
                .uniform_buffer = frame_n * (1 + material_n + draw_n),
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

    fn writeUb(
        self: *Descriptor,
        comptime T: type,
        gpa: std.mem.Allocator,
        frame: usize,
        draw: ?usize,
        buffer: *ngl.Buffer,
        offset: u64,
    ) ngl.Error!void {
        try ngl.DescriptorSet.write(gpa, dev, &.{.{
            .descriptor_set = switch (T.set_index) {
                0 => &self.sets[T.set_index][frame],
                1, 2 => &self.sets[T.set_index][frame][draw.?],
                else => unreachable,
            },
            .binding = T.binding,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = buffer,
                .offset = offset,
                .range = T.size,
            }} },
        }});
    }

    fn writeIs(
        self: *Descriptor,
        comptime T: type,
        gpa: std.mem.Allocator,
        frame: usize,
        view: *ngl.ImageView,
        layout: ngl.Image.Layout,
        sampler: ?*ngl.Sampler,
    ) ngl.Error!void {
        try ngl.DescriptorSet.write(gpa, dev, &.{.{
            .descriptor_set = &self.sets[T.set_index][frame],
            .binding = T.binding,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = view,
                .layout = layout,
                .sampler = sampler,
            }} },
        }});
    }

    fn deinit(self: *Descriptor, gpa: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Shader = struct {
    shadow_map: ngl.Shader,
    vertex: ngl.Shader,
    fragment: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(gpa: std.mem.Allocator, descriptor: *Descriptor) ngl.Error!Shader {
        const dapi = ctx.gpu.getDriverApi();

        const shdw_map_code_spv align(4) = @embedFile("shader/shadow_map.vert.spv").*;
        const shdw_map_code = switch (dapi) {
            .vulkan => &shdw_map_code_spv,
        };

        const vert_code_spv align(4) = @embedFile("shader/vert.spv").*;
        const vert_code = switch (dapi) {
            .vulkan => &vert_code_spv,
        };

        const frag_code_spv align(4) = @embedFile("shader/frag.spv").*;
        const frag_code = switch (dapi) {
            .vulkan => &frag_code_spv,
        };

        const set_layts = &.{
            &descriptor.set_layouts[0],
            &descriptor.set_layouts[1],
            &descriptor.set_layouts[2],
        };

        const shdw_map_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .vertex,
            .next = .{},
            .code = shdw_map_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = null,
            .link = false,
        }});
        defer gpa.free(shdw_map_shd);
        errdefer if (shdw_map_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

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
                .specialization = .{
                    .constants = &.{.{
                        .id = 0,
                        .offset = 0,
                        .size = 4,
                    }},
                    .data = std.mem.asBytes(&RandomSampling.count),
                },
                .link = true,
            },
        });
        defer gpa.free(shaders);
        errdefer for (shaders) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        var layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(gpa, dev);

        return .{
            .shadow_map = try shdw_map_shd[0],
            .vertex = try shaders[0],
            .fragment = try shaders[1],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, gpa: std.mem.Allocator) void {
        self.shadow_map.deinit(gpa, dev);
        self.vertex.deinit(gpa, dev);
        self.fragment.deinit(gpa, dev);
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
        const rend = if (dev.queues[pres].capabilities.graphics)
            pres
        else
            dev.findQueue(.{ .graphics = true }, null) orelse return ngl.Error.NotSupported;

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

const Light = packed struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    _pos_pad: f32 = 0,
    col_r: f32,
    col_g: f32,
    col_b: f32,
    intensity: f32,

    const size = @sizeOf(Light);
    const set_index = 0;
    const binding = 2;

    fn init(position: [3]f32, color: [3]f32, intensity: f32) Light {
        var self: Light = undefined;
        self.set(position, color, intensity);
        return self;
    }

    fn set(self: *Light, position: [3]f32, color: [3]f32, intensity: f32) void {
        self.pos_x = position[0];
        self.pos_y = position[1];
        self.pos_z = position[2];
        self.col_r = color[0];
        self.col_g = color[1];
        self.col_b = color[2];
        self.intensity = intensity;
    }

    fn copy(self: Light, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Material = packed struct {
    col_r: f32,
    col_g: f32,
    col_b: f32,
    col_a: f32,
    metallic: f32,
    smoothness: f32,
    reflectance: f32,

    const size = @sizeOf(Material);
    const set_index = 1;
    const binding = 0;

    fn init(color: [4]f32, metallic: f32, smoothness: f32, reflectance: f32) Material {
        var self: Material = undefined;
        self.set(color, metallic, smoothness, reflectance);
        return self;
    }

    fn set(self: *Material, color: [4]f32, metallic: f32, smoothness: f32, reflectance: f32) void {
        self.col_r = color[0];
        self.col_g = color[1];
        self.col_b = color[2];
        self.col_a = color[3];
        self.metallic = metallic;
        self.smoothness = smoothness;
        self.reflectance = reflectance;
    }

    fn copy(self: Material, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Model = struct {
    shdw_s_mvp_mv_n: [16 + 16 + 16 + 16 + 12]f32,

    const size = @sizeOf(@typeInfo(Model).Struct.fields[0].type);
    const set_index = 2;
    const binding = 0;

    fn init(shadow_mvp: [16]f32, s: [16]f32, mvp: [16]f32, mv: [16]f32, n: [12]f32) Model {
        var self: Model = undefined;
        self.set(shadow_mvp, s, mvp, mv, n);
        return self;
    }

    fn set(
        self: *Model,
        shadow_mvp: [16]f32,
        s: [16]f32,
        mvp: [16]f32,
        mv: [16]f32,
        n: [12]f32,
    ) void {
        @memcpy(self.shdw_s_mvp_mv_n[0..16], &shadow_mvp);
        @memcpy(self.shdw_s_mvp_mv_n[16..32], &s);
        @memcpy(self.shdw_s_mvp_mv_n[32..48], &mvp);
        @memcpy(self.shdw_s_mvp_mv_n[48..64], &mv);
        @memcpy(self.shdw_s_mvp_mv_n[64..76], &n);
    }

    fn copy(self: Model, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.shdw_s_mvp_mv_n));
    }
};

const Draw = struct {
    model: Model,
    material: Material,
};
