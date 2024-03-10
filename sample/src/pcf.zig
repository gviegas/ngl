const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const cube = &@import("model.zig").cube;
const plane = &@import("model.zig").plane;
const util = @import("util.zig");

pub fn main() !void {
    try do();
}

const frame_n = 2;
const width = Platform.width;
const height = Platform.height;
const materials = [_]UniformBuffer.Material{
    .{
        0.1, 0.0, 0,   undefined,
        1,   0,   0,   undefined,
        0.1, 0.1, 0.1, undefined,
        200,
    },
    .{
        0.0, 0,   0.05, undefined,
        0,   0,   0.6,  undefined,
        0.1, 0.1, 0.1,  undefined,
        100,
    },
};
const draws =
    [_]Draw{.{
    .model = .cube,
    .material = 0,
    .index_offset = 0,
    .vertex_offset = 0,
}} ** 3 ++ [_]Draw{.{
    .model = .plane,
    .material = 1,
    .index_offset = null,
    .vertex_offset = @sizeOf(@TypeOf(cube.data)),
}};

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var shdw_map = try ShadowMap.init();
    defer shdw_map.deinit();

    var shdw_pass = try ShadowPass.init(&shdw_map);
    defer shdw_pass.deinit();

    var col_attach = try ColorAttachment.init();
    defer col_attach.deinit();

    var dep_attach = try DepthAttachment.init(col_attach);
    defer dep_attach.deinit();

    var light_pass = try LightPass.init(&col_attach, &dep_attach);
    defer light_pass.deinit();

    var tex = try Texture.init();
    defer tex.deinit();

    var idx_buf = try IndexBuffer.init();
    defer idx_buf.deinit();

    var vert_buf = try VertexBuffer.init();
    defer vert_buf.deinit();

    var unif_buf = try UniformBuffer.init();
    defer unif_buf.deinit();

    var stg_buf = try StagingBuffer.init();
    defer stg_buf.deinit();

    var pl = try Pipeline.init(&shdw_map, &shdw_pass, &col_attach, &light_pass, &tex, &unif_buf);
    defer pl.deinit();

    var queue = try Queue.init();
    defer queue.deinit();

    var draw_xforms = blk: {
        var m: [draws.len][16]f32 = undefined;
        for (0..draws.len) |i| {
            m[i] = util.identity(4);
            switch (draws[i].model) {
                .cube => {
                    m[i][5] += @as(f32, @floatFromInt(i)) * 0.65;
                    m[i][10] += @as(f32, @floatFromInt(i)) * 0.35;
                    m[i][12] = @as(f32, @floatFromInt(i)) * 4;
                },
                .plane => {
                    m[i][0] = 50;
                    m[i][10] = 50;
                    m[i][13] = 1;
                },
            }
        }
        break :blk m;
    };

    const light_pos = [3]f32{ -16, -10, -4 };
    const shdw_v = util.lookAt(.{ 0, 0, 0 }, light_pos, .{ 0, -1, 0 });
    const shdw_p = util.frustum(-1, 1, -1, 1, 1, 100);
    const vps = util.mulM(4, .{
        0.5, 0,   0, 0,
        0,   0.5, 0, 0,
        0,   0,   1, 0,
        0.5, 0.5, 0, 1,
    }, util.mulM(4, shdw_p, shdw_v));
    const v = util.lookAt(.{ 4, 0, 0 }, .{ -2, -7, -7 }, .{ 0, -1, 0 });
    const p = util.perspective(std.math.pi / 3.0, @as(f32, width) / @as(f32, height), 0.01, 100);
    for (0..frame_n) |i| {
        unif_buf.updateLight(
            i,
            util.mulMV(4, v, light_pos ++ [_]f32{1}) ++ [3]f32{ 0.2, 0.2, 0.2 },
        );
        for (0..materials.len) |j|
            unif_buf.updateMaterial(i, j, materials[j]);
        for (0..draws.len) |j| {
            const m = draw_xforms[j];
            const s = util.mulM(4, vps, m);
            const mv = util.mulM(4, v, m);
            const mvp = util.mulM(4, p, mv);
            const n = blk: {
                const n = util.invert3(util.upperLeft(4, mv));
                break :blk [12]f32{
                    n[0], n[3], n[6], undefined,
                    n[1], n[4], n[7], undefined,
                    n[2], n[5], n[8], undefined,
                };
            };
            unif_buf.updateTransform(i, j, s ++ mvp ++ mv ++ n);
        }
    }
    const shdw_vp = util.mulM(4, shdw_p, shdw_v);
    for (&draw_xforms) |*xform| xform.* = util.mulM(4, shdw_vp, xform.*);

    try stg_buf.copy(&queue, &tex, &idx_buf, &vert_buf);

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;
    var timer = try std.time.Timer.start();
    const is_unified = queue.non_unified == null;

    while (timer.read() < std.time.ns_per_min) {
        if (plat.poll().done) break;

        const cmd_pool = &queue.pools[frame];
        const cmd_buf = &queue.buffers[frame];
        const fence = &queue.fences[frame];
        const semas = .{ &queue.semaphores[frame * 2], &queue.semaphores[frame * 2 + 1] };

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fence});
        try ngl.Fence.reset(gpa, dev, &.{fence});

        const next = try plat.swap_chain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try cmd_pool.reset(dev, .keep);
        var cmd = try cmd_buf.begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
        shdw_pass.record(&cmd, &pl, &idx_buf, &vert_buf, draw_xforms);
        light_pass.record(&cmd, next, &pl, &idx_buf, &vert_buf, frame);
        if (!is_unified) @panic("TODO");
        try cmd.end();

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

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 5, blk: {
        var fences: [frame_n]*ngl.Fence = undefined;
        for (0..fences.len) |i| fences[i] = &queue.fences[i];
        break :blk &fences;
    });
}

const ShadowMap = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const extent = 1024;

    fn init() ngl.Error!ShadowMap {
        const dev = &context().device;

        var filt: ngl.Sampler.Filter = undefined;
        var fmt: ngl.Format = undefined;
        for ([_]ngl.Format{
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            .x8_d24_unorm,
            .d24_unorm_s8_uint,
            .d16_unorm,
            .d16_unorm_s8_uint,
        }) |x| {
            const feats = x.getFeatures(dev).optimal_tiling;
            if (feats.sampled_image and feats.sampled_image_filter_linear and
                feats.depth_stencil_attachment)
            {
                filt = .linear;
                fmt = x;
                break;
            }
        } else {
            filt = .nearest;
            fmt = .d16_unorm;
        }

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = fmt,
            .width = extent,
            .height = extent,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment = true, .sampled_image = true },
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
            .compare = .less,
        });

        return .{
            .format = fmt,
            .image = image,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *ShadowMap) void {
        const dev = &context().device;
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
        self.* = undefined;
    }
};

const ShadowPass = struct {
    render_pass: ngl.RenderPass,
    frame_buffer: ngl.FrameBuffer,

    fn init(shadow_map: *ShadowMap) ngl.Error!ShadowPass {
        const dev = &context().device;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{.{
                .format = shadow_map.format,
                .samples = .@"1",
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .unknown,
                .final_layout = .shader_read_only_optimal,
                .resolve_mode = null,
                .combined = if (shadow_map.format.getAspectMask().stencil) .{
                    .stencil_load_op = .dont_care,
                    .stencil_store_op = .dont_care,
                } else null,
                .may_alias = false,
            }},
            .subpasses = &.{.{
                .pipeline_type = .graphics,
                .input_attachments = null,
                .color_attachments = null,
                .depth_stencil_attachment = .{
                    .index = 0,
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
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{
                        .early_fragment_tests = true,
                        .late_fragment_tests = true,
                    },
                    .dest_access_mask = .{
                        .depth_stencil_attachment_read = true,
                        .depth_stencil_attachment_write = true,
                    },
                    .by_region = false,
                },
                .{
                    .source_subpass = .{ .index = 0 },
                    .dest_subpass = .external,
                    .source_stage_mask = .{ .late_fragment_tests = true },
                    .source_access_mask = .{ .depth_stencil_attachment_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .by_region = false,
                },
            },
        });
        errdefer rp.deinit(gpa, dev);
        const fb = try ngl.FrameBuffer.init(gpa, dev, .{
            .render_pass = &rp,
            .attachments = &.{&shadow_map.view},
            .width = ShadowMap.extent,
            .height = ShadowMap.extent,
            .layers = 1,
        });

        return .{ .render_pass = rp, .frame_buffer = fb };
    }

    fn record(
        self: *ShadowPass,
        cmd: *ngl.Cmd,
        pipeline: *Pipeline,
        index_buffer: *IndexBuffer,
        vertex_buffer: *VertexBuffer,
        draw_transforms: [draws.len][16]f32,
    ) void {
        cmd.beginRenderPass(.{
            .render_pass = &self.render_pass,
            .frame_buffer = &self.frame_buffer,
            .render_area = .{
                .x = 0,
                .y = 0,
                .width = ShadowMap.extent,
                .height = ShadowMap.extent,
            },
            .clear_values = &.{.{ .depth_stencil = .{ 1, undefined } }},
        }, .{ .contents = .inline_only });

        for (draws, draw_transforms) |draw, xform| {
            cmd.setPipeline(&pipeline.shadow[@intFromEnum(draw.model)]);
            const s = @as([*]align(4) const u8, @ptrCast(&xform))[0..64];
            cmd.setPushConstants(&pipeline.pipeline_layout, .{ .vertex = true }, 0, s);
            draw.draw(cmd, index_buffer, vertex_buffer);
        }

        cmd.endRenderPass(.{});
    }

    fn deinit(self: *ShadowPass) void {
        const dev = &context().device;
        self.frame_buffer.deinit(gpa, dev);
        self.render_pass.deinit(gpa, dev);
    }
};

const ColorAttachment = struct {
    format: ngl.Format, // Same as `Platform.format.format`
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
            break :blk if (capabs.sample_counts.@"16")
                .@"16"
            else if (capabs.sample_counts.@"8")
                .@"8"
            else if (capabs.sample_counts.@"4")
                .@"4"
            else
                unreachable;
        };

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = width,
            .height = height,
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
            .format = fmt,
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
        self.* = undefined;
    }
};

const DepthAttachment = struct {
    format: ngl.Format,
    samples: ngl.SampleCount, // Same as `ColorAttachment.samples`
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init(color_attachment: ColorAttachment) ngl.Error!DepthAttachment {
        const dev = &context().device;

        const @"type" = ngl.Image.Type.@"2d";
        const spls = color_attachment.samples;
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
        }) |x| {
            const capabs = ngl.Image.getCapabilities(
                dev,
                @"type",
                x,
                tiling,
                usage,
                misc,
            ) catch |err| {
                if (err == ngl.Error.NotSupported)
                    continue;
                return err;
            };
            const U = @typeInfo(ngl.SampleCount.Flags).Struct.backing_integer.?;
            const mask: U = @bitCast(capabs.sample_counts);
            if ((@as(U, 1) << @intFromEnum(spls)) & mask != 0)
                break x;
        } else @panic("MS count mismatch"); // This seems very unlikely

        var image = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = width,
            .height = height,
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
                .aspect_mask = .{ .depth = true },
                .base_level = 0,
                .levels = 1,
                .base_layer = 0,
                .layers = 1,
            },
        });

        return .{
            .format = fmt,
            .samples = spls,
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
        self.* = undefined;
    }
};

const LightPass = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,

    fn init(
        color_attachment: *ColorAttachment,
        depth_attachment: *DepthAttachment,
    ) ngl.Error!LightPass {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{
                .{
                    .format = color_attachment.format,
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
                .{
                    .format = depth_attachment.format,
                    .samples = depth_attachment.samples,
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
            },
            .subpasses = &.{.{
                .pipeline_type = .graphics,
                .input_attachments = null,
                .color_attachments = &.{.{
                    .index = 0,
                    .layout = .color_attachment_optimal,
                    .aspect_mask = .{ .color = true },
                    .resolve = .{ .index = 1, .layout = .color_attachment_optimal },
                }},
                .depth_stencil_attachment = .{
                    .index = 2,
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
                    },
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
                    sc_view,
                    &depth_attachment.view,
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

    fn record(
        self: *LightPass,
        cmd: *ngl.Cmd,
        next_image: ngl.SwapChain.Index,
        pipeline: *Pipeline,
        index_buffer: *IndexBuffer,
        vertex_buffer: *VertexBuffer,
        frame: usize,
    ) void {
        cmd.beginRenderPass(
            .{
                .render_pass = &self.render_pass,
                .frame_buffer = &self.frame_buffers[next_image],
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                },
                .clear_values = &.{
                    .{ .color_f32 = .{ 0.6, 0.6, 0, 1 } },
                    null,
                    .{ .depth_stencil = .{ 1, undefined } },
                },
            },
            .{ .contents = .inline_only },
        );

        const set_off = Pipeline.set_n / frame_n * frame;
        cmd.setDescriptors(.graphics, &pipeline.pipeline_layout, 0, &.{&pipeline.sets[set_off]});

        for (draws, 0..) |draw, i| {
            cmd.setPipeline(&pipeline.light[@intFromEnum(draw.model)]);
            cmd.setDescriptors(
                .graphics,
                &pipeline.pipeline_layout,
                1,
                &.{&pipeline.sets[set_off + 1 + draw.material]},
            );
            cmd.setDescriptors(
                .graphics,
                &pipeline.pipeline_layout,
                2,
                &.{&pipeline.sets[set_off + 1 + materials.len + i]},
            );
            draw.draw(cmd, index_buffer, vertex_buffer);
        }

        cmd.endRenderPass(.{});
    }

    fn deinit(self: *LightPass) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        gpa.free(self.frame_buffers);
        self.render_pass.deinit(gpa, dev);
        self.* = undefined;
    }
};

const Texture = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    views: [materials.len]ngl.ImageView,
    sampler: ngl.Sampler,

    fn init() ngl.Error!Texture {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = .rgba8_unorm,
            .width = 1,
            .height = 1,
            .depth_or_layers = materials.len,
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
        var views: [materials.len]ngl.ImageView = undefined;
        for (0..views.len) |i|
            views[i] = ngl.ImageView.init(gpa, dev, .{
                .image = &image,
                .type = .@"2d",
                .format = .rgba8_unorm,
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
            .u_address = .repeat,
            .v_address = .repeat,
            .w_address = .repeat,
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
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *Texture) void {
        const dev = &context().device;
        for (&self.views) |*view| view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
        self.* = undefined;
    }
};

const IndexBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,

    fn init() ngl.Error!IndexBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = @sizeOf(@TypeOf(cube.indices)),
            .usage = .{ .index_buffer = true, .transfer_dest = true },
        });
        const mem = blk: {
            errdefer buf.deinit(gpa, dev);
            const mem_reqs = buf.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try buf.bind(dev, &mem, 0);
            break :blk mem;
        };

        return .{ .buffer = buf, .memory = mem };
    }

    fn deinit(self: *IndexBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.* = undefined;
    }
};

const VertexBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,

    fn init() ngl.Error!VertexBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = blk: {
                const cube_size = @sizeOf(@TypeOf(cube.data));
                if (cube_size & 3 != 0) unreachable;
                const plane_size = @sizeOf(@TypeOf(plane.data));
                if (plane_size & 3 != 0) unreachable;
                break :blk cube_size + plane_size;
            },
            .usage = .{ .vertex_buffer = true, .transfer_dest = true },
        });
        const mem = blk: {
            errdefer buf.deinit(gpa, dev);
            const mem_reqs = buf.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try buf.bind(dev, &mem, 0);
            break :blk mem;
        };

        return .{ .buffer = buf, .memory = mem };
    }

    fn deinit(self: *VertexBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.* = undefined;
    }
};

const UniformBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory, // Mapped
    data: []u8,

    // Per frame
    const stride = 256 * (1 + materials.len + draws.len);

    fn init() ngl.Error!UniformBuffer {
        const dev = &context().device;

        // We'll use a host accessible uniform buffer this time
        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = frame_n * stride,
            .usage = .{ .uniform_buffer = true },
        });
        var data: []u8 = undefined;
        const mem = blk: {
            errdefer buf.deinit(gpa, dev);
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
            data = (try mem.map(dev, 0, null))[0..mem_reqs.size];
            break :blk mem;
        };

        return .{
            .buffer = buf,
            .memory = mem,
            .data = data,
        };
    }

    const Light = [4 + 3]f32;

    fn updateLight(self: *UniformBuffer, frame: usize, data: Light) void {
        const p = @as([*]const u8, @ptrCast(&data));
        const off = frame * stride;
        @memcpy(self.data[off .. off + @sizeOf(Light)], p);
    }

    const Material = [4 + 4 + 4 + 1]f32;

    fn updateMaterial(self: *UniformBuffer, frame: usize, material: usize, data: Material) void {
        const p = @as([*]const u8, @ptrCast(&data));
        const off = frame * stride + 256 + material * 256;
        @memcpy(self.data[off .. off + @sizeOf(Material)], p);
    }

    const Transform = [16 + 16 + 16 + 12]f32;

    fn updateTransform(self: *UniformBuffer, frame: usize, draw: usize, data: Transform) void {
        const p = @as([*]const u8, @ptrCast(&data));
        const off = frame * stride + 256 + materials.len * 256 + draw * 256;
        @memcpy(self.data[off .. off + @sizeOf(Transform)], p);
    }

    fn deinit(self: *UniformBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.* = undefined;
    }
};

const StagingBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory, // Mapped
    data: []u8,

    fn init() ngl.Error!StagingBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = 1 << 20,
            .usage = .{ .transfer_source = true },
        });
        var data: []u8 = undefined;
        const mem = blk: {
            errdefer buf.deinit(gpa, dev);
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
            data = (try mem.map(dev, 0, null))[0..mem_reqs.size];
            break :blk mem;
        };

        return .{
            .buffer = buf,
            .memory = mem,
            .data = data,
        };
    }

    // Will lock the graphics queue and wait on fence 0
    // `Texture.image` will be transitioned to `shader_read_only_optimal`
    fn copy(
        self: *StagingBuffer,
        queue: *Queue,
        texture: *Texture,
        index_buffer: *IndexBuffer,
        vertex_buffer: *VertexBuffer,
    ) ngl.Error!void {
        const ctx = context();
        const dev = &ctx.device;

        const a = 256;
        var s = self.data;

        const pixels = [_][4]u8{.{ 255, 255, 255, 255 }} ** materials.len;
        for (pixels) |px| {
            @memcpy(s[0..4], &px);
            s = s[a..];
        }

        const indices = blk: {
            const p = @as([*]const u8, @ptrCast(&cube.indices));
            break :blk p[0..@sizeOf(@TypeOf(cube.indices))];
        };
        @memcpy(s[0..indices.len], indices);
        s = s[(indices.len + a - 1) & ~@as(u64, a - 1) ..];

        const vertices = blk: {
            const cube_p = @as([*]const u8, @ptrCast(&cube.data));
            const plane_p = @as([*]const u8, @ptrCast(&plane.data));
            break :blk .{
                cube_p[0..@sizeOf(@TypeOf(cube.data))],
                plane_p[0..@sizeOf(@TypeOf(plane.data))],
            };
        };
        @memcpy(s[0..vertices[0].len], vertices[0]);
        s = s[vertices[0].len..];
        @memcpy(s[0..vertices[1].len], vertices[1]);
        s = s[(vertices[1].len + a - 1) & ~@as(u64, a - 1) ..];

        try queue.pools[0].reset(dev, .keep);
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
                .image = &texture.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = materials.len,
                },
            }},
            .by_region = false,
        }});
        cmd.copyBufferToImage(&.{.{
            .buffer = &self.buffer,
            .image = &texture.image,
            .image_layout = .transfer_dest_optimal,
            .image_type = .@"2d",
            .regions = blk: {
                var regs: [materials.len]ngl.Cmd.BufferImageCopy.Region = undefined;
                for (&regs, 0..) |*reg, i|
                    reg.* = .{
                        .buffer_offset = i * a,
                        .buffer_row_length = 1,
                        .buffer_image_height = 1,
                        .image_aspect = .color,
                        .image_level = 0,
                        .image_x = 0,
                        .image_y = 0,
                        .image_z_or_layer = @intCast(i),
                        .image_width = 1,
                        .image_height = 1,
                        .image_depth_or_layers = 1,
                    };
                break :blk &regs;
            },
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
                .image = &texture.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = materials.len,
                },
            }},
            .by_region = false,
        }});
        cmd.copyBuffer(&.{
            .{
                .source = &self.buffer,
                .dest = &index_buffer.buffer,
                .regions = &.{.{
                    .source_offset = materials.len * a,
                    .dest_offset = 0,
                    .size = indices.len,
                }},
            },
            .{
                .source = &self.buffer,
                .dest = &vertex_buffer.buffer,
                .regions = &.{.{
                    .source_offset = (materials.len * a + indices.len + a - 1) & ~@as(u64, a - 1),
                    .dest_offset = 0,
                    .size = vertices[0].len + vertices[1].len,
                }},
            },
        });
        try cmd.end();

        ctx.lockQueue(queue.graphics);
        defer ctx.unlockQueue(queue.graphics);

        try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
        try dev.queues[queue.graphics].submit(gpa, dev, &queue.fences[0], &.{.{
            .commands = &.{.{ .command_buffer = &queue.buffers[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&queue.fences[0]});
    }

    fn deinit(self: *StagingBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.* = undefined;
    }
};

const Pipeline = struct {
    shadow: [2]ngl.Pipeline,
    light: [2]ngl.Pipeline,
    set_layouts: [3]ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [set_n]ngl.DescriptorSet,

    const cube_model: u1 = 0;
    const plane_model: u1 = 1;

    // One for shadow and light, plus one for each kind
    // of material plus one for each draw call
    const set_n = frame_n * (1 + materials.len + draws.len);

    const shdw_map_vert_spv align(4) = @embedFile("shader/pcf/shdw_map.vert.spv").*;
    const shd_vert_spv align(4) = @embedFile("shader/pcf/shd.vert.spv").*;
    const shd_frag_spv align(4) = @embedFile("shader/pcf/shd.frag.spv").*;

    fn init(
        shadow_map: *ShadowMap,
        shadow_pass: *ShadowPass,
        color_attachment: *ColorAttachment,
        light_pass: *LightPass,
        texture: *Texture,
        uniform_buffer: *UniformBuffer,
    ) ngl.Error!Pipeline {
        const ctx = context();
        const gpu = ctx.gpu;
        const dev = &ctx.device;

        var set_layts: [3]ngl.DescriptorSetLayout = undefined;
        set_layts[0] = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
            .{
                .binding = 0,
                .type = .combined_image_sampler,
                .count = 1,
                .stage_mask = .{ .fragment = true },
                .immutable_samplers = &.{&shadow_map.sampler},
            },
            .{
                .binding = 1,
                .type = .uniform_buffer,
                .count = 1,
                .stage_mask = .{ .fragment = true },
                .immutable_samplers = null,
            },
        } });
        errdefer set_layts[0].deinit(gpa, dev);
        set_layts[1] = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = 0,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&texture.sampler},
                },
                .{
                    .binding = 1,
                    .type = .uniform_buffer,
                    .count = 1,
                    .stage_mask = .{ .fragment = true },
                    .immutable_samplers = null,
                },
            },
        });
        errdefer set_layts[1].deinit(gpa, dev);
        set_layts[2] = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
            .binding = 0,
            .type = .uniform_buffer,
            .count = 1,
            .stage_mask = .{ .vertex = true },
            .immutable_samplers = null,
        }} });
        errdefer set_layts[2].deinit(gpa, dev);
        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{
                &set_layts[0],
                &set_layts[1],
                &set_layts[2],
            },
            .push_constant_ranges = &.{.{
                .offset = 0,
                .size = 64,
                .stage_mask = .{ .vertex = true },
            }},
        });
        errdefer pl_layt.deinit(gpa, dev);

        var shdw_state_params: [2]struct {
            topology: ngl.Primitive.Topology,
            cull_mode: ngl.Rasterization.CullMode,
            clockwise: bool,
        } = undefined;
        shdw_state_params[cube_model] = .{
            .topology = cube.topology,
            .cull_mode = .front,
            .clockwise = cube.clockwise,
        };
        shdw_state_params[plane_model] = .{
            .topology = plane.topology,
            .cull_mode = .back,
            .clockwise = plane.clockwise,
        };
        var shdw_states: [2]ngl.GraphicsState = undefined;
        inline for (&shdw_states, shdw_state_params) |*state, params|
            state.* = .{
                .stages = &.{.{
                    .stage = .vertex,
                    .code = &shdw_map_vert_spv,
                    .name = "main",
                }},
                .layout = &pl_layt,
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
                    .topology = params.topology,
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
                    .cull_mode = params.cull_mode,
                    .clockwise = params.clockwise,
                    .depth_bias = .{
                        .value = 0.01,
                        .slope = 3,
                        .clamp = if (ngl.Feature.get(
                            gpa,
                            gpu,
                            .core,
                        ).?.rasterization.depth_bias_clamp) 1 else null,
                    },
                    .samples = .@"1",
                },
                .depth_stencil = &.{
                    .depth_compare = .less_equal,
                    .depth_write = true,
                    .stencil_front = null,
                    .stencil_back = null,
                },
                .color_blend = null,
                .render_pass = &shadow_pass.render_pass,
                .subpass = 0,
            };

        var light_state_params: [2]struct {
            topology: ngl.Primitive.Topology,
            clockwise: bool,
        } = undefined;
        light_state_params[cube_model] = .{
            .topology = cube.topology,
            .clockwise = cube.clockwise,
        };
        light_state_params[plane_model] = .{
            .topology = plane.topology,
            .clockwise = plane.clockwise,
        };
        var light_states: [2]ngl.GraphicsState = undefined;
        inline for (&light_states, light_state_params) |*state, params|
            state.* = .{
                .stages = &.{
                    .{
                        .stage = .vertex,
                        .code = &shd_vert_spv,
                        .name = "main",
                    },
                    .{
                        .stage = .fragment,
                        .code = &shd_frag_spv,
                        .name = "main",
                    },
                },
                .layout = &pl_layt,
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
                    .topology = params.topology,
                },
                .viewport = &.{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                    .near = 0,
                    .far = 1,
                },
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = params.clockwise,
                    .samples = color_attachment.samples,
                },
                .depth_stencil = &.{
                    .depth_compare = .less_equal,
                    .depth_write = true,
                    .stencil_front = null,
                    .stencil_back = null,
                },
                .color_blend = &.{
                    .attachments = &.{.{ .blend = null, .write = .all }},
                    .constants = .unused,
                },
                .render_pass = &light_pass.render_pass,
                .subpass = 0,
            };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &shdw_states ++ &light_states,
            .cache = null,
        });
        var shdw_pls = pls[0..2].*;
        var light_pls = pls[2..4].*;
        gpa.free(pls);
        errdefer for (&shdw_pls ++ &light_pls) |*pl| pl.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = set_n,
            .pool_size = .{
                .combined_image_sampler = set_n - frame_n,
                .uniform_buffer = set_n,
            },
        });
        errdefer pool.deinit(gpa, dev);
        var sets = blk: {
            const l0 = [_]*ngl.DescriptorSetLayout{&set_layts[0]};
            const l1 = [_]*ngl.DescriptorSetLayout{&set_layts[1]} ** materials.len;
            const l2 = [_]*ngl.DescriptorSetLayout{&set_layts[2]} ** draws.len;
            const frame: [set_n / frame_n]*ngl.DescriptorSetLayout = l0 ++ l1 ++ l2;
            const layts: [set_n]*ngl.DescriptorSetLayout = frame ** frame_n;
            var s = try pool.alloc(gpa, dev, .{ .layouts = &layts });
            defer gpa.free(s);
            break :blk s[0..set_n].*;
        };
        const writes = blk: {
            var is_writes = [_]ngl.DescriptorSet.Write.ImageSamplerWrite{undefined} **
                (frame_n * (1 + materials.len));
            var buf_writes = [_]ngl.DescriptorSet.Write.BufferWrite{undefined} **
                (frame_n * (1 + materials.len + draws.len));
            var writes: [is_writes.len + buf_writes.len]ngl.DescriptorSet.Write = undefined;
            var iw: []ngl.DescriptorSet.Write.ImageSamplerWrite = is_writes[0..];
            var bw: []ngl.DescriptorSet.Write.BufferWrite = buf_writes[0..];
            var w: []ngl.DescriptorSet.Write = writes[0..];
            var s: []ngl.DescriptorSet = sets[0..];
            var off: u64 = 0;
            for (0..frame_n) |_| {
                // Shadow image/sampler (set 0)
                iw[0] = .{
                    .view = &shadow_map.view,
                    .layout = .shader_read_only_optimal,
                    .sampler = null, // Immutable sampler
                };
                w[0] = .{
                    .descriptor_set = &s[0],
                    .binding = 0,
                    .element = 0,
                    .contents = .{ .combined_image_sampler = iw[0..1] },
                };
                // Light uniform (set 0)
                bw[0] = .{
                    .buffer = &uniform_buffer.buffer,
                    .offset = off,
                    .range = @sizeOf(UniformBuffer.Light),
                };
                w[1] = .{
                    .descriptor_set = &s[0],
                    .binding = 1,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };
                iw = iw[1..];
                bw = bw[1..];
                w = w[2..];
                s = s[1..];
                off += 256;
                for (0..materials.len) |i| {
                    // Base color texture/sampler (set 1)
                    iw[0] = .{
                        .view = &texture.views[i],
                        .layout = .shader_read_only_optimal,
                        .sampler = null, // Immutable sampler
                    };
                    w[0] = .{
                        .descriptor_set = &s[0],
                        .binding = 0,
                        .element = 0,
                        .contents = .{ .combined_image_sampler = iw[0..1] },
                    };
                    // Material uniform (set 1)
                    bw[0] = .{
                        .buffer = &uniform_buffer.buffer,
                        .offset = off,
                        .range = @sizeOf(UniformBuffer.Material),
                    };
                    w[1] = .{
                        .descriptor_set = &s[0],
                        .binding = 1,
                        .element = 0,
                        .contents = .{ .uniform_buffer = bw[0..1] },
                    };
                    iw = iw[1..];
                    bw = bw[1..];
                    w = w[2..];
                    s = s[1..];
                    off += 256;
                }
                for (0..draws.len) |_| {
                    // Transform uniform (set 2)
                    bw[0] = .{
                        .buffer = &uniform_buffer.buffer,
                        .offset = off,
                        .range = @sizeOf(UniformBuffer.Transform),
                    };
                    w[0] = .{
                        .descriptor_set = &s[0],
                        .binding = 0,
                        .element = 0,
                        .contents = .{ .uniform_buffer = bw[0..1] },
                    };
                    bw = bw[1..];
                    w = w[1..];
                    s = s[1..];
                    off += 256;
                }
            }
            break :blk writes;
        };
        try ngl.DescriptorSet.write(gpa, dev, &writes);

        return .{
            .shadow = shdw_pls,
            .light = light_pls,
            .set_layouts = set_layts,
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn deinit(self: *Pipeline) void {
        const dev = &context().device;
        for (&self.shadow ++ &self.light) |*pl| pl.deinit(gpa, dev);
        for (&self.set_layouts) |*layt| layt.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
        self.* = undefined;
    }
};

const Queue = struct {
    graphics: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
    fences: [frame_n]ngl.Fence, // Signaled
    non_unified: ?struct {
        present: ngl.Queue.Index, // Same as `Platform.queue_index`
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

        const non_unified: @TypeOf((try init()).non_unified) = blk: {
            if (graph == pres)
                break :blk null;
            var pools: [frame_n]ngl.CommandPool = undefined;
            for (0..pools.len) |i|
                pools[i] = ngl.CommandPool.init(
                    gpa,
                    dev,
                    .{ .queue = &dev.queues[pres] },
                ) catch |err| {
                    for (0..i) |j| pools[j].deinit(gpa, dev);
                    return err;
                };
            errdefer for (&pools) |*pool| pool.deinit(gpa, dev);
            var bufs: [frame_n]ngl.CommandBuffer = undefined;
            for (0..bufs.len) |i| {
                const s = try pools[i].alloc(gpa, dev, .{ .level = .primary, .count = 1 });
                bufs[i] = s[0];
                gpa.free(s);
            }
            var semas: [frame_n]ngl.Semaphore = undefined;
            for (0..semas.len) |i|
                semas[i] = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
                    for (0..i) |j| semas[j].deinit(gpa, dev);
                    return err;
                };
            break :blk .{
                .present = plat.queue_index,
                .pools = pools,
                .buffers = bufs,
                .semaphores = semas,
            };
        };
        errdefer if (non_unified) |x| {
            errdefer for (&x.pools) |*pool| pool.deinit(gpa, dev);
            errdefer for (&x.semaphores) |*sema| sema.deinit(gpa, dev);
        };

        var pools: [frame_n]ngl.CommandPool = undefined;
        for (0..pools.len) |i|
            pools[i] = ngl.CommandPool.init(
                gpa,
                dev,
                .{ .queue = &dev.queues[graph] },
            ) catch |err| {
                for (0..i) |j| pools[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&pools) |*pool| pool.deinit(gpa, dev);
        var bufs: [frame_n]ngl.CommandBuffer = undefined;
        for (0..bufs.len) |i| {
            const s = try pools[i].alloc(gpa, dev, .{ .level = .primary, .count = 1 });
            bufs[i] = s[0];
            gpa.free(s);
        }
        var semas: [frame_n * 2]ngl.Semaphore = undefined;
        for (0..semas.len) |i|
            semas[i] = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
                for (0..i) |j| semas[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&semas) |*sema| sema.deinit(gpa, dev);
        var fences: [frame_n]ngl.Fence = undefined;
        for (0..fences.len) |i|
            fences[i] = ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled }) catch |err| {
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
        self.* = undefined;
    }
};

const Draw = struct {
    model: enum { cube, plane },
    material: usize,
    index_offset: ?u64,
    vertex_offset: u64,

    fn draw(
        self: Draw,
        cmd: *ngl.Cmd,
        index_buffer: *IndexBuffer,
        vertex_buffer: *VertexBuffer,
    ) void {
        switch (self.model) {
            .cube => {
                cmd.setIndexBuffer(
                    cube.index_type,
                    &index_buffer.buffer,
                    self.index_offset.?,
                    @sizeOf(@TypeOf(cube.indices)),
                );
                cmd.setVertexBuffers(
                    0,
                    &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 3,
                    &.{
                        self.vertex_offset + @offsetOf(@TypeOf(cube.data), "position"),
                        self.vertex_offset + @offsetOf(@TypeOf(cube.data), "normal"),
                        self.vertex_offset + @offsetOf(@TypeOf(cube.data), "tex_coord"),
                    },
                    &.{
                        @sizeOf(@TypeOf(cube.data.position)),
                        @sizeOf(@TypeOf(cube.data.normal)),
                        @sizeOf(@TypeOf(cube.data.tex_coord)),
                    },
                );
                cmd.drawIndexed(cube.indices.len, 1, 0, 0, 0);
            },
            .plane => {
                cmd.setVertexBuffers(
                    0,
                    &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 3,
                    &.{
                        self.vertex_offset + @offsetOf(@TypeOf(plane.data), "position"),
                        self.vertex_offset + @offsetOf(@TypeOf(plane.data), "normal"),
                        self.vertex_offset + @offsetOf(@TypeOf(plane.data), "tex_coord"),
                    },
                    &.{
                        @sizeOf(@TypeOf(plane.data.position)),
                        @sizeOf(@TypeOf(plane.data.normal)),
                        @sizeOf(@TypeOf(plane.data.tex_coord)),
                    },
                );
                cmd.draw(plane.vertex_count, 1, 0, 0);
            },
        }
    }
};
