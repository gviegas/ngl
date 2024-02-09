const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const util = @import("util.zig");
const model = @import("model.zig");

pub fn main() !void {
    try do();
}

const frame_n = 2;
const draw_n = 5;

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var queue = try Queue.init();
    defer queue.deinit();

    var mdl = try model.loadObj(gpa, "data/geometry/sphere.obj");
    defer mdl.deinit();

    const vert_buf_size = mdl.vertexSize() + @sizeOf(@TypeOf(model.plane.data)) +
        @sizeOf(@TypeOf(triangle.data));
    var vert_buf = try Buffer(.device).init(vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit();

    const stg_buf_size = vert_buf_size;
    var stg_buf = try Buffer(.host).init(stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit();

    {
        var dest = stg_buf.data;
        var size = mdl.positionSize();
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(mdl.positions.items.ptr))[0..size]);
        dest = dest[size..];
        size = mdl.normalSize();
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(mdl.normals.items.ptr))[0..size]);
        dest = stg_buf.data[mdl.vertexSize()..];
        size = @sizeOf(@TypeOf(model.plane.data));
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(&model.plane.data))[0..size]);
        dest = dest[size..];
        size = @sizeOf(@TypeOf(triangle.data));
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(&triangle.data))[0..size]);
    }

    try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
    var cmd = try queue.buffers[0].begin(gpa, dev, .{
        .one_time_submit = true,
        .inheritance = null,
    });
    cmd.copyBuffer(&.{.{
        .source = &stg_buf.buffer,
        .dest = &vert_buf.buffer,
        .regions = &.{.{
            .source_offset = 0,
            .dest_offset = 0,
            .size = vert_buf_size,
        }},
    }});
    try cmd.end();
    {
        ctx.lockQueue(queue.index);
        defer ctx.unlockQueue(queue.index);
        try dev.queues[queue.index].submit(gpa, dev, &queue.fences[0], &.{.{
            .commands = &.{.{ .command_buffer = &queue.buffers[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&queue.fences[0]});

    var hdr_map = try HdrMap.init();
    defer hdr_map.deinit();

    var bloom_map = try BloomMap.init();
    defer bloom_map.deinit();

    var tone_map = try ToneMap.init();
    defer tone_map.deinit();

    var dep_map = try DepthMap.init();
    defer dep_map.deinit();

    const unif_buf_size = frame_n * (1 + 2 * draw_n) * 256;
    var unif_buf = try Buffer(.host).init(unif_buf_size, .{ .uniform_buffer = true });
    defer unif_buf.deinit();

    var desc = try Descriptor.init(&hdr_map, &bloom_map, &tone_map);
    defer desc.deinit();

    for (0..frame_n) |i|
        try desc.write(i, &hdr_map, &bloom_map, &tone_map, &unif_buf);

    const v = util.lookAt(.{ 0, 0, 0 }, .{ 0, -0.6666, -1 }, .{ 0, -1, 0 });
    const p = util.perspective(
        std.math.pi / 3.0,
        @as(f32, Platform.width) / @as(f32, Platform.height),
        0.1,
        100,
    );

    const models = [draw_n - 1]Renderable(.model){
        Renderable(.model).init(
            0,
            [16]f32{
                0.1,  0,    0,   0,
                0,    0.1,  0,   0,
                0,    0,    0.1, 0,
                -0.3, -0.3, 0,   1,
            },
            v,
            p,
            .{ 1, 0, 0 },
            1,
            0.3,
            0,
        ),
        Renderable(.model).init(
            1,
            [16]f32{
                0.1, 0,    0,   0,
                0,   0.1,  0,   0,
                0,   0,    0.1, 0,
                0.3, -0.3, 0,   1,
            },
            v,
            p,
            .{ 0, 1, 0 },
            0,
            0.6,
            0.075,
        ),
        Renderable(.model).init(
            2,
            [16]f32{
                0.1, 0,    0,    0,
                0,   0.1,  0,    0,
                0,   0,    0.1,  0,
                0,   -0.2, -0.3, 1,
            },
            v,
            p,
            .{ 0, 0, 1 },
            0,
            0.1,
            0.2,
        ),
        Renderable(.model).init(
            3,
            [16]f32{
                0.1, 0,    0,   0,
                0,   0.1,  0,   0,
                0,   0,    0.1, 0,
                0,   -0.4, 0.3, 1,
            },
            v,
            p,
            .{ 1, 1, 1 },
            1,
            1,
            0,
        ),
    };
    const planes = [1]Renderable(.plane){
        Renderable(.plane).init(
            models.len,
            [16]f32{
                5, 0, 0, 0,
                0, 5, 0, 0,
                0, 0, 5, 0,
                0, 0, 0, 1,
            },
            v,
            p,
            .{ 0.25, 0.2, 0.3333 },
            1,
            0.4,
            0,
        ),
    };
    const lights = [3]Light{
        Light.init(.{ -1, -3, 2 }, v, .{ 1, 1, 1 }, 100),
        Light.init(.{ -6, -0.2, 0 }, v, .{ 1, 1, 1 }, 100),
        Light.init(.{ -2, -0.3, -2 }, v, .{ 1, 1, 1 }, 100),
    };

    for (0..frame_n) |i| {
        for (models) |x| x.copy(i, &unif_buf);
        for (planes) |x| x.copy(i, &unif_buf);
        Light.copy(i, &unif_buf, &lights);
    }

    var pass = try Pass.init(&hdr_map, &dep_map);
    defer pass.deinit();

    var pl = try Pipeline.init(&desc, &pass);
    defer pl.deinit();

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;
    var timer = try std.time.Timer.start();
    const is_unified = queue.non_unified == null;

    while (timer.read() < std.time.ns_per_min) {
        if (plat.poll().done) break;

        const cmd_pool = &queue.pools[frame];
        const cmd_buf = &queue.buffers[frame];
        const semas = .{ &queue.semaphores[frame * 2], &queue.semaphores[frame * 2 + 1] };
        const fence = &queue.fences[frame];

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fence});
        try ngl.Fence.reset(gpa, dev, &.{fence});

        const next = try plat.swap_chain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try cmd_pool.reset(dev);
        cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });

        const set_0 = &desc.sets[frame * (1 + draw_n)];
        cmd.setDescriptors(.graphics, &desc.pipeline_layout, 0, &.{set_0});
        cmd.setDescriptors(.compute, &desc.pipeline_layout, 0, &.{set_0});

        // First render pass
        cmd.beginRenderPass(
            .{
                .render_pass = &pass.first.render_pass,
                .frame_buffer = &pass.first.frame_buffer,
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = Platform.width,
                    .height = Platform.height,
                },
                .clear_values = &.{
                    .{ .color_f32 = .{ 0.6, 0.6, 0, 1 } },
                    .{ .depth_stencil = .{ 1, undefined } },
                    null,
                },
            },
            .{ .contents = .inline_only },
        );
        drawRenderables(frame, &cmd, &pl, &desc, &vert_buf, mdl, &models, &planes);
        cmd.endRenderPass(.{});

        // Bloom threshold
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{
                    .compute_shader = true,
                    .fragment_shader = true,
                },
                .source_access_mask = .{
                    .shader_storage_read = true,
                    .shader_storage_write = true,
                    .shader_sampled_read = true,
                },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_storage_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .general,
                .image = &bloom_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 2,
                },
            }},
            .by_region = false,
        }});
        cmd.setPipeline(&pl.compute.bloom);
        cmd.dispatch(BloomMap.width, BloomMap.height, 1);

        // Bloom smoothing
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_write = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{
                    .shader_storage_read = true,
                    .shader_storage_write = true,
                },
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .general,
                .image = &bloom_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 2,
                },
            }},
            .by_region = false,
        }});
        cmd.setPipeline(&pl.compute.blur[0]);
        cmd.dispatch(BloomMap.width, BloomMap.height, 1);

        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{
                    .shader_storage_read = true,
                    .shader_storage_write = true,
                },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{
                    .shader_storage_read = true,
                    .shader_storage_write = true,
                },
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .general,
                .image = &bloom_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 2,
                },
            }},
            .by_region = false,
        }});
        cmd.setPipeline(&pl.compute.blur[1]);
        cmd.dispatch(BloomMap.width, BloomMap.height, 1);

        // First tone map downsample
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{
                .{
                    .source_stage_mask = .{
                        .compute_shader = true,
                        .fragment_shader = true,
                    },
                    .source_access_mask = .{
                        .shader_storage_read = true,
                        .shader_storage_write = true,
                        .shader_sampled_read = true,
                    },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .general,
                    .image = &tone_map.images[0],
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .base_level = 0,
                        .levels = 1,
                        .base_layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{
                        .compute_shader = true,
                        .fragment_shader = true,
                    },
                    .source_access_mask = .{
                        .shader_storage_read = true,
                        .shader_storage_write = true,
                        .shader_sampled_read = true,
                    },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .general,
                    .image = &tone_map.images[1],
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .base_level = 0,
                        .levels = 1,
                        .base_layer = 0,
                        .layers = 1,
                    },
                },
            },
            .by_region = false,
        }});
        cmd.setPipeline(&pl.compute.tm);
        cmd.dispatch(ToneMap.widths[0], ToneMap.heights[0], 1);

        // Remaining tone map downsamples
        for (ToneMap.downsamples[1..ToneMap.downsamples.len], 0..) |size, i| {
            cmd.pipelineBarrier(&.{.{
                .image_dependencies = &.{
                    .{
                        .source_stage_mask = .{ .compute_shader = true },
                        .source_access_mask = .{ .shader_storage_write = true },
                        .dest_stage_mask = .{ .compute_shader = true },
                        .dest_access_mask = .{ .shader_storage_read = true },
                        .queue_transfer = null,
                        .old_layout = .general,
                        .new_layout = .general,
                        .image = &tone_map.images[i & 1],
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .base_level = 0,
                            .levels = 1,
                            .base_layer = 0,
                            .layers = 1,
                        },
                    },
                    .{
                        .source_stage_mask = .{ .compute_shader = true },
                        .source_access_mask = .{ .shader_storage_read = true },
                        .dest_stage_mask = .{ .compute_shader = true },
                        .dest_access_mask = .{ .shader_storage_write = true },
                        .queue_transfer = null,
                        .old_layout = .general,
                        .new_layout = .general,
                        .image = &tone_map.images[@intFromBool(i & 1 == 0)],
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .base_level = 0,
                            .levels = 1,
                            .base_layer = 0,
                            .layers = 1,
                        },
                    },
                },
                .by_region = false,
            }});
            cmd.setPipeline(&pl.compute.tm_rw[i]);
            cmd.dispatch(size[0], size[1], 1);
        }

        // Last render pass
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .shader_read_only_optimal,
                    .image = &bloom_map.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .base_level = 0,
                        .levels = 1,
                        .base_layer = BloomMap.sampled_index,
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
                    .image = &tone_map.images[ToneMap.sampled_index],
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .base_level = 0,
                        .levels = 1,
                        .base_layer = 0,
                        .layers = 1,
                    },
                },
            },
            .by_region = false,
        }});
        cmd.beginRenderPass(
            .{
                .render_pass = &pass.last.render_pass,
                .frame_buffer = &pass.last.frame_buffers[next],
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = Platform.width,
                    .height = Platform.height,
                },
                .clear_values = &.{null},
            },
            .{ .contents = .inline_only },
        );
        drawTriangle(&cmd, &pl, &vert_buf, vert_buf_size - @sizeOf(@TypeOf(triangle.data)));
        cmd.endRenderPass(.{});

        if (!is_unified) @panic("TODO");
        try cmd.end();

        ctx.lockQueue(queue.index);
        defer ctx.unlockQueue(queue.index);

        try dev.queues[queue.index].submit(gpa, dev, fence, &.{.{
            .commands = &.{.{ .command_buffer = cmd_buf }},
            .wait = &.{.{
                .semaphore = semas[0],
                .stage_mask = .{ .color_attachment_output = true },
            }},
            .signal = &.{.{
                .semaphore = semas[1],
                .stage_mask = .{ .color_attachment_output = true },
            }},
        }});

        var pres_sema: *ngl.Semaphore = undefined;
        var pres_queue: *ngl.Queue = undefined;
        if (is_unified) {
            pres_sema = semas[1];
            pres_queue = &dev.queues[queue.index];
        } else @panic("TODO");

        try pres_queue.present(gpa, dev, &.{pres_sema}, &.{.{
            .swap_chain = &plat.swap_chain,
            .image_index = next,
        }});

        frame = (frame + 1) % frame_n;
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 3, blk: {
        var fences: [frame_n]*ngl.Fence = undefined;
        for (0..fences.len) |i| fences[i] = &queue.fences[i];
        break :blk &fences;
    });
}

const triangle = struct {
    const vertex_count = 3;
    const topology = ngl.Primitive.Topology.triangle_list;
    const clockwise = true;

    const data: struct {
        position: [9]f32 = .{
            -1, -1, 0,
            3,  -1, 0,
            -1, 3,  0,
        },
        tex_coord: [6]f32 = .{
            0, 0,
            2, 0,
            0, 2,
        },
    } = .{};
};

fn drawTriangle(
    cmd: *ngl.Cmd,
    pipeline: *Pipeline,
    vertex_buffer: *Buffer(.device),
    vertex_offset: u64,
) void {
    cmd.setPipeline(&pipeline.graphics.last);
    const D = @TypeOf(triangle.data);
    const P = @TypeOf(triangle.data.position);
    const T = @TypeOf(triangle.data.tex_coord);
    cmd.setVertexBuffers(
        0,
        &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 2,
        &.{ vertex_offset + @offsetOf(D, "position"), vertex_offset + @offsetOf(D, "tex_coord") },
        &.{ @sizeOf(P), @sizeOf(T) },
    );
    cmd.draw(triangle.vertex_count, 1, 0, 0);
}

fn Renderable(comptime _: enum { model, plane }) type {
    return struct {
        index: usize,
        mvp: [16]f32,
        mv: [16]f32,
        n: [12]f32,
        base_color: [3]f32,
        metallic: f32,
        roughness: f32,
        reflectance: f32,

        fn init(
            index: usize,
            m: [16]f32,
            v: [16]f32,
            p: [16]f32,
            base_color: [3]f32,
            metallic: f32,
            roughness: f32,
            reflectance: f32,
        ) @This() {
            const mvp = util.mulM(4, util.mulM(4, p, v), m);
            const mv = util.mulM(4, v, m);
            const n = blk: {
                const n = util.invert3(util.upperLeft(4, mv));
                break :blk [12]f32{
                    n[0], n[3], n[6], undefined,
                    n[1], n[4], n[7], undefined,
                    n[2], n[5], n[8], undefined,
                };
            };
            return .{
                .index = index,
                .mvp = mvp,
                .mv = mv,
                .n = n,
                .base_color = base_color,
                .metallic = metallic,
                .roughness = roughness,
                .reflectance = reflectance,
            };
        }

        fn copy(self: @This(), frame: usize, uniform_buffer: *Buffer(.host)) void {
            const off = 256 + frame * (1 + 2 * draw_n) * 256 + self.index * 512;
            const dest = uniform_buffer.data[off..];

            @memcpy(dest[0..64], @as([*]const u8, @ptrCast(&self.mvp))[0..64]);
            @memcpy(dest[64..128], @as([*]const u8, @ptrCast(&self.mv))[0..64]);
            @memcpy(dest[128..176], @as([*]const u8, @ptrCast(&self.n))[0..48]);

            @memcpy(dest[256..280], @as([*]const u8, @ptrCast(&self.base_color ++ [_]f32{
                self.metallic,
                self.roughness,
                self.reflectance,
            }))[0..24]);
        }
    };
}

fn drawRenderables(
    frame: usize,
    cmd: *ngl.Cmd,
    pipeline: *Pipeline,
    descriptor: *Descriptor,
    vertex_buffer: *Buffer(.device),
    model_data: model.Model,
    models: []const Renderable(.model),
    planes: []const Renderable(.plane),
) void {
    const sets = descriptor.sets[1 + frame * (1 + draw_n) ..];

    if (models.len > 0) {
        cmd.setPipeline(&pipeline.graphics.first[0]);
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 2,
            &.{ 0, model_data.positionSize() },
            &.{ model_data.positionSize(), model_data.normalSize() },
        );
        for (models) |mdl| {
            cmd.setDescriptors(.graphics, &descriptor.pipeline_layout, 1, &.{&sets[mdl.index]});
            cmd.draw(model_data.vertexCount(), 1, 0, 0);
        }
    }

    if (planes.len > 0) {
        cmd.setPipeline(&pipeline.graphics.first[1]);
        const vert_off = model_data.vertexSize();
        const D = @TypeOf(model.plane.data);
        const P = @TypeOf(model.plane.data.position);
        const N = @TypeOf(model.plane.data.normal);
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 2,
            &.{ vert_off + @offsetOf(D, "position"), vert_off + @offsetOf(D, "normal") },
            &.{ @sizeOf(P), @sizeOf(N) },
        );
        for (planes) |plane| {
            cmd.setDescriptors(.graphics, &descriptor.pipeline_layout, 1, &.{&sets[plane.index]});
            cmd.draw(model.plane.vertex_count, 1, 0, 0);
        }
    }
}

const Light = struct {
    position: [3]f32,
    color: [3]f32,
    intensity: f32,

    fn init(world_pos: [3]f32, v: [16]f32, color: [3]f32, intensity: f32) @This() {
        const v_pos = util.mulMV(4, v, world_pos ++ [_]f32{1})[0..3].*;
        return .{
            .position = v_pos,
            .color = color,
            .intensity = intensity,
        };
    }

    fn copy(frame: usize, uniform_buffer: *Buffer(.host), lights: []const Light) void {
        if (lights.len * 32 > 256)
            @panic("Too many lights");

        const off = frame * (1 + 2 * draw_n) * 256;
        var dest = uniform_buffer.data[off..];

        for (lights) |light| {
            @memcpy(dest[0..12], @as([*]const u8, @ptrCast(&light.position))[0..12]);
            @memcpy(
                dest[16..32],
                @as([*]const u8, @ptrCast(&light.color ++ [_]f32{light.intensity}))[0..16],
            );
            dest = dest[32..];
        }
    }
};

const Queue = struct {
    // Graphics/compute
    index: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
    // Signaled
    fences: [frame_n]ngl.Fence,
    non_unified: ?struct {
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        semaphores: [frame_n]ngl.Semaphore,
    },

    fn init() ngl.Error!Queue {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const pres = plat.queue_index;
        const gc = if (dev.queues[pres].capabilities.graphics and
            dev.queues[pres].capabilities.compute)
            pres
        else
            dev.findQueue(.{ .graphics = true, .compute = true }, null) orelse @panic("TODO");

        var non_unified: @TypeOf((try init()).non_unified) = blk: {
            if (gc == pres) break :blk null;

            var pools: [frame_n]ngl.CommandPool = undefined;
            for (&pools, 0..) |*pool, i|
                pool.* = ngl.CommandPool.init(
                    gpa,
                    dev,
                    .{ .queue = &dev.queues[pres] },
                ) catch |err| {
                    for (0..i) |j| pools[j].deinit(gpa, dev);
                    return err;
                };
            errdefer for (&pools) |*pool| pool.deinit(gpa, dev);
            var bufs: [frame_n]ngl.CommandBuffer = undefined;
            for (&bufs, &pools) |*buf, *pool| {
                const s = try pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
                buf.* = s[0];
                gpa.free(s);
            }

            var semas: [frame_n]ngl.Semaphore = undefined;
            for (&semas, 0..) |*sema, i|
                sema.* = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
                    for (0..i) |j| semas[j].deinit(gpa, dev);
                    return err;
                };

            break :blk .{
                .pools = pools,
                .buffers = bufs,
                .semaphores = semas,
            };
        };
        errdefer if (non_unified) |*x| {
            for (&x.pools) |*pool| pool.deinit(gpa, dev);
            for (&x.semaphores) |*sema| sema.deinit(gpa, dev);
        };

        var pools: [frame_n]ngl.CommandPool = undefined;
        for (&pools, 0..) |*pool, i|
            pool.* = ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[gc] }) catch |err| {
                for (0..i) |j| pools[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&pools) |*pool| pool.deinit(gpa, dev);
        var bufs: [frame_n]ngl.CommandBuffer = undefined;
        for (&bufs, &pools) |*buf, *pool| {
            const s = try pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
            buf.* = s[0];
            gpa.free(s);
        }

        var semas: [frame_n * 2]ngl.Semaphore = undefined;
        for (&semas, 0..) |*sema, i|
            sema.* = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
                for (0..i) |j| semas[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&semas) |*sema| sema.deinit(gpa, dev);

        var fences: [frame_n]ngl.Fence = undefined;
        for (&fences, 0..) |*fence, i|
            fence.* = ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled }) catch |err| {
                for (0..i) |j| fences[j].deinit(gpa, dev);
                return err;
            };

        return .{
            .index = gc,
            .pools = pools,
            .buffers = bufs,
            .semaphores = semas,
            .fences = fences,
            .non_unified = non_unified,
        };
    }

    fn deinit(self: *Queue) void {
        const dev = &context().device;
        for (&self.pools) |*pool| pool.deinit(gpa, dev);
        for (&self.semaphores) |*sema| sema.deinit(gpa, dev);
        for (&self.fences) |*fence| fence.deinit(gpa, dev);
        if (self.non_unified) |*x| {
            for (&x.pools) |*pool| pool.deinit(gpa, dev);
            for (&x.semaphores) |*sema| sema.deinit(gpa, dev);
        }
    }
};

fn Buffer(comptime domain: enum { device, host }) type {
    return struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,
        data: if (domain == .device) void else []u8,

        fn init(size: u64, usage: ngl.Buffer.Usage) ngl.Error!@This() {
            const dev = &context().device;

            var buf = try ngl.Buffer.init(gpa, dev, .{ .size = size, .usage = usage });
            var mem = blk: {
                errdefer buf.deinit(gpa, dev);
                const mem_reqs = buf.getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(dev.*, if (domain == .device) .{
                        .device_local = true,
                    } else .{
                        .host_visible = true,
                        .host_coherent = true,
                    }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try buf.bind(dev, &mem, 0);
                break :blk mem;
            };
            const data = if (domain == .device) {} else (mem.map(dev, 0, size) catch |err| {
                buf.deinit(gpa, dev);
                dev.free(gpa, &mem);
                return err;
            })[0..size];

            return .{
                .buffer = buf,
                .memory = mem,
                .data = data,
            };
        }

        fn deinit(self: *@This()) void {
            const dev = &context().device;
            self.buffer.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
        }
    };
}

const HdrMap = struct {
    images: [2]ngl.Image,
    memories: [2]ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    const ms = 0;
    const resolve = 1;

    const format = ngl.Format.rgba16_sfloat;
    const samples = ngl.SampleCount.@"4";

    fn init() ngl.Error!HdrMap {
        const dev = &context().device;

        var imgs: [2]ngl.Image = undefined;
        var mems: [2]ngl.Memory = undefined;
        var views: [2]ngl.ImageView = undefined;

        const params: [2]struct {
            samples: ngl.SampleCount,
            usage: ngl.Image.Usage,
        } = .{
            .{
                .samples = samples,
                .usage = .{ .color_attachment = true, .transient_attachment = true },
            },
            .{
                .samples = .@"1",
                .usage = .{ .sampled_image = true, .color_attachment = true },
            },
        };

        for (params, 0..) |param, i| {
            errdefer for (0..i) |j| {
                views[j].deinit(gpa, dev);
                imgs[j].deinit(gpa, dev);
                dev.free(gpa, &mems[j]);
            };

            imgs[i] = try ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = format,
                .width = Platform.width,
                .height = Platform.height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = param.samples,
                .tiling = .optimal,
                .usage = param.usage,
                .misc = .{},
                .initial_layout = .unknown,
            });

            mems[i] = blk: {
                errdefer imgs[i].deinit(gpa, dev);
                const mem_reqs = imgs[i].getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(dev.*, .{
                        .device_local = true,
                        .lazily_allocated = param.usage.transient_attachment,
                    }, null) orelse mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try imgs[i].bind(dev, &mem, 0);
                break :blk mem;
            };
            errdefer {
                imgs[i].deinit(gpa, dev);
                dev.free(gpa, &mems[i]);
            }

            views[i] = try ngl.ImageView.init(gpa, dev, .{
                .image = &imgs[i],
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            });
        }

        const splr = ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .clamp_to_edge,
            .v_address = .clamp_to_edge,
            .w_address = .clamp_to_edge,
            .border_color = null,
            .mag = .nearest,
            .min = .nearest,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        }) catch |err| {
            for (&views, &imgs, &mems) |*view, *image, *mem| {
                view.deinit(gpa, dev);
                image.deinit(gpa, dev);
                dev.free(gpa, mem);
            }
            return err;
        };

        return .{
            .images = imgs,
            .memories = mems,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *HdrMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        for (&self.views) |*view| view.deinit(gpa, dev);
        for (&self.images) |*image| image.deinit(gpa, dev);
        for (&self.memories) |*mem| dev.free(gpa, mem);
    }
};

const BloomMap = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    const format = HdrMap.format;
    const width = Platform.width / 8;
    const height = Platform.height / 8;
    const threshold = 1;
    const sampled_index = 0;

    fn init() ngl.Error!BloomMap {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = width,
            .height = height,
            .depth_or_layers = 2,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .sampled_image = true, .storage_image = true },
            .misc = .{},
            .initial_layout = .unknown,
        });
        var mem = blk: {
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
        errdefer {
            image.deinit(gpa, dev);
            dev.free(gpa, &mem);
        }

        var views: [2]ngl.ImageView = undefined;
        for (&views, 0..) |*view, i|
            view.* = ngl.ImageView.init(gpa, dev, .{
                .image = &image,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = @intCast(i),
                    .layers = 1,
                },
            }) catch |err| {
                for (0..i) |j| views[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&views) |*view| view.deinit(gpa, dev);

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
            .image = image,
            .memory = mem,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *BloomMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        for (&self.views) |*view| view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const ToneMap = struct {
    images: [2]ngl.Image,
    memories: [2]ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.r32_sfloat;
    const widths = .{ @max(1, Platform.width / 2), @max(1, Platform.width / 2 / 2) };
    const heights = .{ @max(1, Platform.height / 2), @max(1, Platform.height / 2 / 2) };
    const downsamples = blk: {
        var sizes: []const [2]u32 = &.{.{ widths[0], heights[0] }};
        var w: u32 = widths[0];
        var h: u32 = heights[0];
        while (w > 1 or h > 1) {
            w = @max(1, w / 2);
            h = @max(1, h / 2);
            sizes = sizes ++ &[_][2]u32{.{ w, h }};
        }
        break :blk sizes[0..sizes.len].*;
    };
    const sampled_index = @intFromBool(downsamples.len & 1 == 0);

    fn init() ngl.Error!ToneMap {
        const dev = &context().device;

        var imgs: [2]ngl.Image = undefined;
        var mems: [2]ngl.Memory = undefined;
        var views: [2]ngl.ImageView = undefined;

        inline for (&imgs, &mems, &views, 0..) |*image, *mem, *view, i| {
            errdefer for (0..i) |j| {
                views[j].deinit(gpa, dev);
                imgs[j].deinit(gpa, dev);
                dev.free(gpa, &mems[j]);
            };

            image.* = try ngl.Image.init(gpa, dev, .{
                .type = .@"2d",
                .format = format,
                .width = widths[i],
                .height = heights[i],
                .depth_or_layers = 1,
                .levels = 1,
                .samples = .@"1",
                .tiling = .optimal,
                .usage = .{ .sampled_image = sampled_index == i, .storage_image = true },
                .misc = .{},
                .initial_layout = .unknown,
            });

            mem.* = blk: {
                errdefer image.deinit(gpa, dev);
                const mem_reqs = image.getMemoryRequirements(dev);
                var m = try dev.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &m);
                try image.bind(dev, &m, 0);
                break :blk m;
            };

            view.* = ngl.ImageView.init(gpa, dev, .{
                .image = image,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            }) catch |err| {
                image.deinit(gpa, dev);
                dev.free(gpa, mem);
                return err;
            };
        }

        const splr = ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .clamp_to_edge,
            .v_address = .clamp_to_edge,
            .w_address = .clamp_to_edge,
            .border_color = null,
            .mag = .nearest,
            .min = .nearest,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        }) catch |err| {
            for (&views) |*view| view.deinit(gpa, dev);
            for (&imgs) |*image| image.deinit(gpa, dev);
            for (&mems) |*mem| dev.free(gpa, mem);
            return err;
        };

        return .{
            .images = imgs,
            .memories = mems,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *ToneMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        for (&self.views) |*view| view.deinit(gpa, dev);
        for (&self.images) |*image| image.deinit(gpa, dev);
        for (&self.memories) |*mem| dev.free(gpa, mem);
    }
};

const DepthMap = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init() ngl.Error!DepthMap {
        const dev = &context().device;

        const @"type" = ngl.Image.Type.@"2d";
        const tiling = ngl.Image.Tiling.optimal;
        const usage = ngl.Image.Usage{
            .depth_stencil_attachment = true,
            .transient_attachment = true,
        };
        const misc = ngl.Image.Misc{};

        const fmt = for ([_]ngl.Format{
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            .x8_d24_unorm,
            .d24_unorm_s8_uint,
            .d16_unorm,
            .d16_unorm_s8_uint,
        }) |fmt| {
            const capabs = ngl.Image.getCapabilities(
                dev,
                @"type",
                fmt,
                tiling,
                usage,
                misc,
            ) catch |err| {
                if (err == ngl.Error.NotSupported) continue else return err;
            };
            const U = @typeInfo(ngl.SampleCount.Flags).Struct.backing_integer.?;
            const mask: U = @bitCast(capabs.sample_counts);
            const flag = 1 << @intFromEnum(HdrMap.samples);
            if (mask & flag != 0) break fmt;
        } else @panic("MS mismatch");

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = Platform.width,
            .height = Platform.height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = HdrMap.samples,
            .tiling = tiling,
            .usage = usage,
            .misc = misc,
            .initial_layout = .unknown,
        });
        var mem = blk: {
            errdefer image.deinit(gpa, dev);
            const mem_reqs = image.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{
                    .device_local = true,
                    .lazily_allocated = true,
                }, null) orelse mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try image.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer {
            image.deinit(gpa, dev);
            dev.free(gpa, &mem);
        }
        const view = try ngl.ImageView.init(gpa, dev, .{
            .image = &image,
            .type = .@"2d",
            .format = fmt,
            .range = .{
                .aspect_mask = .{ .depth = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        });

        return .{
            .format = fmt,
            .image = image,
            .memory = mem,
            .view = view,
        };
    }

    fn deinit(self: *DepthMap) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const Descriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [(1 + draw_n) * frame_n]ngl.DescriptorSet,

    fn init(hdr_map: *HdrMap, bloom_map: *BloomMap, tone_map: *ToneMap) ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                // HDR texture/sampler (resolved)
                .{
                    .binding = 0,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&hdr_map.sampler},
                },
                // Bloom image (layer 0)
                .{
                    .binding = 1,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Bloom image (layer 1)
                .{
                    .binding = 2,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Bloom texture/sampler (layer 0)
                .{
                    .binding = 3,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&bloom_map.sampler},
                },
                // Tone map image (index 0)
                .{
                    .binding = 4,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Tone map image (index 1)
                .{
                    .binding = 5,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Tone map texture/sampler (index 0 or 1)
                .{
                    .binding = 6,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&tone_map.sampler},
                },
                // Light uniforms
                .{
                    .binding = 7,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);
        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                // Global uniforms
                .{
                    .binding = 0,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .vertex = true },
                    .immutable_samplers = null,
                },
                // Material uniforms
                .{
                    .binding = 1,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{ &set_layt, &set_layt_2 },
            .push_constant_ranges = null,
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = (1 + draw_n) * frame_n,
            .pool_size = .{
                .combined_image_sampler = 3 * frame_n,
                .storage_image = 4 * frame_n,
                .uniform_buffer = (1 + 2 * draw_n) * frame_n,
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = blk: {
            const @"0" = [1]*ngl.DescriptorSetLayout{&set_layt};
            const @"1" = [1]*ngl.DescriptorSetLayout{&set_layt_2};
            const s = try pool.alloc(
                gpa,
                dev,
                .{ .layouts = &(@"0" ++ @"1" ** draw_n) ** frame_n },
            );
            defer gpa.free(s);
            break :blk s[0 .. (1 + draw_n) * frame_n].*;
        };

        return .{
            .set_layouts = .{ set_layt, set_layt_2 },
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn write(
        self: *Descriptor,
        frame: usize,
        hdr_map: *HdrMap,
        bloom_map: *BloomMap,
        tone_map: *ToneMap,
        uniform_buffer: *Buffer(.host),
    ) ngl.Error!void {
        var writes: [8 + 2 * draw_n]ngl.DescriptorSet.Write = undefined;
        var buf_w: [2 * draw_n]ngl.DescriptorSet.Write.BufferWrite = undefined;
        const sets = self.sets[frame * (1 + draw_n) ..];
        const off = frame * (1 + 2 * draw_n) * 256;

        writes[0] = .{
            .descriptor_set = &sets[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &hdr_map.views[HdrMap.resolve],
                .layout = .shader_read_only_optimal,
                .sampler = null,
            }} },
        };
        writes[1] = .{
            .descriptor_set = &sets[0],
            .binding = 1,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &bloom_map.views[0],
                .layout = .general,
            }} },
        };
        writes[2] = .{
            .descriptor_set = &sets[0],
            .binding = 2,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &bloom_map.views[1],
                .layout = .general,
            }} },
        };
        writes[3] = .{
            .descriptor_set = &sets[0],
            .binding = 3,
            .element = 0,
            .contents = .{
                .combined_image_sampler = &.{.{
                    .view = &bloom_map.views[BloomMap.sampled_index],
                    .layout = .shader_read_only_optimal,
                    .sampler = null,
                }},
            },
        };
        writes[4] = .{
            .descriptor_set = &sets[0],
            .binding = 4,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &tone_map.views[0],
                .layout = .general,
            }} },
        };
        writes[5] = .{
            .descriptor_set = &sets[0],
            .binding = 5,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &tone_map.views[1],
                .layout = .general,
            }} },
        };
        writes[6] = .{
            .descriptor_set = &sets[0],
            .binding = 6,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &tone_map.views[ToneMap.sampled_index],
                .layout = .shader_read_only_optimal,
                .sampler = null,
            }} },
        };
        writes[7] = .{
            .descriptor_set = &sets[0],
            .binding = 7,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &uniform_buffer.buffer,
                .offset = off,
                .range = 256,
            }} },
        };

        for (0..draw_n) |i| {
            buf_w[i * 2] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = off + 256 + i * 2 * 256,
                .range = 256,
            };
            buf_w[i * 2 + 1] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = off + 256 + (i * 2 + 1) * 256,
                .range = 256,
            };
            writes[8 + i * 2] = .{
                .descriptor_set = &sets[1 + i],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i * 2 .. i * 2 + 1] },
            };
            writes[8 + i * 2 + 1] = .{
                .descriptor_set = &sets[1 + i],
                .binding = 1,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i * 2 + 1 .. i * 2 + 2] },
            };
        }

        try ngl.DescriptorSet.write(gpa, &context().device, &writes);
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        self.pool.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        for (&self.set_layouts) |*layt| layt.deinit(gpa, dev);
    }
};

const Pass = struct {
    first: struct {
        render_pass: ngl.RenderPass,
        frame_buffer: ngl.FrameBuffer,
    },
    last: struct {
        render_pass: ngl.RenderPass,
        frame_buffers: []ngl.FrameBuffer,
    },

    fn init(hdr_map: *HdrMap, depth_map: *DepthMap) ngl.Error!Pass {
        var self: Pass = undefined;
        try self.initFirst(hdr_map, depth_map);
        self.initLast() catch |err| {
            const dev = &context().device;
            self.first.frame_buffer.deinit(gpa, dev);
            self.first.render_pass.deinit(gpa, dev);
            return err;
        };
        return self;
    }

    fn initFirst(self: *Pass, hdr_map: *HdrMap, depth_map: *DepthMap) ngl.Error!void {
        const dev = &context().device;

        const attachs = [_]ngl.RenderPass.Attachment{
            .{
                .format = HdrMap.format,
                .samples = HdrMap.samples,
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .unknown,
                .final_layout = .color_attachment_optimal,
                .resolve_mode = .average,
                .combined = null,
                .may_alias = false,
            },
            .{
                .format = depth_map.format,
                .samples = HdrMap.samples,
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .unknown,
                .final_layout = .depth_stencil_attachment_optimal,
                .resolve_mode = null,
                .combined = if (depth_map.format.getAspectMask().stencil) .{
                    .stencil_load_op = .dont_care,
                    .stencil_store_op = .dont_care,
                } else null,
                .may_alias = false,
            },
            .{
                .format = HdrMap.format,
                .samples = .@"1",
                .load_op = .dont_care,
                .store_op = .store,
                .initial_layout = .unknown,
                .final_layout = .shader_read_only_optimal,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
        };

        const subp = ngl.RenderPass.Subpass{
            .pipeline_type = .graphics,
            .input_attachments = null,
            .color_attachments = &.{.{
                .index = 0,
                .layout = .color_attachment_optimal,
                .aspect_mask = .{ .color = true },
                .resolve = .{ .index = 2, .layout = .color_attachment_optimal },
            }},
            .depth_stencil_attachment = .{
                .index = 1,
                .layout = .depth_stencil_attachment_optimal,
                .aspect_mask = .{ .depth = true },
                .resolve = null,
            },
            .preserve_attachments = null,
        };

        const depends = [_]ngl.RenderPass.Dependency{
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .source_stage_mask = .{
                    .fragment_shader = true,
                    .late_fragment_tests = true,
                },
                .source_access_mask = .{
                    .shader_sampled_read = true,
                    .depth_stencil_attachment_write = true,
                },
                .dest_stage_mask = .{
                    .early_fragment_tests = true,
                    .color_attachment_output = true,
                },
                .dest_access_mask = .{
                    .depth_stencil_attachment_read = true,
                    .depth_stencil_attachment_write = true,
                    .color_attachment_write = true,
                },
                .by_region = false,
            },
            .{
                .source_subpass = .{ .index = 0 },
                .dest_subpass = .external,
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_sampled_read = true },
                .by_region = false,
            },
        };

        self.first.render_pass = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &attachs,
            .subpasses = &.{subp},
            .dependencies = &depends,
        });
        errdefer self.first.render_pass.deinit(gpa, dev);

        self.first.frame_buffer = try ngl.FrameBuffer.init(gpa, dev, .{
            .render_pass = &self.first.render_pass,
            .attachments = &.{
                &hdr_map.views[HdrMap.ms],
                &depth_map.view,
                &hdr_map.views[HdrMap.resolve],
            },
            .width = Platform.width,
            .height = Platform.height,
            .layers = 1,
        });
    }

    fn initLast(self: *Pass) ngl.Error!void {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const attach = ngl.RenderPass.Attachment{
            .format = plat.format.format,
            .samples = .@"1",
            .load_op = .dont_care,
            .store_op = .store,
            .initial_layout = .unknown,
            .final_layout = .present_source,
            .resolve_mode = null,
            .combined = null,
            .may_alias = false,
        };

        const subp = ngl.RenderPass.Subpass{
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
        };

        const depends = [_]ngl.RenderPass.Dependency{
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{
                    .fragment_shader = true,
                    .color_attachment_output = true,
                },
                .dest_access_mask = .{
                    .shader_sampled_read = true,
                    .color_attachment_write = true,
                },
                .by_region = false,
            },
            .{
                .source_subpass = .{ .index = 0 },
                .dest_subpass = .external,
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .color_attachment_output = true },
                .dest_access_mask = .{},
                .by_region = false,
            },
        };

        self.last.render_pass = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{attach},
            .subpasses = &.{subp},
            .dependencies = &depends,
        });
        errdefer self.last.render_pass.deinit(gpa, dev);

        self.last.frame_buffers = try gpa.alloc(ngl.FrameBuffer, plat.images.len);
        errdefer gpa.free(self.last.frame_buffers);
        for (self.last.frame_buffers, plat.image_views, 0..) |*fb, *sc_view, i|
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &self.last.render_pass,
                .attachments = &.{sc_view},
                .width = Platform.width,
                .height = Platform.height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| self.last.frame_buffers[j].deinit(gpa, dev);
                return err;
            };
    }

    fn deinit(self: *Pass) void {
        const dev = &context().device;
        self.first.frame_buffer.deinit(gpa, dev);
        self.first.render_pass.deinit(gpa, dev);
        for (self.last.frame_buffers) |*fb| fb.deinit(gpa, dev);
        self.last.render_pass.deinit(gpa, dev);
    }
};

const Pipeline = struct {
    graphics: struct {
        first: [2]ngl.Pipeline,
        last: ngl.Pipeline,
    },
    compute: struct {
        bloom: ngl.Pipeline,
        blur: [2]ngl.Pipeline,
        tm: ngl.Pipeline,
        tm_rw: [ToneMap.downsamples.len - 1]ngl.Pipeline,
    },

    const first_vert_spv align(4) = @embedFile("shader/hdr/first.vert.spv").*;
    const first_frag_spv align(4) = @embedFile("shader/hdr/first.frag.spv").*;
    const last_vert_spv align(4) = @embedFile("shader/hdr/last.vert.spv").*;
    const last_frag_spv align(4) = @embedFile("shader/hdr/last.frag.spv").*;
    const bloom_comp_spv align(4) = @embedFile("shader/hdr/bloom.comp.spv").*;
    const blur_comp_spv align(4) = @embedFile("shader/hdr/blur.comp.spv").*;
    const blur_2_comp_spv align(4) = @embedFile("shader/hdr/blur_2.comp.spv").*;
    const tm_comp_spv align(4) = @embedFile("shader/hdr/tm.comp.spv").*;
    const tm_r0w1_comp_spv align(4) = @embedFile("shader/hdr/tm_r0w1.comp.spv").*;
    const tm_r1w0_comp_spv align(4) = @embedFile("shader/hdr/tm_r1w0.comp.spv").*;

    fn init(descriptor: *Descriptor, pass: *Pass) ngl.Error!Pipeline {
        var self: Pipeline = undefined;
        try self.initGraphics(descriptor, pass);
        self.initCompute(descriptor) catch |err| {
            const dev = &context().device;
            for (&self.graphics.first) |*pl| pl.deinit(gpa, dev);
            self.graphics.last.deinit(gpa, dev);
            return err;
        };
        return self;
    }

    fn initGraphics(self: *Pipeline, descriptor: *Descriptor, pass: *Pass) ngl.Error!void {
        const stages = [2 + 2]ngl.ShaderStage.Desc{
            .{
                .stage = .vertex,
                .code = &first_vert_spv,
                .name = "main",
            },
            .{
                .stage = .fragment,
                .code = &first_frag_spv,
                .name = "main",
            },
            .{
                .stage = .vertex,
                .code = &last_vert_spv,
                .name = "main",
            },
            .{
                .stage = .fragment,
                .code = &last_frag_spv,
                .name = "main",
            },
        };

        const prims = [2 + 1]ngl.Primitive{
            .{
                .bindings = &.{
                    .{
                        .binding = 0,
                        .stride = 12,
                        .step_rate = .vertex,
                    },
                    .{
                        .binding = 1,
                        .stride = 12,
                        .step_rate = .vertex,
                    },
                },
                .attributes = &.{
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
                },
                .topology = .triangle_list,
            },
            .{
                .bindings = &.{
                    .{
                        .binding = 0,
                        .stride = 12,
                        .step_rate = .vertex,
                    },
                    .{
                        .binding = 1,
                        .stride = 12,
                        .step_rate = .vertex,
                    },
                },
                .attributes = &.{
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
                },
                .topology = model.plane.topology,
            },
            .{
                .bindings = &.{
                    .{
                        .binding = 0,
                        .stride = 12,
                        .step_rate = .vertex,
                    },
                    .{
                        .binding = 1,
                        .stride = 8,
                        .step_rate = .vertex,
                    },
                },
                .attributes = &.{
                    .{
                        .location = 0,
                        .binding = 0,
                        .format = .rgb32_sfloat,
                        .offset = 0,
                    },
                    .{
                        .location = 1,
                        .binding = 1,
                        .format = .rg32_sfloat,
                        .offset = 0,
                    },
                },
                .topology = triangle.topology,
            },
        };

        const vport = ngl.Viewport{
            .x = 0,
            .y = 0,
            .width = Platform.width,
            .height = Platform.height,
            .near = 0,
            .far = 1,
        };

        const rasters = [3]ngl.Rasterization{
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = false,
                .samples = HdrMap.samples,
            },
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = model.plane.clockwise,
                .samples = HdrMap.samples,
            },
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = triangle.clockwise,
                .samples = .@"1",
            },
        };

        const ds = ngl.DepthStencil{
            .depth_compare = .less,
            .depth_write = true,
            .stencil_front = null,
            .stencil_back = null,
        };

        const blend = ngl.ColorBlend{
            .attachments = &.{.{ .blend = null, .write = .all }},
            .constants = .unused,
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, &context().device, .{
            .states = &.{
                .{
                    .stages = stages[0..2],
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &prims[0],
                    .viewport = &vport,
                    .rasterization = &rasters[0],
                    .depth_stencil = &ds,
                    .color_blend = &blend,
                    .render_pass = &pass.first.render_pass,
                    .subpass = 0,
                },
                .{
                    .stages = stages[0..2],
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &prims[1],
                    .viewport = &vport,
                    .rasterization = &rasters[1],
                    .depth_stencil = &ds,
                    .color_blend = &blend,
                    .render_pass = &pass.first.render_pass,
                    .subpass = 0,
                },
                .{
                    .stages = stages[2..4],
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &prims[2],
                    .viewport = &vport,
                    .rasterization = &rasters[2],
                    .depth_stencil = null,
                    .color_blend = &blend,
                    .render_pass = &pass.last.render_pass,
                    .subpass = 0,
                },
            },
            .cache = null,
        });
        defer gpa.free(pls);

        self.graphics.first = pls[0..2].*;
        self.graphics.last = pls[2];
    }

    fn initCompute(self: *Pipeline, descriptor: *Descriptor) ngl.Error!void {
        var states: [1 + 2 + 1 + ToneMap.downsamples.len - 1]ngl.ComputeState = undefined;

        const bloom_spec = ngl.ShaderStage.Specialization{
            .constants = &.{
                .{
                    .id = 0,
                    .offset = 0,
                    .size = 4,
                },
                .{
                    .id = 1,
                    .offset = 4,
                    .size = 4,
                },
                .{
                    .id = 2,
                    .offset = 8,
                    .size = 4,
                },
            },
            .data = @as([*]const u8, @ptrCast(&[3]f32{
                1 / @as(f32, BloomMap.width),
                1 / @as(f32, BloomMap.height),
                BloomMap.threshold,
            }))[0..12],
        };

        states[0] = .{
            .stage = .{
                .code = &bloom_comp_spv,
                .name = "main",
                .specialization = bloom_spec,
            },
            .layout = &descriptor.pipeline_layout,
        };

        states[1] = .{
            .stage = .{ .code = &blur_comp_spv, .name = "main" },
            .layout = &descriptor.pipeline_layout,
        };
        states[2] = .{
            .stage = .{ .code = &blur_2_comp_spv, .name = "main" },
            .layout = &descriptor.pipeline_layout,
        };

        const tm_spec = ngl.ShaderStage.Specialization{
            .constants = &.{
                .{
                    .id = 0,
                    .offset = 0,
                    .size = 4,
                },
                .{
                    .id = 1,
                    .offset = 4,
                    .size = 4,
                },
            },
            .data = @as([*]const u8, @ptrCast(&[2]f32{
                1 / @as(f32, ToneMap.widths[0]),
                1 / @as(f32, ToneMap.heights[0]),
            }))[0..8],
        };

        states[3] = .{
            .stage = .{
                .code = &tm_comp_spv,
                .name = "main",
                .specialization = tm_spec,
            },
            .layout = &descriptor.pipeline_layout,
        };

        var tm_rw_specs: [ToneMap.downsamples.len - 1]ngl.ShaderStage.Specialization = undefined;
        var tm_rw_consts: [2 * tm_rw_specs.len]ngl.ShaderStage.Specialization.Constant = undefined;
        const tm_rw_data = blk: {
            var data: [2 * tm_rw_specs.len]u32 = undefined;
            for (ToneMap.downsamples[0 .. ToneMap.downsamples.len - 1], 0..) |*size, i| {
                data[i * 2] = size[0];
                data[i * 2 + 1] = size[1];
            }
            break :blk data;
        };
        for (0..tm_rw_specs.len) |i| {
            tm_rw_consts[i * 2] = .{
                .id = 0,
                .offset = @intCast(i * 8),
                .size = 4,
            };
            tm_rw_consts[i * 2 + 1] = .{
                .id = 1,
                .offset = @intCast(i * 8 + 4),
                .size = 4,
            };
            tm_rw_specs[i] = .{
                .constants = tm_rw_consts[i * 2 .. i * 2 + 2],
                .data = @as([*]const u8, @ptrCast(&tm_rw_data))[i * 8 .. i * 8 + 8],
            };
        }

        for (states[4 .. 4 + ToneMap.downsamples.len - 1], tm_rw_specs, 0..) |*state, spec, i|
            state.* = .{
                .stage = .{
                    .code = if (i & 1 == 0) &tm_r0w1_comp_spv else &tm_r1w0_comp_spv,
                    .name = "main",
                    .specialization = spec,
                },
                .layout = &descriptor.pipeline_layout,
            };

        const pls = try ngl.Pipeline.initCompute(gpa, &context().device, .{
            .states = &states,
            .cache = null,
        });
        defer gpa.free(pls);

        self.compute.bloom = pls[0];
        self.compute.blur = pls[1..3].*;
        self.compute.tm = pls[3];
        self.compute.tm_rw = pls[4 .. 4 + ToneMap.downsamples.len - 1].*;
    }

    fn deinit(self: *Pipeline) void {
        const dev = &context().device;
        for (&self.graphics.first) |*pl| pl.deinit(gpa, dev);
        self.graphics.last.deinit(gpa, dev);
        self.compute.bloom.deinit(gpa, dev);
        for (&self.compute.blur) |*pl| pl.deinit(gpa, dev);
        self.compute.tm.deinit(gpa, dev);
        for (&self.compute.tm_rw) |*pl| pl.deinit(gpa, dev);
    }
};
