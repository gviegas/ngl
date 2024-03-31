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
const width = Platform.width;
const height = Platform.height;

const light = Light{
    .lights = .{.{
        .position = .{ 0, -4, 3 },
        .color = .{ 1, 1, 1 },
        .intensity = 30,
    }},
};

const materials = [_]Material{
    .{
        .metallic = 1,
        .roughness = 0.15,
        .reflectance = 0,
    },
    .{
        .metallic = 1,
        .roughness = 1,
        .reflectance = 0,
    },
    .{
        .metallic = 0,
        .roughness = 0.7,
        .reflectance = 0.5,
    },
    .{
        .metallic = 0,
        .roughness = 0.1,
        .reflectance = 0.5,
    },
    .{
        .metallic = 0,
        .roughness = 0.5,
        .reflectance = 0.25,
    },
    .{
        .metallic = 0,
        .roughness = 0.5,
        .reflectance = 1,
    },
};

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    var col_attach = try ColorAttachment.init();
    defer col_attach.deinit();

    var dep_attach = try DepthAttachment.init(col_attach.samples);
    defer dep_attach.deinit();

    var pass = try Pass.init(&col_attach, &dep_attach);
    defer pass.deinit();

    var tex = try Texture.init();
    defer tex.deinit();

    var unif_buf = try UniformBuffer.init();
    defer unif_buf.deinit();

    var vert_buf = try VertexBuffer.init();
    defer vert_buf.deinit();

    const stg_size = Texture.size + UniformBuffer.size + vert_buf.model.vertexSize();
    var stg_buf = try StagingBuffer.init(stg_size);
    defer stg_buf.deinit();

    var desc = try Descriptor.init();
    defer desc.deinit();

    var pl = try Pipeline.init(&pass, &desc, col_attach.samples);
    defer pl.deinit();

    var queue = try Queue.init();
    defer queue.deinit();

    try desc.write(&tex, &unif_buf);

    const tex_regs = tex.copy(&stg_buf, 0);

    const eye = [3]f32{ 3, -3, 3 };
    const asp_ratio = @as(f32, width) / @as(f32, height);
    const m = util.identity(4);
    const v = util.lookAt(.{ 0, 0, 0 }, eye, .{ 0, -1, 0 });
    const p = util.perspective(std.math.pi / 3.0, asp_ratio, 0.01, 100);
    const globl = Global{
        .vp = util.mulM(4, p, v),
        .m = m,
        .n = util.transpose(3, util.invert3(util.upperLeft(4, m))),
        .eye = eye,
    };

    var ub_regs: [frame_n * (2 + materials.len)]ngl.Cmd.BufferCopy.Region = undefined;
    for (0..frame_n) |frame| {
        const i = frame * (2 + materials.len);
        ub_regs[i] = globl.copy(frame, &stg_buf, Texture.size);
        ub_regs[i + 1] = light.copy(frame, &stg_buf, Texture.size);
        for (materials, 0..) |matl, j|
            ub_regs[i + 2 + j] = matl.copy(frame, j, &stg_buf, Texture.size);
    }

    const vb_reg = vert_buf.copy(&stg_buf, Texture.size + UniformBuffer.size);

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
                .base_level = 0,
                .levels = Texture.levels,
                .base_layer = 0,
                .layers = 1,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBufferToImage(&.{.{
        .buffer = &stg_buf.buffer,
        .image = &tex.image,
        .image_layout = .transfer_dest_optimal,
        .image_type = .@"2d",
        .regions = &tex_regs,
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
            .image = &tex.image,
            .range = .{
                .aspect_mask = .{ .color = true },
                .base_level = 0,
                .levels = Texture.levels,
                .base_layer = 0,
                .layers = 1,
            },
        }},
        .by_region = false,
    }});
    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf.buffer,
            .dest = &unif_buf.buffer,
            .regions = &ub_regs,
        },
        .{
            .source = &stg_buf.buffer,
            .dest = &vert_buf.buffer,
            .regions = &.{vb_reg},
        },
    });
    try cmd.end();
    {
        ctx.lockQueue(queue.graphics);
        defer ctx.unlockQueue(queue.graphics);

        try ngl.Fence.reset(gpa, dev, &.{&queue.fences[0]});
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
    var material: usize = 0;
    var auto: bool = true;
    var timer = try std.time.Timer.start();
    var timer_2 = try std.time.Timer.start();
    const is_unified = queue.non_unified == null;

    while (timer.read() < std.time.ns_per_min) {
        const input = plat.poll();
        if (input.done) break;
        if (auto and timer_2.read() > std.time.ns_per_ms * 1200) {
            material = (material + 1) % materials.len;
            timer_2.reset();
        }
        if (input.right) {
            auto = false;
            material = @min(material + 1, materials.len - 1);
        }
        if (input.left) {
            auto = false;
            material -|= 1;
        }

        const cmd_pool = &queue.pools[frame];
        const cmd_buf = &queue.buffers[frame];
        const fence = &queue.fences[frame];
        const semas = .{ &queue.semaphores[frame * 2], &queue.semaphores[frame * 2 + 1] };

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fence});
        try ngl.Fence.reset(gpa, dev, &.{fence});

        const next = try plat.swap_chain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });
        pass.record(&cmd, next, &pl, &desc, material, &vert_buf, frame);
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
        inline for (0..fences.len) |i| fences[i] = &queue.fences[i];
        break :blk &fences;
    });
}

const ColorAttachment = struct {
    format: ngl.Format,
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
            inline for (.{ "32", "16", "8", "4" }) |spl| {
                if (@field(capabs.sample_counts, spl))
                    break :blk @field(ngl.SampleCount, spl);
            } else unreachable;
        };

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
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
    }
};

const DepthAttachment = struct {
    format: ngl.Format,
    samples: ngl.SampleCount,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init(samples: ngl.SampleCount) ngl.Error!DepthAttachment {
        const dev = &context().device;

        const @"type" = .@"2d";
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
            const U = @typeInfo(ngl.SampleCount.Flags).Struct.backing_integer.?;
            const mask: U = @bitCast(capabs.sample_counts);
            if ((@as(U, 1) << @intFromEnum(samples)) & mask != 0)
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
            .samples = samples,
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

    fn record(
        self: *Pass,
        cmd: *ngl.Cmd,
        next_image: ngl.SwapChain.Index,
        pipeline: *Pipeline,
        descriptor: *Descriptor,
        material: usize,
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
                    .{ .color_f32 = .{ 0.6, 0.6, 0, 1.0 } },
                    .{ .depth_stencil = .{ 1, undefined } },
                    null,
                },
            },
            .{ .contents = .inline_only },
        );

        cmd.setPipeline(&pipeline.pipeline);

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

        cmd.setDescriptors(.graphics, &descriptor.pipeline_layout, 0, &.{
            &descriptor.sets[frame],
            &descriptor.sets[frame_n + frame * materials.len + material],
        });

        cmd.setVertexBuffers(
            0,
            &[_]*ngl.Buffer{&vertex_buffer.buffer} ** 3,
            &.{
                0,
                vertex_buffer.model.positionSize(),
                vertex_buffer.model.positionSize() + vertex_buffer.model.normalSize(),
            },
            &.{
                vertex_buffer.model.positionSize(),
                vertex_buffer.model.normalSize(),
                vertex_buffer.model.texCoordSize(),
            },
        );

        cmd.draw(vertex_buffer.model.vertexCount(), 1, 0, 0);

        cmd.endRenderPass(.{});
    }

    fn deinit(self: *Pass) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        gpa.free(self.frame_buffers);
        self.render_pass.deinit(gpa, dev);
    }
};

const Texture = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const size = 4 * extent * extent * 2;
    const format = ngl.Format.rgba8_unorm;
    const extent = 1024;
    const levels = blk: {
        var lvls = 1;
        while (extent >> lvls != 0) : (lvls += 1) {}
        break :blk lvls;
    };

    fn copy(
        _: Texture,
        staging_buffer: *StagingBuffer,
        offset: u64,
    ) [levels]ngl.Cmd.BufferImageCopy.Region {
        std.debug.assert(offset & 3 == 0);

        // TODO
        const pixel = [4]u8{ 206, 200, 194, 255 };
        var row: [extent * 4]u8 = undefined;
        for (0..extent) |i|
            @memcpy(row[i * 4 .. i * 4 + 4], &pixel);

        var regions: [levels]ngl.Cmd.BufferImageCopy.Region = undefined;

        // LOD 0.
        for (0..extent) |i|
            @memcpy(staging_buffer.data[offset + row.len * i .. offset + row.len * (i + 1)], &row);
        regions[0] = .{
            .buffer_offset = offset,
            .buffer_row_length = extent,
            .buffer_image_height = extent,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = extent,
            .image_height = extent,
            .image_depth_or_layers = 1,
        };

        // TODO: This only works because we are using a solid color.
        {
            const copy_sz = extent * extent * 4;
            const source_off = offset;
            const dest_off = offset + copy_sz;
            @memcpy(
                staging_buffer.data[dest_off .. dest_off + copy_sz],
                staging_buffer.data[source_off .. source_off + copy_sz],
            );
        }

        // LOD [1..levels).
        for (1..levels) |i| {
            const prev = &regions[i - 1];
            regions[i] = .{
                .buffer_offset = prev.buffer_offset +
                    prev.buffer_row_length * prev.buffer_image_height * 4,
                .buffer_row_length = @max(prev.buffer_row_length / 2, 1),
                .buffer_image_height = @max(prev.buffer_image_height / 2, 1),
                .image_aspect = .color,
                .image_level = @intCast(i),
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 0,
                .image_width = @max(prev.image_width / 2, 1),
                .image_height = @max(prev.image_height / 2, 1),
                .image_depth_or_layers = 1,
            };
        }

        return regions;
    }

    fn init() ngl.Error!Texture {
        const dev = &context().device;

        var image = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 1,
            .levels = levels,
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
                .base_level = 0,
                .levels = levels,
                .base_layer = 0,
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

const UniformBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,

    const size = frame_n * (2 + materials.len) * 256;

    fn init() ngl.Error!UniformBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = size,
            .usage = .{ .uniform_buffer = true, .transfer_dest = true },
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

        return .{
            .buffer = buf,
            .memory = mem,
        };
    }

    fn deinit(self: *UniformBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const VertexBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,
    // TODO: This should be loaded into GPU memory directly.
    model: model.Model,

    fn copy(
        self: VertexBuffer,
        staging_buffer: *StagingBuffer,
        offset: u64,
    ) ngl.Cmd.BufferCopy.Region {
        std.debug.assert(offset & 3 == 0);

        var off = offset;
        var size = self.model.positionSize();
        @memcpy(
            staging_buffer.data[off .. off + size],
            @as([*]const u8, @ptrCast(self.model.positions.items.ptr))[0..size],
        );
        off += size;
        size = self.model.normalSize();
        @memcpy(
            staging_buffer.data[off .. off + size],
            @as([*]const u8, @ptrCast(self.model.normals.items.ptr))[0..size],
        );
        off += size;
        size = self.model.texCoordSize();
        @memcpy(
            staging_buffer.data[off .. off + size],
            @as([*]const u8, @ptrCast(self.model.tex_coords.items.ptr))[0..size],
        );

        return .{
            .source_offset = offset,
            .dest_offset = 0,
            .size = self.model.vertexSize(),
        };
    }

    fn init() ngl.Error!VertexBuffer {
        const dev = &context().device;

        var mdl = model.loadObj(gpa, "data/geometry/sphere.obj") catch |err| {
            std.log.err("Failed to load model ({s})", .{@errorName(err)});
            return error.Other;
        };
        errdefer mdl.deinit();

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = mdl.vertexSize(),
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

        return .{
            .buffer = buf,
            .memory = mem,
            .model = mdl,
        };
    }

    fn deinit(self: *VertexBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.model.deinit();
    }
};

const StagingBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,
    data: []u8,

    fn init(size: u64) ngl.Error!StagingBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = size,
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
            data = (try mem.map(dev, 0, size))[0..size];
            break :blk mem;
        };

        return .{
            .buffer = buf,
            .memory = mem,
            .data = data,
        };
    }

    fn deinit(self: *StagingBuffer) void {
        const dev = &context().device;
        self.buffer.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
    }
};

const Descriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [set_n]ngl.DescriptorSet,

    const set_n = frame_n * (1 + materials.len);

    fn init() ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layts: [2]ngl.DescriptorSetLayout = undefined;
        set_layts[0] = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
            .{
                .binding = 0,
                .type = .uniform_buffer,
                .count = 1,
                .stage_mask = .{ .vertex = true, .fragment = true },
                .immutable_samplers = null,
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
        set_layts[1] = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
            .{
                .binding = 0,
                .type = .combined_image_sampler,
                .count = 1,
                .stage_mask = .{ .fragment = true },
                .immutable_samplers = null,
            },
            .{
                .binding = 1,
                .type = .uniform_buffer,
                .count = 1,
                .stage_mask = .{ .fragment = true },
                .immutable_samplers = null,
            },
        } });
        errdefer set_layts[1].deinit(gpa, dev);
        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{ &set_layts[0], &set_layts[1] },
            .push_constant_ranges = null,
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = set_n,
            .pool_size = .{
                .uniform_buffer = frame_n * (2 + materials.len),
                .combined_image_sampler = frame_n * materials.len,
            },
        });
        errdefer pool.deinit(gpa, dev);
        const sets = blk: {
            const layts_0 = [_]*ngl.DescriptorSetLayout{&set_layts[0]} ** frame_n;
            const layts_1 = [_]*ngl.DescriptorSetLayout{&set_layts[1]} ** (frame_n * materials.len);
            const sets = try pool.alloc(gpa, dev, .{ .layouts = &layts_0 ++ &layts_1 });
            defer gpa.free(sets);
            break :blk sets[0..set_n].*;
        };

        return .{
            .set_layouts = set_layts,
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn write(self: *Descriptor, texture: *Texture, uniform_buffer: *UniformBuffer) ngl.Error!void {
        var is: [frame_n * materials.len]ngl.DescriptorSet.Write.ImageSamplerWrite = undefined;
        var ub: [frame_n * (2 + materials.len)]ngl.DescriptorSet.Write.BufferWrite = undefined;
        var w: [is.len + ub.len]ngl.DescriptorSet.Write = undefined;
        for (&is) |*x|
            x.* = .{
                .view = &texture.view,
                .layout = .shader_read_only_optimal,
                .sampler = &texture.sampler,
            };
        for (&ub, 0..) |*x, i|
            x.* = .{
                .buffer = &uniform_buffer.buffer,
                .offset = 256 * i,
                .range = 256,
            };
        for (w[0..is.len], self.sets[frame_n..], 0..) |*x, *set, i|
            x.* = .{
                .descriptor_set = set,
                .binding = 0,
                .element = 0,
                .contents = .{ .combined_image_sampler = is[i .. i + 1] },
            };
        for (0..frame_n) |i| {
            w[is.len + i * 2] = .{
                .descriptor_set = &self.sets[i],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = ub[i * 2 .. i * 2 + 1] },
            };
            w[is.len + i * 2 + 1] = .{
                .descriptor_set = &self.sets[i],
                .binding = 1,
                .element = 0,
                .contents = .{ .uniform_buffer = ub[i * 2 + 1 .. i * 2 + 2] },
            };
            for (0..materials.len) |j| {
                const k = i * materials.len + j;
                w[is.len + frame_n * 2 + k] = .{
                    .descriptor_set = &self.sets[frame_n + k],
                    .binding = 1,
                    .element = 0,
                    .contents = .{ .uniform_buffer = ub[frame_n * 2 + k .. frame_n * 2 + k + 1] },
                };
            }
        }
        try ngl.DescriptorSet.write(gpa, &context().device, &w);
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        for (&self.set_layouts) |*layt| layt.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Pipeline = struct {
    pipeline: ngl.Pipeline,

    const vert_spv align(4) = @embedFile("shader/pbr/vert.spv").*;
    const frag_spv align(4) = @embedFile("shader/pbr/frag.spv").*;

    fn init(pass: *Pass, descriptor: *Descriptor, samples: ngl.SampleCount) ngl.Error!Pipeline {
        const stages = [2]ngl.ShaderStage.Desc{
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
        };

        const prim = ngl.Primitive{
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
            .topology = .triangle_list,
        };

        const raster = ngl.Rasterization{
            .polygon_mode = .fill,
            .cull_mode = .back,
            .clockwise = false,
            .samples = samples,
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

        const pl = try ngl.Pipeline.initGraphics(gpa, &context().device, .{
            .states = &.{.{
                .stages = &stages,
                .layout = &descriptor.pipeline_layout,
                .primitive = &prim,
                .rasterization = &raster,
                .depth_stencil = &ds,
                .color_blend = &blend,
                .render_pass = &pass.render_pass,
                .subpass = 0,
            }},
            .cache = null,
        });
        defer gpa.free(pl);

        return .{ .pipeline = pl[0] };
    }

    fn deinit(self: *Pipeline) void {
        self.pipeline.deinit(gpa, &context().device);
    }
};

const Queue = struct {
    graphics: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    fences: [frame_n]ngl.Fence, // Signaled.
    semaphores: [frame_n * 2]ngl.Semaphore,
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

        var non_unified: @TypeOf((try init()).non_unified) = blk: {
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
        var fences: [frame_n]ngl.Fence = undefined;
        for (&fences, 0..) |*fence, i|
            fence.* = ngl.Fence.init(gpa, dev, .{ .initial_status = .signaled }) catch |err| {
                for (0..i) |j| fences[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&fences) |*fence| fence.deinit(gpa, dev);
        var semas: [frame_n * 2]ngl.Semaphore = undefined;
        for (&semas, 0..) |*sema, i|
            sema.* = ngl.Semaphore.init(gpa, dev, .{}) catch |err| {
                for (0..i) |j| semas[j].deinit(gpa, dev);
                return err;
            };

        return .{
            .graphics = graph,
            .pools = pools,
            .buffers = bufs,
            .fences = fences,
            .semaphores = semas,
            .non_unified = non_unified,
        };
    }

    fn deinit(self: *Queue) void {
        const dev = &context().device;
        for (&self.pools) |*pool| pool.deinit(gpa, dev);
        for (&self.fences) |*fence| fence.deinit(gpa, dev);
        for (&self.semaphores) |*sema| sema.deinit(gpa, dev);
        if (self.non_unified) |*x| {
            for (&x.pools) |*pool| pool.deinit(gpa, dev);
            for (&x.semaphores) |*sema| sema.deinit(gpa, dev);
        }
    }
};

const Global = struct {
    vp: [16]f32,
    m: [16]f32,
    n: [9]f32,
    eye: [3]f32,

    comptime {
        if (@sizeOf(@This()) > 256) @compileError("???");
    }

    fn copy(
        self: Global,
        frame: usize,
        staging_buffer: *StagingBuffer,
        offset: u64,
    ) ngl.Cmd.BufferCopy.Region {
        std.debug.assert(offset & 255 == 0);
        const off = frame * 512;
        const data: [256 / 4]f32 =
            self.vp ++
            self.m ++
            self.n[0..3].* ++ [1]f32{undefined} ++
            self.n[3..6].* ++ [1]f32{undefined} ++
            self.n[6..9].* ++ [1]f32{undefined} ++
            self.eye ++
            [_]f32{undefined} ** 17;
        @memcpy(
            staging_buffer.data[offset + off .. offset + off + 256],
            @as([*]const u8, @ptrCast(&data))[0..256],
        );
        return .{
            .source_offset = offset + off,
            .dest_offset = off,
            .size = 256,
        };
    }
};

const Light = struct {
    lights: [1]Data,

    const Data = struct {
        position: [3]f32,
        color: [3]f32,
        intensity: f32,
    };

    comptime {
        if (@sizeOf(@This()) > 256) @compileError("???");
    }

    fn copy(
        self: Light,
        frame: usize,
        staging_buffer: *StagingBuffer,
        offset: u64,
    ) ngl.Cmd.BufferCopy.Region {
        std.debug.assert(offset & 255 == 0);
        // Interleaved with `Global`.
        const off = frame * 512 + 256;
        if (self.lights.len > 1) @compileError("TODO");
        const data: [256 / 4]f32 =
            self.lights[0].position ++ [1]f32{undefined} ++
            self.lights[0].color ++ [1]f32{self.lights[0].intensity} ++
            [_]f32{undefined} ** 56;
        @memcpy(
            staging_buffer.data[offset + off .. offset + off + 256],
            @as([*]const u8, @ptrCast(&data))[0..256],
        );
        return .{
            .source_offset = offset + off,
            .dest_offset = off,
            .size = 256,
        };
    }
};

const Material = struct {
    metallic: f32,
    roughness: f32,
    reflectance: f32,

    comptime {
        if (@sizeOf(@This()) > 256) @compileError("???");
    }

    fn copy(
        self: Material,
        frame: usize,
        index: usize,
        staging_buffer: *StagingBuffer,
        offset: u64,
    ) ngl.Cmd.BufferCopy.Region {
        std.debug.assert(offset & 255 == 0);
        // After all `Global`s and `Light`s.
        const off = frame_n * 512 + frame * 256 * materials.len + index * 256;
        const data: [256 / 4]f32 =
            [1]f32{self.metallic} ++
            [1]f32{self.roughness} ++
            [1]f32{self.reflectance} ++
            [_]f32{undefined} ** 61;
        @memcpy(
            staging_buffer.data[offset + off .. offset + off + 256],
            @as([*]const u8, @ptrCast(&data))[0..256],
        );
        return .{
            .source_offset = offset + off,
            .dest_offset = off,
            .size = 256,
        };
    }
};
