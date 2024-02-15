const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const util = @import("util.zig");
const model = @import("model.zig");
const idata = @import("idata.zig");

pub fn main() !void {
    try do();
}

const frame_n = 2;
const width = Platform.width;
const height = Platform.height;
const samples = ngl.SampleCount.@"4";

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    const extent = 512;
    const cube_map_size = extent * extent * 4 * 6;
    var cube_map = try CubeMap.init(ngl.Format.rgba8_srgb, extent);
    defer cube_map.deinit();

    const unif_buf_size = 256;
    var unif_buf = try Buffer(.device).init(
        .{ .uniform_buffer = true, .transfer_dest = true },
        unif_buf_size,
    );
    defer unif_buf.deinit();

    var mdl = try model.loadObj(gpa, "data/geometry/teapot.obj");
    defer mdl.deinit();
    if (mdl.indices != null) @panic("TODO");

    const vert_buf_size = mdl.positionSize() + mdl.normalSize() +
        @sizeOf(@TypeOf(model.cube.data.position));
    var vert_buf = try Buffer(.device).init(
        .{ .vertex_buffer = true, .transfer_dest = true },
        vert_buf_size,
    );
    defer vert_buf.deinit();

    const idx_buf_size = @sizeOf(@TypeOf(model.cube.indices));
    var idx_buf = try Buffer(.device).init(
        .{ .index_buffer = true, .transfer_dest = true },
        idx_buf_size,
    );
    defer idx_buf.deinit();

    const vert_copy_off = (cube_map_size + 255) & ~@as(u64, 255);
    const idx_copy_off = (vert_copy_off + vert_buf_size + 255) & ~@as(u64, 255);
    const unif_copy_off = (idx_copy_off + idx_buf_size + 255) & ~@as(u64, 255);
    const stg_buf_size = unif_copy_off + unif_buf_size;
    var stg_buf = try Buffer(.host).init(.{ .transfer_source = true }, stg_buf_size);
    defer stg_buf.deinit();

    var dest: struct {
        data: []u8,

        pub fn get(self: *@This(), size: u64) ![]u8 {
            if (size > self.data.len) @panic("Need to increase staging buffer size");
            defer self.data = self.data[size..];
            return self.data[0..size];
        }
    } = .{ .data = stg_buf.data };

    // x, -x, y, -y, z, -z
    // TODO: Need to flip some to match cube orientation
    const cube_data = .{
        try idata.loadPng(gpa, "data/image/x.png", &dest),
        try idata.loadPng(gpa, "data/image/-x.png", &dest),
        try idata.loadPng(gpa, "data/image/y.png", &dest),
        try idata.loadPng(gpa, "data/image/-y.png", &dest),
        try idata.loadPng(gpa, "data/image/z.png", &dest),
        try idata.loadPng(gpa, "data/image/-z.png", &dest),
    };
    inline for (cube_data) |x|
        if (x.width != extent or x.height != extent or x.format != .rgba8_srgb)
            @panic("TODO");

    var queue = try Queue.init();
    defer queue.deinit();

    var desc = try Descriptor.init(&cube_map, &unif_buf);
    defer desc.deinit();

    var col_attach = try ColorAttachment.init();
    defer col_attach.deinit();

    var dep_attach = try DepthAttachment.init();
    defer dep_attach.deinit();

    var pass = try Pass.init(&col_attach, &dep_attach);
    defer pass.deinit();

    var pl = try Pipeline.init(&desc, &pass);
    defer pl.deinit();

    const m = [16]f32{
        0.1, 0,   0,   0,
        0,   0.1, 0,   0,
        0,   0,   0.1, 0,
        0,   0,   0,   1,
    };
    const n = blk: {
        const inv = util.invert3(util.upperLeft(4, m));
        break :blk [12]f32{
            inv[0], inv[3], inv[6], undefined,
            inv[1], inv[4], inv[7], undefined,
            inv[2], inv[5], inv[8], undefined,
        };
    };
    const eye = [3]f32{ 0.2, -0.3, -0.4 };
    const v = util.lookAt(.{ 0, 0, 0 }, eye, .{ 0, -1, 0 });
    const ar = @as(f32, width) / @as(f32, height);
    const p = util.perspective(std.math.pi / 3.0, ar, 0.01, 100);
    {
        var s = dest.data;
        if (stg_buf.data.len - s.len != cube_map_size)
            @panic("Unexpected cube map copying size");
        s = s[vert_copy_off - cube_map_size ..];
        @memcpy(
            s[0..mdl.positionSize()],
            @as([*]const u8, @ptrCast(mdl.positions.items.ptr))[0..mdl.positionSize()],
        );
        @memcpy(
            s[mdl.positionSize() .. mdl.positionSize() + mdl.normalSize()],
            @as([*]const u8, @ptrCast(mdl.normals.items.ptr))[0..mdl.normalSize()],
        );
        @memcpy(
            s[mdl.positionSize() + mdl.normalSize() .. mdl.positionSize() + mdl.normalSize() +
                @sizeOf(@TypeOf(model.cube.data.position))],
            @as(
                [*]const u8,
                @ptrCast(&model.cube.data.position),
            )[0..@sizeOf(@TypeOf(model.cube.data.position))],
        );
        s = s[idx_copy_off - vert_copy_off ..];
        @memcpy(
            s[0..@sizeOf(@TypeOf(model.cube.indices))],
            @as(
                [*]const u8,
                @ptrCast(&model.cube.indices),
            )[0..@sizeOf(@TypeOf(model.cube.indices))],
        );
        s = s[unif_copy_off - idx_copy_off ..];
        @memcpy(s[0..64], @as([*]const u8, @ptrCast(&p))[0..64]);
        @memcpy(s[64..128], @as([*]const u8, @ptrCast(&v))[0..64]);
        @memcpy(s[128..192], @as([*]const u8, @ptrCast(&m))[0..64]);
        @memcpy(s[192..240], @as([*]const u8, @ptrCast(&n))[0..48]);
        @memcpy(s[240..256], @as([*]const u8, @ptrCast(&eye))[0..16]);
    }

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
            .image = &cube_map.image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 6,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBufferToImage(&.{.{
        .buffer = &stg_buf.buffer,
        .image = &cube_map.image,
        .image_layout = .transfer_dest_optimal,
        .image_type = .@"2d",
        .regions = &.{.{
            .buffer_offset = 0,
            .buffer_row_length = extent,
            .buffer_image_height = extent,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = extent,
            .image_height = extent,
            .image_depth_or_layers = 6,
        }},
    }});
    cmd.pipelineBarrier(&.{.{
        .image_dependencies = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{},
            .dest_access_mask = .{},
            .queue_transfer = null,
            .old_layout = .transfer_dest_optimal,
            .new_layout = .shader_read_only_optimal,
            .image = &cube_map.image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 6,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf.buffer,
            .dest = &vert_buf.buffer,
            .regions = &.{.{
                .source_offset = vert_copy_off,
                .dest_offset = 0,
                .size = vert_buf_size,
            }},
        },
        .{
            .source = &stg_buf.buffer,
            .dest = &idx_buf.buffer,
            .regions = &.{.{
                .source_offset = idx_copy_off,
                .dest_offset = 0,
                .size = idx_buf_size,
            }},
        },
        .{
            .source = &stg_buf.buffer,
            .dest = &unif_buf.buffer,
            .regions = &.{.{
                .source_offset = unif_copy_off,
                .dest_offset = 0,
                .size = unif_buf_size,
            }},
        },
    });
    try cmd.end();
    try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
    {
        ctx.lockQueue(queue.graphics);
        defer ctx.unlockQueue(queue.graphics);

        try dev.queues[queue.graphics].submit(gpa, dev, &queue.fences[0], &.{.{
            .commands = &.{.{ .command_buffer = &queue.buffers[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&queue.fences[0]});

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

        const next = try plat.swap_chain.nextImage(dev, std.time.ns_per_s, semas[0], null);

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
                    .{ .color_f32 = .{ 0.6, 0.6, 0, 1 } },
                    .{ .depth_stencil = .{ 1, undefined } },
                    null,
                },
            },
            .{ .contents = .inline_only },
        );
        cmd.setDescriptors(.graphics, &desc.pipeline_layout, 0, &.{&desc.set});
        cmd.setPipeline(&pl.cube_map);
        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vert_buf.buffer} ** 2,
            &.{ 0, mdl.positionSize() },
            &.{ mdl.positionSize(), mdl.normalSize() },
        );
        cmd.draw(mdl.vertexCount(), 1, 0, 0);
        cmd.setPipeline(&pl.sky_box);
        cmd.setIndexBuffer(
            model.cube.index_type,
            &idx_buf.buffer,
            0,
            @sizeOf(@TypeOf(model.cube.indices)),
        );
        cmd.setVertexBuffers(
            0,
            &.{&vert_buf.buffer},
            &.{mdl.positionSize() + mdl.normalSize()},
            &.{@sizeOf(@TypeOf(model.cube.data.position))},
        );
        cmd.drawIndexed(model.cube.indices.len, 1, 0, 0, 0);
        cmd.endRenderPass(.{});
        if (!is_unified) @panic("TODO");
        try cmd.end();

        try ngl.Fence.reset(gpa, dev, &.{fence});

        ctx.lockQueue(queue.graphics);
        defer ctx.unlockQueue(queue.graphics);

        try dev.queues[queue.graphics].submit(gpa, dev, fence, &.{.{
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
            pres_queue = &dev.queues[queue.graphics];
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

const CubeMap = struct {
    format: ngl.Format,
    extent: u32,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    fn init(format: ngl.Format, extent: u32) ngl.Error!CubeMap {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 6,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .sampled_image = true, .transfer_dest = true },
            .misc = .{ .cube_compatible = true },
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
            .type = .cube,
            .format = format,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 6,
            },
        });
        errdefer view.deinit(gpa, dev);
        const filt = if (format.getFeatures(dev).optimal_tiling.sampled_image_filter_linear)
            ngl.Sampler.Filter.linear
        else
            ngl.Sampler.Filter.nearest;
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
            .format = format,
            .extent = extent,
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *CubeMap) void {
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

        fn init(usage: ngl.Buffer.Usage, size: u64) ngl.Error!@This() {
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
            const data = if (domain == .device) {} else (mem.map(dev, 0, null) catch |err| {
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

const Queue = struct {
    graphics: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
    fences: [frame_n]ngl.Fence, // Signaled
    non_unified: ?struct {
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        semaphores: [frame_n]ngl.Semaphore,
    },

    fn init() ngl.Error!Queue {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const pres = plat.queue_index;
        const graph = if (dev.queues[pres].capabilities.graphics)
            pres
        else
            dev.findQueue(.{ .graphics = true }, null) orelse return error.NotSupported;

        var non_unified: @TypeOf((try Queue.init()).non_unified) = blk: {
            if (graph == pres)
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
            pool.* = ngl.CommandPool.init(gpa, dev, .{ .queue = &dev.queues[graph] }) catch |err| {
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
        var fences: [frame_n]ngl.Fence = undefined;
        for (&fences, 0..) |*fence, i|
            fence.* = ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled }) catch |err| {
                for (0..i) |j| fences[j].deinit(gpa, dev);
                return err;
            };

        return .{
            .graphics = graph,
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

const Descriptor = struct {
    set_layout: ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    set: ngl.DescriptorSet,

    fn init(cube_map: *CubeMap, uniform_buffer: *Buffer(.device)) ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
            .{
                .binding = 0,
                .type = .combined_image_sampler,
                .count = 1,
                .stage_mask = .{ .fragment = true },
                .immutable_samplers = &.{&cube_map.sampler},
            },
            .{
                .binding = 1,
                .type = .uniform_buffer,
                .count = 1,
                .stage_mask = .{ .vertex = true },
                .immutable_samplers = null,
            },
        } });
        errdefer set_layt.deinit(gpa, dev);
        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{&set_layt},
            .push_constant_ranges = null,
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = 1,
            .pool_size = .{ .combined_image_sampler = 1, .uniform_buffer = 1 },
        });
        errdefer pool.deinit(gpa, dev);
        var set = blk: {
            const s = try pool.alloc(gpa, dev, .{ .layouts = &.{&set_layt} });
            defer gpa.free(s);
            break :blk s[0];
        };
        try ngl.DescriptorSet.write(gpa, dev, &.{
            .{
                .descriptor_set = &set,
                .binding = 0,
                .element = 0,
                .contents = .{ .combined_image_sampler = &.{.{
                    .view = &cube_map.view,
                    .layout = .shader_read_only_optimal,
                    .sampler = null,
                }} },
            },
            .{
                .descriptor_set = &set,
                .binding = 1,
                .element = 0,
                .contents = .{
                    .uniform_buffer = &.{.{
                        .buffer = &uniform_buffer.buffer,
                        .offset = 0,
                        .range = 256,
                    }},
                },
            },
        });

        return .{
            .set_layout = set_layt,
            .pipeline_layout = pl_layt,
            .pool = pool,
            .set = set,
        };
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        self.set_layout.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const ColorAttachment = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init() ngl.Error!ColorAttachment {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const fmt = plat.format.format;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
            .tiling = .optimal,
            .usage = .{ .color_attachment = true, .transient_attachment = true },
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
        const view = try ngl.ImageView.init(gpa, dev, .{
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

        return .{
            .format = fmt,
            .image = image,
            .memory = mem,
            .view = view,
        };
    }

    fn deinit(self: *ColorAttachment) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const DepthAttachment = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init() ngl.Error!DepthAttachment {
        const dev = &context().device;

        const @"type" = ngl.Image.Type.@"2d";
        const tiling = ngl.Image.Tiling.optimal;
        const usage = ngl.Image.Usage{
            .depth_stencil_attachment = true,
            .transient_attachment = true,
        };
        const misc = ngl.Image.Misc{};

        const fmt = for ([_]ngl.Format{
            .x8_d24_unorm,
            .d24_unorm_s8_uint,
            .d32_sfloat,
            .d32_sfloat_s8_uint,
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
                if (err == ngl.Error.NotSupported)
                    continue;
                return err;
            };
            if (@field(capabs.sample_counts, @tagName(samples)))
                break fmt;
        } else @panic("MS count mismatch");

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = samples,
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

    fn deinit(self: *DepthAttachment) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const Pass = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,

    fn init(color_attachment: *ColorAttachment, depth_attachment: *DepthAttachment) ngl.Error!Pass {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                .{
                    .format = color_attachment.format,
                    .samples = samples,
                    .load_op = .clear,
                    .store_op = .dont_care,
                    .initial_layout = .unknown,
                    .final_layout = .color_attachment_optimal,
                    .resolve_mode = .average,
                    .combined = null,
                    .may_alias = false,
                },
                .{
                    .format = depth_attachment.format,
                    .samples = samples,
                    .load_op = .clear,
                    .store_op = .dont_care,
                    .initial_layout = .unknown,
                    .final_layout = .depth_stencil_attachment_optimal,
                    .resolve_mode = null,
                    .combined = if (depth_attachment.format.getAspectMask().stencil) .{
                        .stencil_load_op = .dont_care,
                        .stencil_store_op = .dont_care,
                    } else null,
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
            },
            .subpasses = &.{.{
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
            }},
            .dependencies = &.{
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
        const fbs = try gpa.alloc(ngl.FrameBuffer, plat.images.len);
        errdefer gpa.free(fbs);
        for (fbs, plat.image_views, 0..) |*fb, *sc_view, i|
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &rp,
                .attachments = &.{
                    &color_attachment.view,
                    &depth_attachment.view,
                    sc_view,
                },
                .width = width,
                .height = height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| fbs[j].deinit(gpa, dev);
                return err;
            };

        return .{
            .render_pass = rp,
            .frame_buffers = fbs,
        };
    }

    fn deinit(self: *Pass) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        gpa.free(self.frame_buffers);
        self.render_pass.deinit(gpa, dev);
    }
};

const Pipeline = struct {
    cube_map: ngl.Pipeline,
    sky_box: ngl.Pipeline,

    const cube_map_vert_spv align(4) = @embedFile("shader/cube/cube_map.vert.spv").*;
    const cube_map_frag_spv align(4) = @embedFile("shader/cube/cube_map.frag.spv").*;
    const sky_box_vert_spv align(4) = @embedFile("shader/cube/sky_box.vert.spv").*;
    const sky_box_frag_spv align(4) = @embedFile("shader/cube/sky_box.frag.spv").*;

    fn init(descriptor: *Descriptor, pass: *Pass) ngl.Error!Pipeline {
        const dev = &context().device;

        const vport = ngl.Viewport{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
            .near = 0,
            .far = 1,
        };
        const ds = ngl.DepthStencil{
            .depth_compare = .less_equal,
            .depth_write = true,
            .stencil_front = null,
            .stencil_back = null,
        };
        const blend = ngl.ColorBlend{
            .attachments = &.{.{ .blend = null, .write = .all }},
            .constants = .unused,
        };

        const cm_state = ngl.GraphicsState{
            .stages = &.{
                .{
                    .stage = .vertex,
                    .code = &cube_map_vert_spv,
                    .name = "main",
                },
                .{
                    .stage = .fragment,
                    .code = &cube_map_frag_spv,
                    .name = "main",
                },
            },
            .layout = &descriptor.pipeline_layout,
            .primitive = &.{
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
            .viewport = &vport,
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .none,
                .clockwise = false,
                .samples = samples,
            },
            .depth_stencil = &ds,
            .color_blend = &blend,
            .render_pass = &pass.render_pass,
            .subpass = 0,
        };

        const sb_state = ngl.GraphicsState{
            .stages = &.{
                .{
                    .stage = .vertex,
                    .code = &sky_box_vert_spv,
                    .name = "main",
                },
                .{
                    .stage = .fragment,
                    .code = &sky_box_frag_spv,
                    .name = "main",
                },
            },
            .layout = &descriptor.pipeline_layout,
            .primitive = &.{
                .bindings = &.{.{
                    .binding = 0,
                    .stride = 12,
                    .step_rate = .vertex,
                }},
                .attributes = &.{.{
                    .location = 0,
                    .binding = 0,
                    .format = .rgb32_sfloat,
                    .offset = 0,
                }},
                .topology = model.cube.topology,
            },
            .viewport = &vport,
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .front,
                .clockwise = model.cube.clockwise,
                .samples = samples,
            },
            .depth_stencil = &ds,
            .color_blend = &blend,
            .render_pass = &pass.render_pass,
            .subpass = 0,
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{ cm_state, sb_state },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{
            .cube_map = pls[0],
            .sky_box = pls[1],
        };
    }

    fn deinit(self: *Pipeline) void {
        const dev = &context().device;
        self.cube_map.deinit(gpa, dev);
        self.sky_box.deinit(gpa, dev);
    }
};
