const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const util = @import("util.zig");
const model = @import("model.zig");

// TODO: This needs a smoothing pass to reduce noise.

pub fn main() !void {
    try do();
}

const frame_n = 2;
const draw_n = 2;
const width = Platform.width / 2;
const height = Platform.height / 2;

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var queue = try Queue.init();
    defer queue.deinit();

    const unif_buf_size = frame_n * 3 * 256;
    var unif_buf = try Buffer(.host).init(unif_buf_size, .{ .uniform_buffer = true });
    defer unif_buf.deinit();

    var mdl = try model.loadObj(gpa, "data/geometry/teapot.obj");
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

    var norm_map = try NormalMap.init();
    defer norm_map.deinit();

    var dep_map = try DepthMap.init();
    defer dep_map.deinit();

    var col_map = try ColorMap.init();
    defer col_map.deinit();

    var desc = try Descriptor.init(&norm_map, &dep_map);
    defer desc.deinit();

    for (0..frame_n) |i|
        try desc.write(i, &norm_map, &dep_map, &col_map, &unif_buf);

    var pass = try Pass.init(&norm_map, &dep_map, &col_map);
    defer pass.deinit();

    var pl = try Pipeline.init(&desc, &pass);
    defer pl.deinit();

    {
        var dest = stg_buf.data;
        var size = mdl.positionSize();
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(mdl.positions.items.ptr))[0..size]);
        dest = dest[size..];
        size = mdl.normalSize();
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(mdl.normals.items.ptr))[0..size]);
        dest = dest[size..];
        size = mdl.texCoordSize();
        // Not used.
        dest = dest[size..];
        size = @sizeOf(@TypeOf(model.plane.data));
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(&model.plane.data))[0..size]);
        dest = dest[size..];
        size = @sizeOf(@TypeOf(triangle.data));
        @memcpy(dest[0..size], @as([*]const u8, @ptrCast(&triangle.data))[0..size]);
    }

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

    try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
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

    const m_mdl = [16]f32{
        1, 0,    0, 0,
        0, 1,    0, 0,
        0, 0,    1, 0,
        0, -1.7, 0, 1,
    };
    const m_plane = [16]f32{
        50, 0,  0,  0,
        0,  50, 0,  0,
        0,  0,  50, 0,
        0,  0,  0,  1,
    };
    const v = util.lookAt(.{ 0, -1, 0 }, .{ -1, -5, -4 }, .{ 0, -1, 0 });
    const mv_mdl = util.mulM(4, v, m_mdl);
    const mv_plane = util.mulM(4, v, m_plane);
    const n_mdl = blk: {
        const n = util.invert3(util.upperLeft(4, mv_mdl));
        break :blk [12]f32{
            n[0], n[3], n[6], undefined,
            n[1], n[4], n[7], undefined,
            n[2], n[5], n[8], undefined,
        };
    };
    const n_plane = blk: {
        const n = util.invert3(util.upperLeft(4, mv_plane));
        break :blk [12]f32{
            n[0], n[3], n[6], undefined,
            n[1], n[4], n[7], undefined,
            n[2], n[5], n[8], undefined,
        };
    };
    const p = util.perspective(std.math.pi / 3.0, @as(f32, width) / @as(f32, height), 0.01, 100);
    const inv_p = util.mulM(4, [16]f32{
        0.5, 0,   0, 0,
        0,   0.5, 0, 0,
        0,   0,   1, 0,
        0.5, 0.5, 0, 1,
    }, util.invert4(p));
    const mvp_mdl = util.mulM(4, p, mv_mdl);
    const mvp_plane = util.mulM(4, p, mv_plane);
    const ao_params: packed struct {
        scale: f32,
        bias: f32,
        intensity: f32,
    } = .{
        .scale = 1,
        .bias = 0.25,
        .intensity = 2,
    };

    for (0..frame_n) |i| {
        const off = 256 * 3 * i;
        const dest = unif_buf.data[off..];
        @memcpy(dest[0..64], @as([*]const u8, @ptrCast(&inv_p))[0..64]);
        @memcpy(dest[64..128], @as([*]const u8, @ptrCast(&v))[0..64]);
        @memcpy(dest[128..140], @as([*]const u8, @ptrCast(&ao_params))[0..12]);
        @memcpy(dest[256..320], @as([*]const u8, @ptrCast(&mvp_mdl))[0..64]);
        @memcpy(dest[320..368], @as([*]const u8, @ptrCast(&n_mdl))[0..48]);
        @memcpy(dest[512..576], @as([*]const u8, @ptrCast(&mvp_plane))[0..64]);
        @memcpy(dest[576..624], @as([*]const u8, @ptrCast(&n_plane))[0..48]);
    }

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

        const next = try plat.swapchain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
        cmd.beginRenderPass(
            .{
                .render_pass = &pass.render_pass,
                .frame_buffer = &pass.frame_buffers[next],
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                },
                .clear_values = &.{
                    null,
                    .{ .depth_stencil = .{ 1, undefined } },
                    .{ .color_f32 = .{ 0.6, 0.6, 0, 1 } },
                    null,
                },
            },
            .{ .contents = .inline_only },
        );
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

        cmd.setPipeline(&pl.pipelines[Pipeline.mdl]);
        cmd.setDescriptors(
            .graphics,
            &desc.pipeline_layout,
            1,
            &.{&desc.sets[1 + Pipeline.mdl + frame * (1 + draw_n)]},
        );
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vert_buf.buffer} ** 2,
            &.{ 0, mdl.positionSize() },
            &.{ mdl.positionSize(), mdl.normalSize() },
        );
        cmd.draw(mdl.vertexCount(), 1, 0, 0);

        cmd.setPipeline(&pl.pipelines[Pipeline.plane]);
        cmd.setDescriptors(
            .graphics,
            &desc.pipeline_layout,
            1,
            &.{&desc.sets[1 + Pipeline.plane + frame * (1 + draw_n)]},
        );
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vert_buf.buffer} ** 2,
            &.{
                mdl.vertexSize() + @offsetOf(@TypeOf(model.plane.data), "position"),
                mdl.vertexSize() + @offsetOf(@TypeOf(model.plane.data), "normal"),
            },
            &.{
                @sizeOf(@TypeOf(model.plane.data.position)),
                @sizeOf(@TypeOf(model.plane.data.normal)),
            },
        );
        cmd.draw(model.plane.vertex_count, 1, 0, 0);

        cmd.nextSubpass(.{ .contents = .inline_only }, .{});

        cmd.setPipeline(&pl.pipelines[Pipeline.tri]);
        cmd.setDescriptors(
            .graphics,
            &desc.pipeline_layout,
            0,
            &.{&desc.sets[frame * (1 + draw_n)]},
        );
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vert_buf.buffer} ** 2,
            &.{
                mdl.vertexSize() + @sizeOf(@TypeOf(model.plane.data)) +
                    @offsetOf(@TypeOf(triangle.data), "position"),
                mdl.vertexSize() + @sizeOf(@TypeOf(model.plane.data)) +
                    @offsetOf(@TypeOf(triangle.data), "tex_coord"),
            },
            &.{
                @sizeOf(@TypeOf(triangle.data.position)),
                @sizeOf(@TypeOf(triangle.data.tex_coord)),
            },
        );
        cmd.draw(triangle.vertex_count, 1, 0, 0);
        cmd.endRenderPass(.{});
        if (!is_unified) @panic("TODO");
        try cmd.end();

        try ngl.Fence.reset(gpa, dev, &.{fence});
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
            .swapchain = &plat.swapchain,
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

const Queue = struct {
    index: ngl.Queue.Index, // Graphics/compute.
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
    fences: [frame_n]ngl.Fence, // Signaled.
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

const NormalMap = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rg32_sfloat;
    const samples = ngl.SampleCount.@"4";

    fn init() ngl.Error!NormalMap {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{ .sampled_image = true, .color_attachment = true },
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

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &image,
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
        errdefer view.deinit(gpa, dev);

        const splr = try ngl.Sampler.init(gpa, dev, .{
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
        });

        return .{
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *NormalMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const DepthMap = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const samples = ngl.SampleCount.@"4";

    fn init() ngl.Error!DepthMap {
        const dev = &context().device;

        const fmt = for ([_]ngl.Format{
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            .x8_d24_unorm,
            .d24_unorm_s8_uint,
            .d16_unorm,
            .d16_unorm_s8_uint,
        }) |fmt| {
            const opt = fmt.getFeatures(dev).optimal_tiling;
            //if (opt.sampled_image_filter_linear and opt.depth_stencil_attachment)
            if (opt.sampled_image and opt.depth_stencil_attachment)
                break fmt;
        } else unreachable;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{ .sampled_image = true, .depth_stencil_attachment = true },
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

        var view = try ngl.ImageView.init(gpa, dev, .{
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
        errdefer view.deinit(gpa, dev);

        const splr = try ngl.Sampler.init(gpa, dev, .{
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
        });

        return .{
            .format = fmt,
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *DepthMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const ColorMap = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    const samples = ngl.SampleCount.@"4";

    fn init() ngl.Error!ColorMap {
        const dev = &context().device;

        const fmt = (platform() catch unreachable).format.format;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{
                .color_attachment = true,
                .transient_attachment = true,
                .input_attachment = true,
            },
            .misc = .{},
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

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &image,
            .type = .@"2d",
            .format = fmt,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        });
        errdefer view.deinit(gpa, dev);

        return .{
            .image = image,
            .memory = mem,
            .view = view,
        };
    }

    fn deinit(self: *ColorMap) void {
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
    sets: [(1 + 1 * draw_n) * frame_n]ngl.DescriptorSet,

    fn init(normal_map: *NormalMap, depth_map: *DepthMap) ngl.Error!Descriptor {
        const dev = &context().device;

        // SSAO resources.
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = 0,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&normal_map.sampler},
                },
                .{
                    .binding = 1,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&depth_map.sampler},
                },
                .{
                    .binding = 2,
                    .type = .input_attachment,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
                .{
                    .binding = 3,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);
        // Global uniforms for input pass.
        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
            .binding = 0,
            .type = .uniform_buffer,
            .count = 1,
            .stage_mask = .{ .vertex = true },
            .immutable_samplers = null,
        }} });
        errdefer set_layt_2.deinit(gpa, dev);

        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{ &set_layt, &set_layt_2 },
            .push_constant_ranges = null,
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = (1 + 1 * draw_n) * frame_n,
            .pool_size = .{
                .combined_image_sampler = 2 * frame_n,
                .uniform_buffer = (1 + 1 * draw_n) * frame_n,
                .input_attachment = frame_n,
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = blk: {
            const @"0" = [_]*ngl.DescriptorSetLayout{&set_layt};
            const @"1" = [_]*ngl.DescriptorSetLayout{&set_layt_2};
            const s = try pool.alloc(
                gpa,
                dev,
                .{ .layouts = &(@"0" ++ @"1" ** draw_n) ** frame_n },
            );
            defer gpa.free(s);
            break :blk s[0 .. (1 + 1 * draw_n) * frame_n].*;
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
        normal_map: *NormalMap,
        depth_map: *DepthMap,
        color_map: *ColorMap,
        uniform_buffer: *Buffer(.host),
    ) ngl.Error!void {
        var writes: [4 + draw_n]ngl.DescriptorSet.Write = undefined;
        const sets = self.sets[frame * (1 + draw_n) ..];
        const off = frame * (1 + draw_n) * 256;

        writes[0] = .{
            .descriptor_set = &sets[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &normal_map.view,
                .layout = .general,
                .sampler = null,
            }} },
        };
        writes[1] = .{
            .descriptor_set = &sets[0],
            .binding = 1,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &depth_map.view,
                .layout = .general,
                .sampler = null,
            }} },
        };
        writes[2] = .{
            .descriptor_set = &sets[0],
            .binding = 2,
            .element = 0,
            .contents = .{ .input_attachment = &.{.{
                .view = &color_map.view,
                .layout = .general,
            }} },
        };
        writes[3] = .{
            .descriptor_set = &sets[0],
            .binding = 3,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &uniform_buffer.buffer,
                .offset = off,
                .range = 256,
            }} },
        };

        var buf_w: [draw_n]ngl.DescriptorSet.Write.BufferWrite = undefined;
        for (0..draw_n) |i| {
            buf_w[i] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = off + 256 + i * 256,
                .range = 256,
            };
            writes[4 + i] = .{
                .descriptor_set = &sets[1 + i],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i .. i + 1] },
            };
        }

        try ngl.DescriptorSet.write(gpa, &context().device, &writes);
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        for (&self.set_layouts) |*layt| layt.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Pass = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,

    fn init(
        normal_map: *NormalMap,
        depth_map: *DepthMap,
        color_map: *ColorMap,
    ) ngl.Error!Pass {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const attachs = [_]ngl.RenderPass.Attachment{
            .{
                .format = NormalMap.format,
                .samples = NormalMap.samples,
                .load_op = .dont_care,
                .store_op = .dont_care,
                .initial_layout = .unknown,
                .final_layout = .general,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
            .{
                .format = depth_map.format,
                .samples = DepthMap.samples,
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .unknown,
                .final_layout = .general,
                .resolve_mode = null,
                .combined = if (depth_map.format.getAspectMask().stencil) .{
                    .stencil_load_op = .dont_care,
                    .stencil_store_op = .dont_care,
                } else null,
                .may_alias = false,
            },
            .{
                .format = plat.format.format,
                .samples = ColorMap.samples,
                .load_op = .clear,
                .store_op = .dont_care,
                .initial_layout = .unknown,
                .final_layout = .general,
                .resolve_mode = .average,
                .combined = null,
                .may_alias = false,
            },
            .{
                .format = plat.format.format,
                .samples = .@"1",
                .load_op = .dont_care,
                .store_op = .store,
                .initial_layout = .unknown,
                .final_layout = .present_source,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
        };

        var subps = [_]ngl.RenderPass.Subpass{
            .{
                .pipeline_type = .graphics,
                .input_attachments = null,
                .color_attachments = &.{
                    .{
                        .index = 0,
                        .layout = .general,
                        .aspect_mask = .{ .color = true },
                        .resolve = null,
                    },
                    .{
                        .index = 2,
                        .layout = .general,
                        .aspect_mask = .{ .color = true },
                        .resolve = null,
                    },
                },
                .depth_stencil_attachment = .{
                    .index = 1,
                    .layout = .general,
                    .aspect_mask = .{ .depth = true },
                    .resolve = null,
                },
                .preserve_attachments = null,
            },
            .{
                .pipeline_type = .graphics,
                .input_attachments = &.{.{
                    .index = 2,
                    .layout = .general,
                    .aspect_mask = .{ .color = true },
                    .resolve = null,
                }},
                .color_attachments = &.{.{
                    .index = 2,
                    .layout = .general,
                    .aspect_mask = .{ .color = true },
                    .resolve = .{
                        .index = 3,
                        .layout = .color_attachment_optimal,
                    },
                }},
                .depth_stencil_attachment = null,
                .preserve_attachments = &.{ 0, 1 },
            },
        };

        const depends = [_]ngl.RenderPass.Dependency{
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .source_stage_mask = .{
                    .late_fragment_tests = true,
                    .color_attachment_output = true,
                },
                .source_access_mask = .{ .depth_stencil_attachment_write = true },
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
                .dest_subpass = .{ .index = 1 },
                .source_stage_mask = .{
                    .late_fragment_tests = true,
                    .color_attachment_output = true,
                },
                .source_access_mask = .{
                    .depth_stencil_attachment_write = true,
                    .color_attachment_write = true,
                },
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
                .source_subpass = .{ .index = 1 },
                .dest_subpass = .external,
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .color_attachment_output = true },
                .dest_access_mask = .{},
                .by_region = false,
            },
        };

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &attachs,
            .subpasses = &subps,
            .dependencies = &depends,
        });
        errdefer rp.deinit(gpa, dev);

        var fbs = try gpa.alloc(ngl.FrameBuffer, plat.images.len);
        errdefer gpa.free(fbs);
        for (fbs, plat.image_views, 0..) |*fb, *sc_view, i|
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &rp,
                .attachments = &.{
                    &normal_map.view,
                    &depth_map.view,
                    &color_map.view,
                    sc_view,
                },
                .width = width,
                .height = height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| fbs[j].deinit(gpa, dev);
                return err;
            };

        return .{ .render_pass = rp, .frame_buffers = fbs };
    }

    fn deinit(self: *Pass) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        gpa.free(self.frame_buffers);
        self.render_pass.deinit(gpa, dev);
    }
};

const Pipeline = struct {
    pipelines: [3]ngl.Pipeline,

    const mdl = 0;
    const plane = 1;
    const tri = 2;

    const input_vert_spv align(4) = @embedFile("shader/ssao/input.vert.spv").*;
    const input_frag_spv align(4) = @embedFile("shader/ssao/input.frag.spv").*;
    const ssao_vert_spv align(4) = @embedFile("shader/ssao/ssao.vert.spv").*;
    const ssao_frag_spv align(4) = @embedFile("shader/ssao/ssao.frag.spv").*;

    fn init(descriptor: *Descriptor, pass: *Pass) ngl.Error!Pipeline {
        const dev = &context().device;

        const in_stages = [2]ngl.ShaderStage.Desc{
            .{
                .stage = .vertex,
                .code = &input_vert_spv,
                .name = "main",
            },
            .{
                .stage = .fragment,
                .code = &input_frag_spv,
                .name = "main",
            },
        };

        const ao_stages = [2]ngl.ShaderStage.Desc{
            .{
                .stage = .vertex,
                .code = &ssao_vert_spv,
                .name = "main",
            },
            .{
                .stage = .fragment,
                .code = &ssao_frag_spv,
                .name = "main",
            },
        };

        const in_binds = [2]ngl.Primitive.Binding{
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
        };
        const in_attribs = [2]ngl.Primitive.Attribute{
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
        };
        const in_prim = [2]ngl.Primitive{
            .{
                .bindings = &in_binds,
                .attributes = &in_attribs,
                .topology = .triangle_list,
            },
            .{
                .bindings = &in_binds,
                .attributes = &in_attribs,
                .topology = model.plane.topology,
            },
        };

        const ao_binds = [2]ngl.Primitive.Binding{
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
        };
        const ao_attribs = [2]ngl.Primitive.Attribute{
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
        };
        const ao_prim = ngl.Primitive{
            .bindings = &ao_binds,
            .attributes = &ao_attribs,
            .topology = triangle.topology,
        };

        const raster = [3]ngl.Rasterization{
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = false,
                .samples = ColorMap.samples,
            },
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = model.plane.clockwise,
                .samples = ColorMap.samples,
            },
            .{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = triangle.clockwise,
                .samples = ColorMap.samples,
            },
        };

        const in_ds = ngl.DepthStencil{
            .depth_compare = .less,
            .depth_write = true,
            .stencil_front = null,
            .stencil_back = null,
        };

        const in_blend = ngl.ColorBlend{
            .attachments = &.{
                .{ .blend = null, .write = .all },
                .{ .blend = null, .write = .all },
            },
        };

        const ao_blend = ngl.ColorBlend{
            .attachments = &.{.{ .blend = null, .write = .all }},
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{
                .{
                    .stages = &in_stages,
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &in_prim[0],
                    .rasterization = &raster[0],
                    .depth_stencil = &in_ds,
                    .color_blend = &in_blend,
                    .render_pass = &pass.render_pass,
                    .subpass = 0,
                },
                .{
                    .stages = &in_stages,
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &in_prim[1],
                    .rasterization = &raster[1],
                    .depth_stencil = &in_ds,
                    .color_blend = &in_blend,
                    .render_pass = &pass.render_pass,
                    .subpass = 0,
                },
                .{
                    .stages = &ao_stages,
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &ao_prim,
                    .rasterization = &raster[2],
                    .depth_stencil = null,
                    .color_blend = &ao_blend,
                    .render_pass = &pass.render_pass,
                    .subpass = 1,
                },
            },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{ .pipelines = pls[0..3].* };
    }

    fn deinit(self: *Pipeline) void {
        for (&self.pipelines) |*pl| pl.deinit(gpa, &context().device);
    }
};
