const std = @import("std");

const ngl = @import("../ngl.zig");
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
const draw_n = planes.len + cubes.len;

const planes = [1]Draw(.plane){
    .{
        .index = 0,
        .m = .{
            10, 0,  0,  0,
            0,  10, 0,  0,
            0,  0,  10, 0,
            0,  0,  0,  1,
        },
        .base_color = .{ 0, 0, 1 },
        .metallic = 0,
        .roughness = 1,
        .reflectance = 0.01,
    },
};

const cubes = [5]Draw(.cube){
    .{
        .index = planes.len,
        .m = .{
            0.1,    0,    0,     0,
            0,      0.1,  0,     0,
            0,      0,    0.1,   0,
            -0.125, -0.3, -0.25, 1,
        },
        .base_color = .{ 1, 0, 0 },
        .metallic = 1,
        .roughness = 0.1,
        .reflectance = 0,
    },
    .{
        .index = planes.len + 1,
        .m = .{
            0.3, 0,    0,    0,
            0,   0.1,  0,    0,
            0,   0,    0.2,  0,
            0,   -0.1, -0.3, 1,
        },
        .base_color = .{ 1, 0, 1 },
        .metallic = 1,
        .roughness = 0.1,
        .reflectance = 0,
    },
    .{
        .index = planes.len + 2,
        .m = .{
            0.1,  0,    0,   0,
            0,    0.2,  0,   0,
            0,    0,    0.1, 0,
            -0.3, -0.2, 0.3, 1,
        },
        .base_color = .{ 0, 1, 0 },
        .metallic = 1,
        .roughness = 0.1,
        .reflectance = 0,
    },
    .{
        .index = planes.len + 3,
        .m = .{
            0.1,  0,     0,    0,
            0,    0.15,  0,    0,
            0,    0,     0.1,  0,
            0.25, -0.15, 0.25, 1,
        },
        .base_color = .{ 0, 1, 1 },
        .metallic = 1,
        .roughness = 0.1,
        .reflectance = 0,
    },
    .{
        .index = planes.len + 4,
        .m = .{
            0.1, 0,     0,    0,
            0,   0.15,  0,    0,
            0,   0,     0.1,  0,
            0.1, -0.15, -0.6, 1,
        },
        .base_color = .{ 0.9, 0.9, 0.9 },
        .metallic = 1,
        .roughness = 0.05,
        .reflectance = 0,
    },
};

const light: Light = blk: {
    const pos = [3]f32{ 0.75, -1, -1.25 };
    const vp = util.mulM(
        4,
        util.frustum(-1, 1, -1, 1, 1, 100),
        util.lookAt(.{ 0, 0, 0 }, pos, .{ 0, -1, 0 }),
    );
    const vps = util.mulM(4, .{
        0.5, 0,   0, 0,
        0,   0.5, 0, 0,
        0,   0,   1, 0,
        0.5, 0.5, 0, 1,
    }, vp);
    break :blk .{
        .mvp = vp,
        .s = vps,
        .world_pos = pos,
        .color = .{ 1, 1, 1 },
        .intensity = 40,
    };
};

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var shdw_map = try ShadowMap.init();
    defer shdw_map.deinit();

    var shdw_dep = try ShadowDepth.init(shdw_map);
    defer shdw_dep.deinit();

    var col_attach = try ColorAttachment.init();
    defer col_attach.deinit();

    var dep_attach = try DepthAttachment.init(col_attach);
    defer dep_attach.deinit();

    var queue = try Queue.init();
    defer queue.deinit();

    const unif_buf_size = (1 + draw_n * 3) * frame_n * 256;
    var unif_buf = try Buffer(.host).init(unif_buf_size, .{ .uniform_buffer = true });
    defer unif_buf.deinit();

    const vert_buf_size = @sizeOf(@TypeOf(model.plane.data)) + @sizeOf(@TypeOf(model.cube.data));
    var vert_buf = try Buffer(.device).init(vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit();

    const idx_buf_size = @sizeOf(@TypeOf(model.cube.indices));
    var idx_buf = try Buffer(.device).init(idx_buf_size, .{
        .index_buffer = true,
        .transfer_dest = true,
    });
    defer idx_buf.deinit();

    const stg_buf_size = unif_buf_size + vert_buf_size + idx_buf_size;
    var stg_buf = try Buffer(.host).init(stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit();

    {
        var data = stg_buf.data;
        var size: u64 = @sizeOf(@TypeOf(model.plane.data));
        @memcpy(data[0..size], @as([*]const u8, @ptrCast(&model.plane.data))[0..size]);
        data = data[size..];
        size = @sizeOf(@TypeOf(model.cube.data));
        @memcpy(data[0..size], @as([*]const u8, @ptrCast(&model.cube.data))[0..size]);
        data = data[size..];
        size = @sizeOf(@TypeOf(model.cube.indices));
        @memcpy(data[0..size], @as([*]const u8, @ptrCast(&model.cube.indices))[0..size]);
    }

    var desc = try Descriptor.init(&shdw_map);
    defer desc.deinit();

    const v = util.lookAt(.{ 0, 0, 0 }, .{ -1, -2, -2 }, .{ 0, -1, 0 });
    const vp = util.mulM(4, util.perspective(
        std.math.pi / 3.0,
        @as(f32, Platform.width) / @as(f32, Platform.height),
        0.01,
        100,
    ), v);

    for (0..frame_n) |i| {
        try desc.write(i, &shdw_map, &unif_buf);

        light.update(i, &unif_buf, v);

        for (planes) |plane| {
            plane.updateShading(i, &unif_buf, .{
                .s = light.s,
                .vp = vp,
                .v = v,
            });
            plane.updateGeneration(i, &unif_buf, light.mvp);
        }

        for (cubes) |cube| {
            cube.updateShading(i, &unif_buf, .{
                .s = light.s,
                .vp = vp,
                .v = v,
            });
            cube.updateGeneration(i, &unif_buf, light.mvp);
        }
    }

    var gen = try Generation.init(&shdw_map, &shdw_dep, &desc);
    defer gen.deinit();

    var smo = try Smoothing.init(&desc);
    defer smo.deinit();

    var shd = try Shading.init(&col_attach, &dep_attach, &desc);
    defer shd.deinit();

    var cmd = try queue.buffers[0].begin(gpa, dev, .{
        .one_time_submit = true,
        .inheritance = null,
    });
    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf.buffer,
            .dest = &vert_buf.buffer,
            .regions = &.{.{
                .source_offset = 0,
                .dest_offset = 0,
                .size = vert_buf_size,
            }},
        },
        .{
            .source = &stg_buf.buffer,
            .dest = &idx_buf.buffer,
            .regions = &.{.{
                .source_offset = vert_buf_size,
                .dest_offset = 0,
                .size = idx_buf_size,
            }},
        },
    });
    try cmd.end();

    {
        try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});

        ctx.lockQueue(queue.index);
        defer ctx.unlockQueue(queue.index);

        try dev.queues[queue.index].submit(gpa, dev, &queue.fences[0], &.{.{
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

        try cmd_pool.reset(dev);
        cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
        gen.record(&cmd, frame, &desc, &vert_buf, &idx_buf);
        smo.record(&cmd, frame, &desc, &shdw_map);
        shd.record(&cmd, frame, &desc, next, &vert_buf, &idx_buf);
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
            .swap_chain = &plat.swap_chain,
            .image_index = next,
        }});

        frame = (frame + 1) % frame_n;
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 5, blk: {
        var fences: [frame_n]*ngl.Fence = undefined;
        for (0..fences.len) |i| fences[i] = &queue.fences[i];
        break :blk &fences;
    });
}

// TODO: Mip levels
const ShadowMap = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    // TODO: Try increasing the extent (and then blur a downsampled shadow map)
    const extent = 256;

    fn init() ngl.Error!ShadowMap {
        const dev = &context().device;

        const fmt = blk: {
            for ([_]ngl.Format{
                //.rg32_sfloat,
                //.rgb32_sfloat, // This is rarely supported for anything other than vertex input
                .rgba32_sfloat,
                //.rg16_sfloat,
                //.rgba16_sfloat, // This must support all the features we need
            }) |fmt| {
                const opt = fmt.getFeatures(dev).optimal_tiling;
                if (opt.sampled_image_filter_linear and opt.storage_image and opt.color_attachment)
                    break :blk fmt;
            }
            @panic("TODO");
            //unreachable;
        };

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = extent,
            .height = extent,
            .depth_or_layers = 2,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
                .color_attachment = true,
            },
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
                .format = fmt,
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
            .u_address = .clamp_to_border,
            .v_address = .clamp_to_border,
            .w_address = .clamp_to_border,
            .border_color = .opaque_white_float,
            .mag = .linear,
            .min = .linear,
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
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *ShadowMap) void {
        const dev = &context().device;
        self.sampler.deinit(gpa, dev);
        for (&self.views) |*view| view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const ShadowDepth = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init(shadow_map: ShadowMap) ngl.Error!ShadowDepth {
        const dev = &context().device;

        const fmt = switch (shadow_map.format) {
            .rg32_sfloat,
            .rgb32_sfloat,
            .rgba32_sfloat,
            => for ([_]ngl.Format{
                .d32_sfloat,
                .d32_sfloat_s8_uint,
                .x8_d24_unorm,
                .d24_unorm_s8_uint,
            }) |fmt| {
                const opt = fmt.getFeatures(dev).optimal_tiling;
                if (opt.depth_stencil_attachment)
                    break fmt;
            } else .d16_unorm,

            else => .d16_unorm,
        };

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = ShadowMap.extent,
            .height = ShadowMap.extent,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment = true, .transient_attachment = true },
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

    fn deinit(self: *ShadowDepth) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const ColorAttachment = struct {
    samples: ngl.SampleCount,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init() ngl.Error!ColorAttachment {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const @"type" = ngl.Image.Type.@"2d";
        const fmt = plat.format.format;
        const tiling = ngl.Image.Tiling.optimal;
        const usage = ngl.Image.Usage{ .color_attachment = true, .transient_attachment = true };
        const misc = ngl.Image.Misc{};

        const spls: ngl.SampleCount = blk: {
            const capabs = try ngl.Image.getCapabilities(dev, @"type", fmt, tiling, usage, misc);
            const cnts = capabs.sample_counts;
            break :blk if (cnts.@"16")
                .@"16"
            else if (cnts.@"8")
                .@"8"
            else
                .@"4";
        };

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = Platform.width,
            .height = Platform.height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = spls,
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
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        });

        return .{
            .samples = spls,
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

    fn init(color_attachment: ColorAttachment) ngl.Error!DepthAttachment {
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
            const bit: U = @as(U, 1) << @intFromEnum(color_attachment.samples);
            if (mask & bit == bit) break fmt;
        } else @panic("MS mismatch");

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = Platform.width,
            .height = Platform.height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = color_attachment.samples,
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

const Queue = struct {
    index: ngl.Queue.Index, // Graphics/compute
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

const Descriptor = struct {
    set_layouts: [3]ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [(1 + draw_n * 3) * frame_n]ngl.DescriptorSet,

    fn init(shadow_map: *ShadowMap) ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                // Shadow map layer [0]
                .{
                    .binding = 0,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Shadow map layer [1]
                .{
                    .binding = 1,
                    .type = .storage_image,
                    .count = 1,
                    .stage_mask = .{ .compute = true },
                    .immutable_samplers = null,
                },
                // Shadow map layer [0] again
                .{
                    .binding = 2,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&shadow_map.sampler},
                },
                // Light uniforms
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
        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                // Material uniforms
                .{
                    .binding = 0,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt_2.deinit(gpa, dev);
        var set_layt_3 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                // Global uniforms for shadow generation and shading
                .{
                    .binding = 0,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .vertex = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layt_3.deinit(gpa, dev);

        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{ &set_layt, &set_layt_2, &set_layt_3 },
            .push_constant_ranges = null,
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = (1 + draw_n * 3) * frame_n,
            .pool_size = .{
                .combined_image_sampler = frame_n,
                .storage_image = 2 * frame_n,
                .uniform_buffer = (1 + draw_n * 3) * frame_n,
            },
        });
        errdefer pool.deinit(gpa, dev);
        const sets = blk: {
            const s = try pool.alloc(gpa, dev, blk_2: {
                // One per frame
                const @"0" = [_]*ngl.DescriptorSetLayout{&set_layt};
                // One per draw per frame
                const @"1" = [_]*ngl.DescriptorSetLayout{&set_layt_2};
                // Two per draw per frame (drawn twice)
                const @"2" = [_]*ngl.DescriptorSetLayout{&set_layt_3};
                break :blk_2 .{ .layouts = &(@"0" ++ (@"1" ++ @"2" ** 2) ** draw_n) ** frame_n };
            });
            defer gpa.free(s);
            break :blk s[0 .. (1 + draw_n * 3) * frame_n].*;
        };

        return .{
            .set_layouts = .{ set_layt, set_layt_2, set_layt_3 },
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn write(
        self: *Descriptor,
        frame: usize,
        shadow_map: *ShadowMap,
        uniform_buffer: *Buffer(.host),
    ) ngl.Error!void {
        var writes: [4 + draw_n * 3]ngl.DescriptorSet.Write = undefined;
        const base_set = self.sets[frame * (1 + draw_n * 3) ..];
        const base_off = (frame * (1 + draw_n * 3)) * 256;

        writes[0] = .{
            .descriptor_set = &base_set[0],
            .binding = 0,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &shadow_map.views[0],
                .layout = .general,
            }} },
        };
        writes[1] = .{
            .descriptor_set = &base_set[0],
            .binding = 1,
            .element = 0,
            .contents = .{ .storage_image = &.{.{
                .view = &shadow_map.views[1],
                .layout = .general,
            }} },
        };
        writes[2] = .{
            .descriptor_set = &base_set[0],
            .binding = 2,
            .element = 0,
            .contents = .{ .combined_image_sampler = &.{.{
                .view = &shadow_map.views[0],
                .layout = .shader_read_only_optimal,
                .sampler = null,
            }} },
        };
        writes[3] = .{
            .descriptor_set = &base_set[0],
            .binding = 3,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = &uniform_buffer.buffer,
                .offset = base_off,
                .range = 256,
            }} },
        };

        var buf_w: [draw_n * 3]ngl.DescriptorSet.Write.BufferWrite = undefined;
        for (0..draw_n) |i| {
            buf_w[i * 3] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = base_off + 256 + i * 768,
                .range = 256,
            };
            buf_w[i * 3 + 1] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = base_off + 256 + i * 768 + 256,
                .range = 256,
            };
            buf_w[i * 3 + 2] = .{
                .buffer = &uniform_buffer.buffer,
                .offset = base_off + 256 + i * 768 + 512,
                .range = 256,
            };
            writes[4 + i * 3] = .{
                .descriptor_set = &base_set[1 + i * 3],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i * 3 .. i * 3 + 1] },
            };
            writes[4 + i * 3 + 1] = .{
                .descriptor_set = &base_set[1 + i * 3 + 1],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i * 3 + 1 .. i * 3 + 2] },
            };
            writes[4 + i * 3 + 2] = .{
                .descriptor_set = &base_set[1 + i * 3 + 2],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = buf_w[i * 3 + 2 .. i * 3 + 3] },
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

const Generation = struct {
    render_pass: ngl.RenderPass,
    frame_buffer: ngl.FrameBuffer,
    pipelines: [2]ngl.Pipeline,

    const plane = 0;
    const cube = 1;

    const vert_spv align(4) = @embedFile("shader/vsm/shdw_map.vert.spv").*;
    const frag_spv align(4) = @embedFile("shader/vsm/shdw_map.frag.spv").*;

    fn init(
        shadow_map: *ShadowMap,
        shadow_depth: *ShadowDepth,
        descriptor: *Descriptor,
    ) ngl.Error!Generation {
        const dev = &context().device;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                .{
                    .format = shadow_map.format,
                    .samples = .@"1",
                    .load_op = .clear,
                    .store_op = .store,
                    .initial_layout = .unknown,
                    .final_layout = .general,
                    .resolve_mode = null,
                    .combined = null,
                    .may_alias = false,
                },
                .{
                    .format = shadow_depth.format,
                    .samples = .@"1",
                    .load_op = .clear,
                    .store_op = .dont_care,
                    .initial_layout = .unknown,
                    .final_layout = .depth_stencil_attachment_optimal,
                    .resolve_mode = null,
                    .combined = if (shadow_depth.format.getAspectMask().stencil) .{
                        .stencil_load_op = .dont_care,
                        .stencil_store_op = .dont_care,
                    } else null,
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
                    .resolve = null,
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
                    .source_access_mask = .{
                        .depth_stencil_attachment_write = true,
                        .color_attachment_write = true,
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
            },
        });
        errdefer rp.deinit(gpa, dev);

        var fb = try ngl.FrameBuffer.init(gpa, dev, .{
            .render_pass = &rp,
            .attachments = &.{ &shadow_map.views[0], &shadow_depth.view },
            .width = ShadowMap.extent,
            .height = ShadowMap.extent,
            .layers = 1,
        });
        errdefer fb.deinit(gpa, dev);

        const plane_state = ngl.GraphicsState{
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
                    .stride = 12,
                    .step_rate = .vertex,
                }},
                .attributes = &.{.{
                    .location = 0,
                    .binding = 0,
                    .format = .rgb32_sfloat,
                    .offset = 0,
                }},
                .topology = model.plane.topology,
            },
            .viewport = &.{
                .x = 0,
                .y = 0,
                .width = ShadowMap.extent,
                .height = ShadowMap.extent,
                .near = 0,
                .far = 1,
            },
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .back, // Notice back-face culling
                .clockwise = model.plane.clockwise,
                .samples = .@"1",
            },
            .depth_stencil = &.{
                .depth_compare = .less,
                .depth_write = true,
                .stencil_front = null,
                .stencil_back = null,
            },
            .color_blend = &.{
                .attachments = &.{.{
                    .blend = null,
                    .write = .{ .mask = .{ .r = true, .g = true, .b = false, .a = false } },
                }},
                .constants = .unused,
            },
            .render_pass = &rp,
            .subpass = 0,
        };

        const cube_state = ngl.GraphicsState{
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
            .viewport = &.{
                .x = 0,
                .y = 0,
                .width = ShadowMap.extent,
                .height = ShadowMap.extent,
                .near = 0,
                .far = 1,
            },
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .back, // Notice back-face culling
                .clockwise = model.cube.clockwise,
                .samples = .@"1",
            },
            .depth_stencil = &.{
                .depth_compare = .less,
                .depth_write = true,
                .stencil_front = null,
                .stencil_back = null,
            },
            .color_blend = &.{
                .attachments = &.{.{
                    .blend = null,
                    .write = .{ .mask = .{ .r = true, .g = true, .b = false, .a = false } },
                }},
                .constants = .unused,
            },
            .render_pass = &rp,
            .subpass = 0,
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{ plane_state, cube_state },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{
            .render_pass = rp,
            .frame_buffer = fb,
            .pipelines = pls[0..2].*,
        };
    }

    fn record(
        self: *Generation,
        cmd: *ngl.Cmd,
        frame: usize,
        descriptor: *Descriptor,
        vertex_buffer: *Buffer(.device),
        index_buffer: *Buffer(.device),
    ) void {
        cmd.setDescriptors(
            .graphics,
            &descriptor.pipeline_layout,
            0,
            &.{&descriptor.sets[frame * (1 + draw_n * 3)]},
        );
        cmd.beginRenderPass(
            .{
                .render_pass = &self.render_pass,
                .frame_buffer = &self.frame_buffer,
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = ShadowMap.extent,
                    .height = ShadowMap.extent,
                },
                .clear_values = &.{
                    .{ .color_f32 = .{ 1, 1, 0, 0 } },
                    .{ .depth_stencil = .{ 1, undefined } },
                },
            },
            .{ .contents = .inline_only },
        );
        Draw(.plane).draw(cmd, frame, descriptor, self, vertex_buffer, index_buffer, &planes);
        Draw(.cube).draw(cmd, frame, descriptor, self, vertex_buffer, index_buffer, &cubes);
        cmd.endRenderPass(.{});
    }

    fn deinit(self: *Generation) void {
        const dev = &context().device;
        for (&self.pipelines) |*pl| pl.deinit(gpa, dev);
        self.frame_buffer.deinit(gpa, dev);
        self.render_pass.deinit(gpa, dev);
    }
};

const Smoothing = struct {
    pipelines: [2]ngl.Pipeline,

    const v_comp_spv align(4) = @embedFile("shader/vsm/blur.comp.spv").*;
    const h_comp_spv align(4) = @embedFile("shader/vsm/blur_2.comp.spv").*;

    fn init(descriptor: *Descriptor) ngl.Error!Smoothing {
        const pls = try ngl.Pipeline.initCompute(gpa, &context().device, .{
            .states = &.{
                .{
                    .stage = .{
                        .stage = .compute,
                        .code = &v_comp_spv,
                        .name = "main",
                    },
                    .layout = &descriptor.pipeline_layout,
                },
                .{
                    .stage = .{
                        .stage = .compute,
                        .code = &h_comp_spv,
                        .name = "main",
                    },
                    .layout = &descriptor.pipeline_layout,
                },
            },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{ .pipelines = pls[0..2].* };
    }

    fn record(
        self: *Smoothing,
        cmd: *ngl.Cmd,
        frame: usize,
        descriptor: *Descriptor,
        shadow_map: *ShadowMap,
    ) void {
        // Note that this is only set for graphics at this point
        cmd.setDescriptors(
            .compute,
            &descriptor.pipeline_layout,
            0,
            &.{&descriptor.sets[frame * (1 + draw_n * 3)]},
        );

        // Shadow generation pass will transition the first layer
        // to the `general` layout
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_read = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_storage_write = true },
                .queue_transfer = null,
                .old_layout = .unknown,
                .new_layout = .general,
                .image = &shadow_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 1,
                    .layers = 1,
                },
            }},
            .by_region = false,
        }});

        // Read from first layer and writes to second layer
        cmd.setPipeline(&self.pipelines[0]);
        cmd.dispatch(ShadowMap.extent, ShadowMap.extent, 1);

        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_read = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_write = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .general,
                    .image = &shadow_map.image,
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
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_storage_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .general,
                    .image = &shadow_map.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .base_level = 0,
                        .levels = 1,
                        .base_layer = 1,
                        .layers = 1,
                    },
                },
            },
            .by_region = false,
        }});

        // Reads from second layer and writes to first layer
        cmd.setPipeline(&self.pipelines[1]);
        cmd.dispatch(ShadowMap.extent, ShadowMap.extent, 1);

        // The result ends up in the first layer, which will be
        // sampled in the shading pass
        cmd.pipelineBarrier(&.{.{
            .image_dependencies = &.{.{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_write = true },
                .dest_stage_mask = .{ .fragment_shader = true },
                .dest_access_mask = .{ .shader_sampled_read = true },
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .shader_read_only_optimal,
                .image = &shadow_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            }},
            .by_region = false,
        }});
    }

    fn deinit(self: *Smoothing) void {
        for (&self.pipelines) |*pl| pl.deinit(gpa, &context().device);
    }
};

const Shading = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,
    pipelines: [2]ngl.Pipeline,

    const plane = 0;
    const cube = 1;

    const vert_spv align(4) = @embedFile("shader/vsm/shd.vert.spv").*;
    const frag_spv align(4) = @embedFile("shader/vsm/shd.frag.spv").*;

    fn init(
        color_attachment: *ColorAttachment,
        depth_attachment: *DepthAttachment,
        descriptor: *Descriptor,
    ) ngl.Error!Shading {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                .{
                    .format = plat.format.format,
                    .samples = color_attachment.samples,
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
                    .samples = color_attachment.samples,
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
                    .resolve = .{
                        .index = 2,
                        .layout = .color_attachment_optimal,
                    },
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
                        .compute_shader = true,
                    },
                    .source_access_mask = .{
                        .depth_stencil_attachment_write = true,
                        .color_attachment_write = true,
                        .shader_storage_write = true,
                    },
                    .dest_stage_mask = .{
                        .early_fragment_tests = true,
                        .fragment_shader = true,
                        .color_attachment_output = true,
                    },
                    .dest_access_mask = .{
                        .shader_sampled_read = true,
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

        var fbs = try gpa.alloc(ngl.FrameBuffer, plat.images.len);
        errdefer gpa.free(fbs);
        for (fbs, plat.image_views, 0..) |*fb, *sc_view, i|
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &rp,
                .attachments = &.{
                    &color_attachment.view,
                    &depth_attachment.view,
                    sc_view,
                },
                .width = Platform.width,
                .height = Platform.height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| fbs[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (fbs) |*fb| fb.deinit(gpa, dev);

        const plane_state = ngl.GraphicsState{
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
                    .{
                        .binding = 2,
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
                        .format = .rgb32_sfloat,
                        .offset = 0,
                    },
                    .{
                        .location = 2,
                        .binding = 2,
                        .format = .rg32_sfloat,
                        .offset = 0,
                    },
                },
                .topology = model.plane.topology,
            },
            .viewport = &.{
                .x = 0,
                .y = 0,
                .width = Platform.width,
                .height = Platform.height,
                .near = 0,
                .far = 1,
            },
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = model.plane.clockwise,
                .samples = color_attachment.samples,
            },
            .depth_stencil = &.{
                .depth_compare = .less,
                .depth_write = true,
                .stencil_front = null,
                .stencil_back = null,
            },
            .color_blend = &.{
                .attachments = &.{.{ .blend = null, .write = .all }},
                .constants = .unused,
            },
            .render_pass = &rp,
            .subpass = 0,
        };

        const cube_state = ngl.GraphicsState{
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
                    .{
                        .binding = 2,
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
                        .format = .rgb32_sfloat,
                        .offset = 0,
                    },
                    .{
                        .location = 2,
                        .binding = 2,
                        .format = .rg32_sfloat,
                        .offset = 0,
                    },
                },
                .topology = model.cube.topology,
            },
            .viewport = &.{
                .x = 0,
                .y = 0,
                .width = Platform.width,
                .height = Platform.height,
                .near = 0,
                .far = 1,
            },
            .rasterization = &.{
                .polygon_mode = .fill,
                .cull_mode = .back,
                .clockwise = model.cube.clockwise,
                .samples = color_attachment.samples,
            },
            .depth_stencil = &.{
                .depth_compare = .less,
                .depth_write = true,
                .stencil_front = null,
                .stencil_back = null,
            },
            .color_blend = &.{
                .attachments = &.{.{ .blend = null, .write = .all }},
                .constants = .unused,
            },
            .render_pass = &rp,
            .subpass = 0,
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{ plane_state, cube_state },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{
            .render_pass = rp,
            .frame_buffers = fbs,
            .pipelines = pls[0..2].*,
        };
    }

    fn record(
        self: *Shading,
        cmd: *ngl.Cmd,
        frame: usize,
        descriptor: *Descriptor,
        next: ngl.SwapChain.Index,
        vertex_buffer: *Buffer(.device),
        index_buffer: *Buffer(.device),
    ) void {
        // Descriptor set 0 is already set

        cmd.beginRenderPass(
            .{
                .render_pass = &self.render_pass,
                .frame_buffer = &self.frame_buffers[next],
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
        Draw(.plane).draw(cmd, frame, descriptor, self, vertex_buffer, index_buffer, &planes);
        Draw(.cube).draw(cmd, frame, descriptor, self, vertex_buffer, index_buffer, &cubes);
        cmd.endRenderPass(.{});
    }

    fn deinit(self: *Shading) void {
        const dev = &context().device;
        for (&self.pipelines) |*pl| pl.deinit(gpa, dev);
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        gpa.free(self.frame_buffers);
        self.render_pass.deinit(gpa, dev);
    }
};

const Light = struct {
    mvp: [16]f32,
    s: [16]f32,
    world_pos: [3]f32,
    color: [3]f32,
    intensity: f32,

    fn update(self: Light, frame: usize, uniform_buffer: *Buffer(.host), v_camera: [16]f32) void {
        const off = frame * (1 + draw_n * 3) * 256;
        var data = uniform_buffer.data[off..];
        const pos = util.mulMV(4, v_camera, self.world_pos ++ [_]f32{1});
        @memcpy(
            data[0..32],
            @as([*]const u8, @ptrCast(&pos ++ self.color ++ [_]f32{self.intensity}))[0..32],
        );
    }
};

fn Draw(comptime @"type": enum { plane, cube }) type {
    return struct {
        index: usize,
        m: [16]f32,
        base_color: [3]f32,
        metallic: f32,
        roughness: f32,
        reflectance: f32,

        fn updateShading(
            self: @This(),
            frame: usize,
            uniform_buffer: *Buffer(.host),
            transforms: struct {
                s: [16]f32,
                vp: [16]f32,
                v: [16]f32,
            },
        ) void {
            const off = (frame * (1 + draw_n * 3) + (1 + self.index * 3)) * 256;
            var data = uniform_buffer.data[off..];
            @memcpy(
                data[0..24],
                @as([*]const u8, @ptrCast(&self.base_color ++ [_]f32{
                    self.metallic,
                    self.roughness,
                    self.reflectance,
                })),
            );
            data = data[256..];

            const s = util.mulM(4, transforms.s, self.m);
            const mvp = util.mulM(4, transforms.vp, self.m);
            const mv = util.mulM(4, transforms.v, self.m);
            const n = blk: {
                const n = util.invert3(util.upperLeft(4, mv));
                break :blk [12]f32{
                    n[0], n[3], n[6], undefined,
                    n[1], n[4], n[7], undefined,
                    n[2], n[5], n[8], undefined,
                };
            };

            @memcpy(data[0..64], @as([*]const u8, @ptrCast(&s))[0..64]);
            data = data[64..];
            @memcpy(data[0..64], @as([*]const u8, @ptrCast(&mvp))[0..64]);
            data = data[64..];
            @memcpy(data[0..64], @as([*]const u8, @ptrCast(&mv))[0..64]);
            data = data[64..];
            @memcpy(data[0..48], @as([*]const u8, @ptrCast(&n))[0..48]);
        }

        fn updateGeneration(
            self: @This(),
            frame: usize,
            uniform_buffer: *Buffer(.host),
            mvp_light: [16]f32,
        ) void {
            const off = (frame * (1 + draw_n * 3) + (1 + self.index * 3 + 2)) * 256;
            const data = uniform_buffer.data[off..];
            const mvp = util.mulM(4, mvp_light, self.m);
            @memcpy(data[0..64], @as([*]const u8, @ptrCast(&mvp))[0..64]);
        }

        // Descriptor set 0 must have been set
        fn draw(
            cmd: *ngl.Cmd,
            frame: usize,
            descriptor: *Descriptor,
            pass: anytype,
            vertex_buffer: *Buffer(.device),
            index_buffer: ?*Buffer(.device),
            draws: []const @This(),
        ) void {
            switch (@"type") {
                .plane => {
                    cmd.setPipeline(&pass.pipelines[@TypeOf(pass.*).plane]);
                    cmd.setVertexBuffers(
                        0,
                        &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 3,
                        &.{
                            @offsetOf(@TypeOf(model.plane.data), "position"),
                            @offsetOf(@TypeOf(model.plane.data), "normal"),
                            @offsetOf(@TypeOf(model.plane.data), "tex_coord"),
                        },
                        &.{
                            @sizeOf(@TypeOf(model.plane.data.position)),
                            @sizeOf(@TypeOf(model.plane.data.normal)),
                            @sizeOf(@TypeOf(model.plane.data.tex_coord)),
                        },
                    );
                    for (draws) |d| {
                        const set_off = frame * (1 + draw_n * 3) + 1 + d.index * 3;
                        const sets = descriptor.sets[set_off .. set_off + 3];
                        switch (@TypeOf(pass)) {
                            *Shading => cmd.setDescriptors(
                                .graphics,
                                &descriptor.pipeline_layout,
                                1,
                                &.{ &sets[0], &sets[1] },
                            ),
                            *Generation => cmd.setDescriptors(
                                .graphics,
                                &descriptor.pipeline_layout,
                                2,
                                &.{&sets[2]},
                            ),
                            else => unreachable,
                        }
                        cmd.draw(model.plane.vertex_count, 1, 0, 0);
                    }
                },

                .cube => {
                    cmd.setPipeline(&pass.pipelines[@TypeOf(pass.*).cube]);
                    const vert_off = @sizeOf(@TypeOf(model.plane.data));
                    cmd.setVertexBuffers(
                        0,
                        &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 3,
                        &.{
                            vert_off + @offsetOf(@TypeOf(model.cube.data), "position"),
                            vert_off + @offsetOf(@TypeOf(model.cube.data), "normal"),
                            vert_off + @offsetOf(@TypeOf(model.cube.data), "tex_coord"),
                        },
                        &.{
                            @sizeOf(@TypeOf(model.cube.data.position)),
                            @sizeOf(@TypeOf(model.cube.data.normal)),
                            @sizeOf(@TypeOf(model.cube.data.tex_coord)),
                        },
                    );
                    cmd.setIndexBuffer(
                        .u16,
                        &index_buffer.?.buffer,
                        0,
                        @sizeOf(@TypeOf(model.cube.indices)),
                    );
                    for (draws) |d| {
                        const set_off = frame * (1 + draw_n * 3) + 1 + d.index * 3;
                        const sets = descriptor.sets[set_off .. set_off + 3];
                        switch (@TypeOf(pass)) {
                            *Shading => cmd.setDescriptors(
                                .graphics,
                                &descriptor.pipeline_layout,
                                1,
                                &.{ &sets[0], &sets[1] },
                            ),
                            *Generation => cmd.setDescriptors(
                                .graphics,
                                &descriptor.pipeline_layout,
                                2,
                                &.{&sets[2]},
                            ),
                            else => unreachable,
                        }
                        cmd.drawIndexed(model.cube.indices.len, 1, 0, 0, 0);
                    }
                },
            }
        }
    };
}
