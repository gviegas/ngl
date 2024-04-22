const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const util = @import("util.zig");
const idata = @import("idata.zig");

// TODO: Try the technique from Valve's paper that uses
// signed distance fields rather than coverage data.

pub fn main() !void {
    try do();
}

const frame_n = 2;

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var queue = try Queue.init();
    defer queue.deinit();

    var dest: struct {
        staging_buffer: Buffer(.host) = undefined,

        pub fn get(self: *@This(), size: u64) ![]u8 {
            const sz = (size + 255 & ~@as(u64, 255)) + quad.size;
            self.staging_buffer = try Buffer(.host).init(sz, .{ .transfer_source = true });
            return self.staging_buffer.data[0..size];
        }
    } = .{};

    const tex_data = try idata.loadPng(gpa, "data/image/glyphs.png", &dest);
    if (!tex_data.format.getFeatures(dev).optimal_tiling.sampled_image_filter_linear)
        @panic("TODO");
    if (tex_data.width != tex_data.height)
        @panic("Source texture data must be square");
    if (tex_data.width < AlphaMap.width)
        @panic("Source texture data must be high-res");

    var stg_buf = dest.staging_buffer;
    defer stg_buf.deinit();

    quad.copy(&stg_buf, tex_data.data.len);

    var tex = try Texture.init(tex_data.format, tex_data.width, tex_data.height);
    defer tex.deinit();

    var alpha = try AlphaMap.init();
    defer alpha.deinit();

    var vert_buf = try Buffer(.device).init(
        quad.size,
        .{ .vertex_buffer = true, .transfer_dest = true },
    );
    defer vert_buf.deinit();

    const unif_buf_size = frame_n * 256;
    var unif_buf = try Buffer(.host).init(unif_buf_size, .{ .uniform_buffer = true });
    defer unif_buf.deinit();

    var desc = try Descriptor.init(&tex, &alpha, &unif_buf);
    defer desc.deinit();

    var gen = try Generation.init(&desc);
    defer gen.deinit();

    var rend = try Rendering.init(&desc);
    defer rend.deinit();

    var cmd = try queue.buffers[0].begin(gpa, dev, .{
        .one_time_submit = true,
        .inheritance = null,
    });
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{},
            .source_access_mask = .{},
            .dest_stage_mask = .{ .copy = true },
            .dest_access_mask = .{ .transfer_write = true },
            .queue_transfer = null,
            .old_layout = .unknown,
            .new_layout = .transfer_dest_optimal,
            .image = &tex.image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBufferToImage(&.{.{
        .buffer = &stg_buf.buffer,
        .image = &tex.image,
        .image_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .buffer_offset = 0,
            .buffer_row_length = tex_data.width,
            .buffer_image_height = tex_data.height,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = tex_data.width,
            .image_height = tex_data.height,
            .image_depth_or_layers = 1,
        }},
    }});
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{
            .{
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_sampled_read = true },
                .queue_transfer = null,
                .old_layout = .transfer_dest_optimal,
                .new_layout = .shader_read_only_optimal,
                .image = &tex.image,
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
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_storage_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .general,
                .image = &alpha.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
        },
        .by_region = false,
    }});
    cmd.setPipeline(&gen.pipeline);
    cmd.setDescriptors(.compute, &desc.pipeline_layout, 0, &.{&desc.sets[0]});
    cmd.dispatch(AlphaMap.width, AlphaMap.height, 1);
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{ .compute_shader = true },
            .source_access_mask = .{ .shader_storage_write = true },
            .dest_stage_mask = .{},
            .dest_access_mask = .{},
            .queue_transfer = null,
            .old_layout = .general,
            .new_layout = .shader_read_only_optimal,
            .image = &alpha.image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBuffer(&.{.{
        .source = &stg_buf.buffer,
        .dest = &vert_buf.buffer,
        .regions = &.{.{
            .source_offset = stg_buf.data.len - quad.size,
            .dest_offset = 0,
            .size = quad.size,
        }},
    }});
    try cmd.end();

    try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
    {
        ctx.lockQueue(queue.graph_comp);
        defer ctx.unlockQueue(queue.graph_comp);

        try dev.queues[queue.graph_comp].submit(gpa, dev, &queue.fences[0], &.{.{
            .commands = &.{.{ .command_buffer = &queue.buffers[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 10, &.{&queue.fences[0]});

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;
    var timer = try std.time.Timer.start();
    var delta = try std.time.Instant.now();
    const is_unified = queue.non_unified == null;
    const ar = @as(f32, Platform.width) / @as(f32, Platform.height);
    const vp = util.mulM(
        4,
        util.perspective(std.math.pi / 3.0, ar, 0.01, 128),
        util.lookAt(.{ 0, 0, 0 }, .{ 0, 0, -10 }, .{ 0, -1, 0 }),
    );
    var scale_dir: f32 = 1;
    var scale_fac: f32 = 0;

    while (timer.read() < std.time.ns_per_min) {
        if (plat.poll().done) break;

        const cmd_pool = &queue.pools[frame];
        const cmd_buf = &queue.buffers[frame];
        const semas = .{ &queue.semaphores[frame * 2], &queue.semaphores[frame * 2 + 1] };
        const fence = &queue.fences[frame];

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fence});

        const now = std.time.Instant.now() catch unreachable;
        const dt = now.since(delta);
        delta = now;
        scale_fac += scale_dir * 0.0666 * (@as(f32, @floatFromInt(dt)) / 1e9);
        if (scale_fac < 0 or scale_fac > 1) {
            scale_fac = @min(1, @max(0, scale_fac));
            scale_dir *= -1;
        }
        const scale = 2000.0 * @min(0.03, @max(0.0003, std.math.pow(f32, scale_fac, 6.0)));

        const m = [16]f32{
            scale, 0,     0,     0,
            0,     scale, 0,     0,
            0,     0,     scale, 0,
            0,     0,     0,     1,
        };
        const mvp = util.mulM(4, vp, m);
        @memcpy(
            unif_buf.data[frame * 256 .. frame * 256 + 64],
            @as([*]const u8, @ptrCast(&mvp))[0..64],
        );

        const next = try plat.swapchain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
        cmd.beginRenderPass(
            .{
                .render_pass = &rend.render_pass,
                .frame_buffer = &rend.frame_buffers[next],
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = Platform.width,
                    .height = Platform.height,
                },
                .clear_values = &.{.{ .color_f32 = .{ 0.6, 0.6, 0, 1 } }},
            },
            .{ .contents = .inline_only },
        );
        cmd.setPipeline(&rend.pipeline);
        cmd.setDescriptors(.graphics, &desc.pipeline_layout, 1, &.{&desc.sets[frame + 1]});
        cmd.setVertexBuffers(0, &.{&vert_buf.buffer}, &.{0}, &.{quad.size});
        cmd.setViewports(&.{.{
            .x = 0,
            .y = 0,
            .width = Platform.width,
            .height = Platform.height,
            .znear = 0,
            .zfar = 1,
        }});
        cmd.setScissorRects(&.{.{
            .x = 0,
            .y = 0,
            .width = Platform.width,
            .height = Platform.height,
        }});
        cmd.draw(quad.vertex_count, 1, 0, 0);
        cmd.endRenderPass(.{});
        if (!is_unified) @panic("TODO");
        try cmd.end();

        try ngl.Fence.reset(gpa, dev, &.{fence});

        ctx.lockQueue(queue.graph_comp);
        defer ctx.unlockQueue(queue.graph_comp);

        try dev.queues[queue.graph_comp].submit(gpa, dev, fence, &.{.{
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
            pres_queue = &dev.queues[queue.graph_comp];
        } else @panic("TODO");

        try pres_queue.present(gpa, dev, &.{pres_sema}, &.{.{
            .swapchain = &plat.swapchain,
            .image_index = next,
        }});

        frame = (frame + 1) % frame_n;
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 3, blk: {
        var fences: [frame_n]*ngl.Fence = undefined;
        for (0..frame_n) |i| fences[i] = &queue.fences[i];
        break :blk &fences;
    });
}

const Queue = struct {
    graph_comp: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
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

        var non_unified: @TypeOf((try Queue.init()).non_unified) = blk: {
            if (pres == gc)
                break :blk null;
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
            .graph_comp = gc,
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

const Texture = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    fn init(format: ngl.Format, width: u32, height: u32) ngl.Error!Texture {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .sampled_image = true, .transfer_dest = true },
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
            .mag = .nearest,
            .min = .nearest,
            .mipmap = .nearest,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        });

        return .{
            .format = format,
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *Texture) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const AlphaMap = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rgba8_unorm;
    const width = 192;
    const height = width;

    fn init() ngl.Error!AlphaMap {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
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
        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &image,
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
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *AlphaMap) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
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

const Descriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [frame_n + 1]ngl.DescriptorSet,

    fn init(
        texture: *Texture,
        alpha_map: *AlphaMap,
        uniform_buffer: *Buffer(.host),
    ) ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = 0,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = &.{&texture.sampler},
                },
                .{
                    .binding = 1,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);
        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = 0,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&alpha_map.sampler},
                },
                .{
                    .binding = 1,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .vertex = true },
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
            .max_sets = frame_n + 1,
            .pool_size = .{
                .combined_image_sampler = frame_n + 1,
                .storage_image = 1,
                .uniform_buffer = frame_n,
            },
        });
        errdefer pool.deinit(gpa, dev);
        var sets = blk: {
            const s = try pool.alloc(
                gpa,
                dev,
                .{ .layouts = &[1]*ngl.DescriptorSetLayout{&set_layt} ++
                    [_]*ngl.DescriptorSetLayout{&set_layt_2} ** frame_n },
            );
            defer gpa.free(s);
            break :blk s[0 .. frame_n + 1].*;
        };

        var writes: [2 + frame_n * 2]ngl.DescriptorSet.Write = undefined;
        // First set.
        writes[0] = .{
            .descriptor_set = &sets[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &texture.view,
                .layout = .shader_read_only_optimal,
                .sampler = null,
            }} },
        };
        writes[1] = .{
            .descriptor_set = &sets[0],
            .binding = 1,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &alpha_map.view,
                .layout = .general,
            }} },
        };
        // Remaining (per frame) sets.
        var is_wr: [frame_n]ngl.DescriptorSet.Write.ImageSamplerWrite = undefined;
        var buf_wr: [frame_n]ngl.DescriptorSet.Write.BufferWrite = undefined;
        for (0..frame_n) |i| {
            is_wr[i] = .{
                .view = &alpha_map.view,
                .layout = .shader_read_only_optimal,
                .sampler = null,
            };
            writes[2 + i * 2] = .{
                .descriptor_set = &sets[i + 1],
                .binding = 0,
                .element = 0,
                .contents = .{ .combined_image_sampler = is_wr[i .. i + 1] },
            };
            buf_wr[i] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = 256 * i,
                .range = 256,
            };
            writes[2 + i * 2 + 1] = .{
                .descriptor_set = &sets[i + 1],
                .binding = 1,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_wr[i .. i + 1] },
            };
        }
        try ngl.DescriptorSet.write(gpa, dev, &writes);

        return .{
            .set_layouts = .{ set_layt, set_layt_2 },
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        for (&self.set_layouts) |*set| set.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Generation = struct {
    pipeline: ngl.Pipeline,

    const local = [2]u32{ 1, 1 }; // TODO

    const comp_spv align(4) = @embedFile("shader/mag/comp.spv").*;

    fn init(descriptor: *Descriptor) ngl.Error!Generation {
        const dev = &context().device;

        const pl = try ngl.Pipeline.initCompute(gpa, dev, .{
            .states = &.{.{
                .stage = .{
                    .code = &comp_spv,
                    .name = "main",
                    .specialization = .{
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
                        .data = @as([*]const u8, @ptrCast(&local))[0..8],
                    },
                },
                .layout = &descriptor.pipeline_layout,
            }},
            .cache = null,
        });
        defer gpa.free(pl);

        return .{ .pipeline = pl[0] };
    }

    fn deinit(self: *Generation) void {
        self.pipeline.deinit(gpa, &context().device);
    }
};

const Rendering = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,
    pipeline: ngl.Pipeline,

    const vert_spv align(4) = @embedFile("shader/mag/vert.spv").*;
    const frag_spv align(4) = @embedFile("shader/mag/frag.spv").*;

    fn init(descriptor: *Descriptor) ngl.Error!Rendering {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{.{
                .format = plat.format.format,
                .samples = .@"1",
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .unknown,
                .final_layout = .present_source,
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
            .dependencies = &.{
                .{
                    .source_subpass = .external,
                    .dest_subpass = .{ .index = 0 },
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{},
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
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
            },
        });
        errdefer rp.deinit(gpa, dev);

        var fbs = try gpa.alloc(ngl.FrameBuffer, plat.images.len);
        errdefer gpa.free(fbs);
        for (fbs, plat.image_views, 0..) |*fb, *sc_view, i|
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &rp,
                .attachments = &.{sc_view},
                .width = Platform.width,
                .height = Platform.height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| fbs[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (fbs) |*fb| fb.deinit(gpa, dev);

        const pl = try ngl.Pipeline.initGraphics(gpa, dev, .{
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
                .layout = &descriptor.pipeline_layout,
                .primitive = &.{
                    .bindings = &.{.{
                        .binding = 0,
                        .stride = @sizeOf(quad.Vertex),
                        .step_rate = .vertex,
                    }},
                    .attributes = &.{
                        .{
                            .location = 0,
                            .binding = 0,
                            .format = .rgb32_sfloat,
                            .offset = @offsetOf(quad.Vertex, "x"),
                        },
                        .{
                            .location = 1,
                            .binding = 0,
                            .format = .rg32_sfloat,
                            .offset = @offsetOf(quad.Vertex, "u"),
                        },
                    },
                    .topology = quad.topology,
                },
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = quad.clockwise,
                    .samples = .@"1",
                },
                .depth_stencil = null,
                .color_blend = &.{
                    .attachments = &.{.{ .blend = null, .write = .all }},
                },
                .render_pass = &rp,
                .subpass = 0,
            }},
            .cache = null,
        });
        defer gpa.free(pl);

        return .{
            .render_pass = rp,
            .frame_buffers = fbs,
            .pipeline = pl[0],
        };
    }

    fn deinit(self: *Rendering) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        self.render_pass.deinit(gpa, dev);
        self.pipeline.deinit(gpa, dev);
    }
};

const quad = struct {
    const topology = ngl.Primitive.Topology.triangle_strip;
    const clockwise = true;
    const vertex_count = 4;
    const size = @sizeOf(@TypeOf(vertices));

    const Vertex = packed struct {
        x: f32,
        y: f32,
        z: f32 = 0.5,
        u: f32,
        v: f32,
    };

    const vertices = [vertex_count]Vertex{
        .{
            .x = -1,
            .y = 1,
            .u = 0,
            .v = 1,
        },
        .{
            .x = -1,
            .y = -1,
            .u = 0,
            .v = 0,
        },
        .{
            .x = 1,
            .y = 1,
            .u = 1,
            .v = 1,
        },
        .{
            .x = 1,
            .y = -1,
            .u = 1,
            .v = 0,
        },
    };

    fn copy(staging_buffer: *Buffer(.host), offset: u64) void {
        const source = @as([*]const u8, @ptrCast(&vertices))[0..size];
        const dest = staging_buffer.data[offset .. offset + size];
        @memcpy(dest, source);
    }
};
