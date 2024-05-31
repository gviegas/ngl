const std = @import("std");
const assert = std.debug.assert;

const ngl = @import("ngl");
const pfm = ngl.pfm;

const Ctx = @import("Ctx");
const model = @import("model");
const util = @import("util");

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

    var depth = try Depth(.{ width, height }, Color.samples).init(gpa);
    defer depth.deinit(gpa);

    var shdw_map = try ShadowMap.init(gpa);
    defer shdw_map.deinit(gpa);

    var shdw_dep = try Depth([_]u32{ShadowMap.extent} ** 2, .@"1").init(gpa);
    defer shdw_dep.deinit(gpa);

    const dep_bias_clamp = ngl.Feature.get(gpa, ctx.gpu, .core).?.rasterization.depth_bias_clamp;

    var latt = try model.loadObj(gpa, "data/geometry/lattice.obj");
    defer latt.deinit(gpa);
    const plane = &model.plane;
    assert(latt.indices == null);
    comptime assert(!@hasDecl(plane.*, "indices"));

    const latt_pos_off = 0;
    const latt_norm_off = latt_pos_off + latt.positionSize();
    const plane_pos_off = latt_norm_off + latt.normalSize();
    const plane_norm_off = plane_pos_off + @sizeOf(@TypeOf(plane.data.position));
    const latt_size = plane_pos_off;
    const plane_size = plane_norm_off + @sizeOf(@TypeOf(plane.data.normal)) - plane_pos_off;
    const vert_buf_size = latt_size + plane_size;
    var vert_buf = try Buffer(.device).init(gpa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(gpa);

    const light_off = 0;
    const globl_off = (light_off + Light.size + 255) & ~@as(u64, 255);
    const matl_off = globl_off + draw_n * ((Global.size + 255) & ~@as(u64, 255));
    const unif_strd = matl_off + draw_n * ((Material.size + 255) & ~@as(u64, 255));
    const unif_buf_size = frame_n * unif_strd;
    var unif_buf = try Buffer(.device).init(gpa, unif_buf_size, .{
        .uniform_buffer = true,
        .transfer_dest = true,
    });
    defer unif_buf.deinit(gpa);

    const vert_cpy_off = 0;
    const unif_cpy_off = (vert_cpy_off + vert_buf_size + 255) & ~@as(u64, 255);
    const stg_buf_size = unif_cpy_off + unif_buf_size;
    var stg_buf = try Buffer(.host).init(gpa, stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit(gpa);

    var desc = try Descriptor.init(gpa, &shdw_map);
    defer desc.deinit(gpa);

    var shd = try Shader.init(gpa, &desc);
    defer shd.deinit(gpa);

    var cq = try Command.init(gpa);
    defer cq.deinit(gpa);
    const one_queue = cq.multiqueue == null;

    const v = util.lookAt(.{ 0, 0, 0 }, .{ 0, -4, -4 }, .{ 0, -1, 0 });
    const p = util.perspective(std.math.pi / 4.0, @as(f32, width) / height, 0.01, 100);

    const light_world_pos = .{ 13, -10, 2 };
    const light_view_pos = util.mulMV(4, v, light_world_pos ++ [1]f32{1})[0..3].*;
    const light_col = .{ 1, 1, 1 };
    const intensity = 100;
    const light = Light.init(light_view_pos, light_col, intensity);

    const shdw_v = util.lookAt(.{ 0, 0, 0 }, light_world_pos, .{ 0, -1, 0 });
    const shdw_p = util.frustum(-0.25, 0.25, -0.25, 0.25, 1, 100);
    const shdw_vp = util.mulM(4, shdw_p, shdw_v);
    const vps = util.mulM(4, .{
        0.5, 0,   0, 0,
        0,   0.5, 0, 0,
        0,   0,   1, 0,
        0.5, 0.5, 0, 1,
    }, shdw_vp);
    const draws = blk: {
        const xforms = [draw_n][16]f32{
            util.identity(4),
            .{
                20, 0, 0,  0,
                0,  1, 0,  0,
                0,  0, 20, 0,
                0,  1, 0,  1,
            },
        };
        const matls = [draw_n]Material{
            Material.init(.{ 0.8392157, 0.8196078, 0.7843137, 1 }, 1, 0.725, 0),
            Material.init(.{ 0.5803922, 0.4901961, 0.4588235, 1 }, 0, 0.6, 0.5),
        };
        var draws: [draw_n]Draw = undefined;
        for (&draws, xforms, matls) |*draw, m, matl| {
            const shdw_mvp = util.mulM(4, shdw_vp, m);
            const s = util.mulM(4, vps, m);
            const mv = util.mulM(4, v, m);
            const inv = util.invert3(util.upperLeft(4, mv));
            const n = .{
                inv[0], inv[3], inv[6], undefined,
                inv[1], inv[4], inv[7], undefined,
                inv[2], inv[5], inv[8], undefined,
            };
            const mvp = util.mulM(4, p, mv);
            draw.* = .{
                .global = Global.init(shdw_mvp, s, mvp, mv, n),
                .material = matl,
            };
        }
        break :blk draws;
    };

    const vert_data = stg_buf.data[vert_cpy_off .. vert_cpy_off + vert_buf_size];
    @memcpy(
        vert_data[latt_pos_off .. latt_pos_off + latt.positionSize()],
        std.mem.sliceAsBytes(latt.positions.items),
    );
    @memcpy(
        vert_data[latt_norm_off .. latt_norm_off + latt.normalSize()],
        std.mem.sliceAsBytes(latt.normals.items),
    );
    @memcpy(
        vert_data[plane_pos_off .. plane_pos_off + @sizeOf(@TypeOf(plane.data.position))],
        std.mem.asBytes(&plane.data.position),
    );
    @memcpy(
        vert_data[plane_norm_off .. plane_norm_off + @sizeOf(@TypeOf(plane.data.normal))],
        std.mem.asBytes(&plane.data.normal),
    );

    for (0..frame_n) |frame| {
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd .. unif_cpy_off + strd + unif_strd];

        light.copy(data[light_off .. light_off + Light.size]);

        for (draws, 0..) |draw, i| {
            const goff = globl_off + i * ((Global.size + 255) & ~@as(u64, 255));
            draw.global.copy(data[goff .. goff + Global.size]);

            const moff = matl_off + i * ((Material.size + 255) & ~@as(u64, 255));
            draw.material.copy(data[moff .. moff + Material.size]);
        }
    }

    try desc.writeSet0(gpa, &shdw_map, &unif_buf.buffer, blk: {
        var offs: [frame_n]u64 = undefined;
        for (&offs, 0..) |*off, frame|
            off.* = frame * unif_strd + light_off;
        break :blk offs;
    });

    try desc.writeSet1(gpa, &unif_buf.buffer, blk: {
        var offs: [frame_n][draw_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, draw| {
                off.* = frame * unif_strd + globl_off +
                    draw * ((Global.size + 255) & ~@as(u64, 255));
            };
        break :blk offs;
    }, blk: {
        var offs: [frame_n][draw_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, draw| {
                off.* = frame * unif_strd + matl_off +
                    draw * ((Material.size + 255) & ~@as(u64, 255));
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

    try cmd.end();

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
        cmd.setDescriptors(.compute, &shd.layout, 0, &.{&desc.sets[0][frame]});
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
            .image = &.{
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &shdw_map.image,
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
                    .image = &shdw_dep.image,
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
                .view = &shdw_map.views[0],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = null,
            }},
            .depth = .{
                .view = &shdw_dep.view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .depth_stencil = .{ 1, undefined } },
                .resolve = null,
            },
            .stencil = blk: {
                assert(!shdw_dep.format.getAspectMask().stencil);
                break :blk null;
            },
            .render_area = .{ .width = ShadowMap.extent, .height = ShadowMap.extent },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.shadow_map_vert, &shd.shadow_map_frag });
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
        cmd.setDepthBias(0.01, 2, if (dep_bias_clamp) 1 else 0);

        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setVertexBuffers(0, &.{&vert_buf.buffer}, &.{latt_pos_off}, &.{latt.positionSize()});
        cmd.setCullMode(.front);
        cmd.setFrontFace(.counter_clockwise);
        for (0..lattice_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{&desc.sets[1][frame][i]});
            cmd.draw(latt.vertexCount(), 1, 0, 0);
        }

        cmd.setPrimitiveTopology(plane.topology);
        cmd.setVertexBuffers(
            0,
            &.{&vert_buf.buffer},
            &.{plane_pos_off},
            &.{@sizeOf(@TypeOf(plane.data.position))},
        );
        cmd.setCullMode(.back);
        cmd.setFrontFace(plane.front_face);
        for (lattice_n..draw_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{&desc.sets[1][frame][i]});
            cmd.draw(plane.vertex_count, 1, 0, 0);
        }

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
                    .image = &shdw_map.image,
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
                    .source_access_mask = .{
                        .shader_sampled_read = true,
                        .shader_storage_write = true,
                    },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .general,
                    .image = &shdw_map.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 1,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.setShaders(&.{.compute}, &.{&shd.shadow_blur_comp});
        cmd.dispatch(ShadowMap.extent, ShadowMap.extent, 1);

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
                    .image = &shdw_map.image,
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
                    .image = &shdw_map.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 1,
                        .layers = 1,
                    },
                },
            },
        }});

        cmd.setShaders(&.{.compute}, &.{&shd.shadow_blur_2_comp});
        cmd.dispatch(ShadowMap.extent, ShadowMap.extent, 1);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .shader_read_only_optimal,
                    .image = &shdw_map.image,
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

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.light_vert, &shd.light_frag });
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
            &.{ latt.positionSize(), latt.normalSize() },
        );
        cmd.setFrontFace(.counter_clockwise);
        for (0..lattice_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{&desc.sets[1][frame][i]});
            cmd.draw(latt.vertexCount(), 1, 0, 0);
        }

        cmd.setPrimitiveTopology(plane.topology);
        cmd.setVertexBuffers(
            0,
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ plane_pos_off, plane_norm_off },
            &.{ @sizeOf(@TypeOf(plane.data.position)), @sizeOf(@TypeOf(plane.data.normal)) },
        );
        cmd.setFrontFace(plane.front_face);
        for (lattice_n..draw_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{&desc.sets[1][frame][i]});
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

fn Depth(comptime size: [2]u32, comptime samples: ngl.SampleCount) type {
    return struct {
        format: ngl.Format,
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,

        fn init(gpa: std.mem.Allocator) ngl.Error!@This() {
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
                .width = size[0],
                .height = size[1],
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

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.view.deinit(gpa, dev);
            self.image.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
        }
    };
}

const ShadowMap = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rg32_sfloat;
    const extent = 512;
    const set_index = 0;
    const binding = struct {
        // Layer 0 filtering in 1st blur pass and final light pass.
        const blur_light_comb = 0;
        // Layer 1 writing in 1st blur pass.
        const blur_stor = 1;
        // Layer 1 filtering in 2nd blur pass.
        const blur_2_comb = 2;
        // Layer 0 writing in 2nd blur pass.
        const blur_2_stor = 3;
    };

    fn init(gpa: std.mem.Allocator) ngl.Error!ShadowMap {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 2,
            // TODO: Mipmap.
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
                .color_attachment = true,
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

        var views: [2]ngl.ImageView = undefined;
        for (&views, 0..) |*view, i|
            view.* = ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = @intCast(i),
                    .layers = 1,
                },
            }) catch |err| {
                for (0..i) |j|
                    views[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&views) |*view|
            view.deinit(gpa, dev);

        const filt = if (format.getFeatures(dev).optimal_tiling.sampled_image_filter_linear)
            ngl.Sampler.Filter.linear
        else
            ngl.Sampler.Filter.nearest;

        const splr = try ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .clamp_to_border,
            .v_address = .clamp_to_border,
            .w_address = .clamp_to_border,
            .border_color = .opaque_white_float,
            .mag = filt,
            .min = filt,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        });

        return .{
            .image = img,
            .memory = mem,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *ShadowMap, gpa: std.mem.Allocator) void {
        for (&self.views) |*view|
            view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
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

const Descriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pool: ngl.DescriptorPool,
    sets: struct {
        [frame_n]ngl.DescriptorSet,
        [frame_n][draw_n]ngl.DescriptorSet,
    },

    fn init(gpa: std.mem.Allocator, shadow_map: *ShadowMap) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = ShadowMap.binding.blur_light_comb,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&shadow_map.sampler},
                },
                .{
                    .binding = ShadowMap.binding.blur_stor,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = ShadowMap.binding.blur_2_comb,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{&shadow_map.sampler},
                },
                .{
                    .binding = ShadowMap.binding.blur_2_stor,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
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
            .bindings = &.{
                .{
                    .binding = Global.binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .vertex = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = Material.binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = frame_n + draw_n * frame_n,
            .pool_size = .{
                .combined_image_sampler = 2 * frame_n,
                .storage_image = 2 * frame_n,
                .uniform_buffer = frame_n + 2 * draw_n * frame_n,
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = try pool.alloc(gpa, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** (draw_n * frame_n),
        });
        defer gpa.free(sets);

        return .{
            .set_layouts = .{ set_layt, set_layt_2 },
            .pool = pool,
            .sets = .{
                sets[0..frame_n].*,
                blk: {
                    var dest: [frame_n][draw_n]ngl.DescriptorSet = undefined;
                    var source = sets[frame_n..];
                    for (0..frame_n) |frame| {
                        source = source[frame * draw_n ..];
                        dest[frame] = source[0..draw_n].*;
                    }
                    break :blk dest;
                },
            },
        };
    }

    fn writeSet0(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        shadow_map: *ShadowMap,
        uniform_buffer: *ngl.Buffer,
        uniform_offsets: [frame_n]u64,
    ) ngl.Error!void {
        var writes: [5 * frame_n]ngl.DescriptorSet.Write = undefined;
        const comb_l0 = writes[0..frame_n];
        const stor_l1 = writes[frame_n .. 2 * frame_n];
        const comb_l1 = writes[2 * frame_n .. 3 * frame_n];
        const stor_l0 = writes[3 * frame_n .. 4 * frame_n];
        const unif_light = writes[4 * frame_n .. 5 * frame_n];

        const Isw = ngl.DescriptorSet.Write.ImageSamplerWrite;
        var isw_arr: [2 * frame_n]Isw = undefined;
        var isw: []Isw = &isw_arr;

        const Iw = ngl.DescriptorSet.Write.ImageWrite;
        var iw_arr: [2 * frame_n]Iw = undefined;
        var iw: []Iw = &iw_arr;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [frame_n]Bw = undefined;
        var bw: []Bw = &bw_arr;

        for (comb_l0, &self.sets[0]) |*comb, *set| {
            isw[0] = .{
                .view = &shadow_map.views[0],
                .layout = .shader_read_only_optimal,
                .sampler = null,
            };
            comb.* = .{
                .descriptor_set = set,
                .binding = ShadowMap.binding.blur_light_comb,
                .element = 0,
                .contents = .{ .combined_image_sampler = isw[0..1] },
            };
            isw = isw[1..];
        }

        for (stor_l1, &self.sets[0]) |*stor, *set| {
            iw[0] = .{
                .view = &shadow_map.views[1],
                .layout = .general,
            };
            stor.* = .{
                .descriptor_set = set,
                .binding = ShadowMap.binding.blur_stor,
                .element = 0,
                .contents = .{ .storage_image = iw[0..1] },
            };
            iw = iw[1..];
        }

        for (comb_l1, &self.sets[0]) |*comb, *set| {
            isw[0] = .{
                .view = &shadow_map.views[1],
                .layout = .shader_read_only_optimal,
                .sampler = null,
            };
            comb.* = .{
                .descriptor_set = set,
                .binding = ShadowMap.binding.blur_2_comb,
                .element = 0,
                .contents = .{ .combined_image_sampler = isw[0..1] },
            };
            isw = isw[1..];
        }

        for (stor_l0, &self.sets[0]) |*stor, *set| {
            iw[0] = .{
                .view = &shadow_map.views[0],
                .layout = .general,
            };
            stor.* = .{
                .descriptor_set = set,
                .binding = ShadowMap.binding.blur_2_stor,
                .element = 0,
                .contents = .{ .storage_image = iw[0..1] },
            };
            iw = iw[1..];
        }

        for (unif_light, &self.sets[0], uniform_offsets) |*unif, *set, off| {
            bw[0] = .{
                .buffer = uniform_buffer,
                .offset = off,
                .range = Light.size,
            };
            unif.* = .{
                .descriptor_set = set,
                .binding = Light.binding,
                .element = 0,
                .contents = .{ .uniform_buffer = bw[0..1] },
            };
            bw = bw[1..];
        }

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn writeSet1(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        global_offsets: [frame_n][draw_n]u64,
        material_offsets: [frame_n][draw_n]u64,
    ) ngl.Error!void {
        var writes: [2 * draw_n * frame_n]ngl.DescriptorSet.Write = undefined;
        var w: []ngl.DescriptorSet.Write = &writes;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [writes.len]Bw = undefined;
        var bw: []Bw = &bw_arr;

        for (&self.sets[1], global_offsets, material_offsets) |*sets, globl_offs, matl_offs|
            for (sets, globl_offs, matl_offs) |*set, globl_off, matl_off| {
                bw[0] = .{
                    .buffer = uniform_buffer,
                    .offset = globl_off,
                    .range = Global.size,
                };
                w[0] = .{
                    .descriptor_set = set,
                    .binding = Global.binding,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };

                bw[1] = .{
                    .buffer = uniform_buffer,
                    .offset = matl_off,
                    .range = Material.size,
                };
                w[1] = .{
                    .descriptor_set = set,
                    .binding = Material.binding,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[1..2] },
                };

                bw = bw[2..];
                w = w[2..];
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
    shadow_map_vert: ngl.Shader,
    shadow_map_frag: ngl.Shader,
    shadow_blur_comp: ngl.Shader,
    shadow_blur_2_comp: ngl.Shader,
    light_vert: ngl.Shader,
    light_frag: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(gpa: std.mem.Allocator, descriptor: *Descriptor) ngl.Error!Shader {
        const dapi = ctx.gpu.getDriverApi();

        const shdw_map_vert_code_spv align(4) = @embedFile("shader/shdw_map_vert.spv").*;
        const shdw_map_vert_code = switch (dapi) {
            .vulkan => &shdw_map_vert_code_spv,
        };

        const shdw_map_frag_code_spv align(4) = @embedFile("shader/shdw_map_frag.spv").*;
        const shdw_map_frag_code = switch (dapi) {
            .vulkan => &shdw_map_frag_code_spv,
        };

        const shdw_blur_comp_code_spv align(4) = @embedFile("shader/shdw_blur_comp.spv").*;
        const shdw_blur_comp_code = switch (dapi) {
            .vulkan => &shdw_blur_comp_code_spv,
        };

        const shdw_blur_2_comp_code_spv align(4) = @embedFile("shader/shdw_blur_2_comp.spv").*;
        const shdw_blur_2_comp_code = switch (dapi) {
            .vulkan => &shdw_blur_2_comp_code_spv,
        };

        const light_vert_code_spv align(4) = @embedFile("shader/light_vert.spv").*;
        const light_vert_code = switch (dapi) {
            .vulkan => &light_vert_code_spv,
        };

        const light_frag_code_spv align(4) = @embedFile("shader/light_frag.spv").*;
        const light_frag_code = switch (dapi) {
            .vulkan => &light_frag_code_spv,
        };

        const set_layts = &.{
            &descriptor.set_layouts[0],
            &descriptor.set_layouts[1],
        };

        const shdw_map_shds = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .vertex,
                .next = .{ .fragment = true },
                .code = shdw_map_vert_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
            .{
                .type = .fragment,
                .next = .{},
                .code = shdw_map_frag_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
        });
        defer gpa.free(shdw_map_shds);
        errdefer for (shdw_map_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const shdw_blur_shds = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .compute,
                .next = .{},
                .code = shdw_blur_comp_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = false,
            },
            .{
                .type = .compute,
                .next = .{},
                .code = shdw_blur_2_comp_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = false,
            },
        });
        defer gpa.free(shdw_blur_shds);
        errdefer for (shdw_blur_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const light_shds = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .vertex,
                .next = .{ .fragment = true },
                .code = light_vert_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
            .{
                .type = .fragment,
                .next = .{},
                .code = light_frag_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
        });
        defer gpa.free(light_shds);
        errdefer for (light_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        var layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(gpa, dev);

        return .{
            .shadow_map_vert = try shdw_map_shds[0],
            .shadow_map_frag = try shdw_map_shds[1],
            .shadow_blur_comp = try shdw_blur_shds[0],
            .shadow_blur_2_comp = try shdw_blur_shds[1],
            .light_vert = try light_shds[0],
            .light_frag = try light_shds[1],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, gpa: std.mem.Allocator) void {
        for ([_]*ngl.Shader{
            &self.shadow_map_vert,
            &self.shadow_map_frag,
            &self.shadow_blur_comp,
            &self.shadow_blur_2_comp,
            &self.light_vert,
            &self.light_frag,
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
    const binding = 4;

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

const Global = struct {
    shdw_s_mvp_mv_n: [16 + 16 + 16 + 16 + 12]f32,

    const size = @sizeOf(@typeInfo(Global).Struct.fields[0].type);
    const set_index = 1;
    const binding = 0;

    fn init(shadow_mvp: [16]f32, s: [16]f32, mvp: [16]f32, mv: [16]f32, n: [12]f32) Global {
        var self: Global = undefined;
        self.set(shadow_mvp, s, mvp, mv, n);
        return self;
    }

    fn set(
        self: *Global,
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

    fn copy(self: Global, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.shdw_s_mvp_mv_n));
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
    const binding = 1;

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

const Draw = struct {
    global: Global,
    material: Material,
};
