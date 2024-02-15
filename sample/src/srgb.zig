const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const idata = @import("idata.zig");
const util = @import("util.zig");

pub fn main() !void {
    try do();
}

const frame_n = 2;
const image_path = "data/image/feral.png";

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();

    const Dest = struct {
        staging_buffer: ?StagingBuffer = null,
        image_size: u64 = 0,

        pub fn get(self: *@This(), size: u64) ![]u8 {
            if (self.staging_buffer != null)
                @panic("Dest.get called twice");
            self.staging_buffer = try StagingBuffer.init(size +
                (size + 255 & ~@as(u64, 255)) + @sizeOf(@TypeOf(VertexBuffer.vertices)));
            self.image_size = size;
            return self.staging_buffer.?.data;
        }
    };
    var dest = Dest{};
    defer if (dest.staging_buffer) |*x| x.deinit();

    const img_data = try idata.loadPng(gpa, image_path, &dest);
    if (img_data.format != .rgba8_srgb)
        @panic("Unexpected image format from decoder");
    if (img_data.width * img_data.height * 4 != dest.image_size)
        @panic("Unexpected image size from decoder");

    const scale: [2]f32 = blk: {
        const iw: f32 = @floatFromInt(img_data.width);
        const ih: f32 = @floatFromInt(img_data.height);
        const aw: f32 = @floatFromInt(Platform.width);
        const ah: f32 = @floatFromInt(Platform.height);

        const sx = iw / aw;
        const sy = ih / ah;

        break :blk util.norm(2, .{ sx, sy });
    };

    var tex = try Texture.init(img_data.width, img_data.height);
    defer tex.deinit();

    var desc = try Descriptor.init(&tex);
    defer desc.deinit();

    var pass = try Pass.init();
    defer pass.deinit();

    var pl = try Pipeline.init(&desc, &pass);
    defer pl.deinit();

    var vert_buf = try VertexBuffer.init();
    defer vert_buf.deinit();

    var stg_buf = dest.staging_buffer orelse unreachable;
    const tex_copy_off = 0;
    const tex_copy_size = dest.image_size;
    const vert_copy_off = (tex_copy_size + 255) & ~@as(u64, 255);
    const vert_copy_size = @sizeOf(@TypeOf(VertexBuffer.vertices));
    @memcpy(
        stg_buf.data[vert_copy_off .. vert_copy_off + vert_copy_size],
        @as([*]const u8, @ptrCast(&VertexBuffer.vertices))[0..vert_copy_size],
    );

    var queue = try Queue.init();
    defer queue.deinit();

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
                .levels = 1,
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
        .regions = &.{.{
            .buffer_offset = tex_copy_off,
            .buffer_row_length = img_data.width,
            .buffer_image_height = img_data.height,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = img_data.width,
            .image_height = img_data.height,
            .image_depth_or_layers = 1,
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
            .image = &tex.image,
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
    cmd.copyBuffer(&.{.{
        .source = &stg_buf.buffer,
        .dest = &vert_buf.buffer,
        .regions = &.{.{
            .source_offset = vert_copy_off,
            .dest_offset = 0,
            .size = vert_copy_size,
        }},
    }});
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
    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 3, &.{&queue.fences[0]});

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;
    var pl_idx: usize = 0;
    var timer = try std.time.Timer.start();
    var timer_2 = try std.time.Timer.start();
    const is_unified = queue.non_unified == null;

    const log = struct {
        fn f(pipeline_index: u1) void {
            std.log.info("{s}", .{if (pipeline_index == 0) "sRGB EOTF" else "gamma 2.2"});
        }
    }.f;
    log(@intCast(pl_idx));

    while (timer.read() < std.time.ns_per_min) {
        const input = plat.poll();
        if (input.done) break;
        if (timer_2.read() > std.time.ns_per_s * 2) {
            timer_2.reset();
            pl_idx = (pl_idx + 1) % pl.pipelines.len;
            log(@intCast(pl_idx));
        }

        const cmd_pool = &queue.pools[frame];
        const cmd_buf = &queue.buffers[frame];
        const semas = .{ &queue.semaphores[frame * 2], &queue.semaphores[frame * 2 + 1] };
        const fence = &queue.fences[frame];

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{fence});
        try ngl.Fence.reset(gpa, dev, &.{fence});

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
                    .width = Platform.width,
                    .height = Platform.height,
                },
                .clear_values = &.{.{ .color_f32 = .{ 0.6, 0.6, 0, 1 } }},
            },
            .{ .contents = .inline_only },
        );
        cmd.setPipeline(&pl.pipelines[pl_idx]);
        cmd.setDescriptors(.graphics, &desc.pipeline_layout, 0, &.{&desc.sets[frame]});
        cmd.setPushConstants(
            &desc.pipeline_layout,
            .{ .vertex = true },
            0,
            @as([*]align(4) const u8, @ptrCast(&scale))[0..@sizeOf(@TypeOf(scale))],
        );
        cmd.setVertexBuffers(
            0,
            &.{&vert_buf.buffer},
            &.{0},
            &.{@sizeOf(@TypeOf(VertexBuffer.vertices))},
        );
        cmd.draw(VertexBuffer.vertices.len, 1, 0, 0);
        cmd.endRenderPass(.{});
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

const Texture = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    // We'll apply the sRGB conversion ourselves
    const format = ngl.Format.rgba8_unorm;

    fn init(width: u32, height: u32) ngl.Error!Texture {
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
                .base_level = 0,
                .levels = 1,
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

const Descriptor = struct {
    set_layout: ngl.DescriptorSetLayout,
    pipeline_layout: ngl.PipelineLayout,
    pool: ngl.DescriptorPool,
    sets: [frame_n]ngl.DescriptorSet,

    fn init(texture: *Texture) ngl.Error!Descriptor {
        const dev = &context().device;

        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = &.{&texture.sampler},
        }} });
        errdefer set_layt.deinit(gpa, dev);
        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{&set_layt},
            .push_constant_ranges = &.{.{
                .offset = 0,
                .size = 8,
                .stage_mask = .{ .vertex = true },
            }},
        });
        errdefer pl_layt.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = frame_n,
            .pool_size = .{ .combined_image_sampler = frame_n },
        });
        errdefer pool.deinit(gpa, dev);
        var sets = blk: {
            var s = try pool.alloc(
                gpa,
                dev,
                .{ .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n },
            );
            defer gpa.free(s);
            break :blk s[0..frame_n].*;
        };
        var writes: [sets.len]ngl.DescriptorSet.Write = undefined;
        const is = [1]ngl.DescriptorSet.Write.ImageSamplerWrite{.{
            .view = &texture.view,
            .layout = .shader_read_only_optimal,
            .sampler = null,
        }};
        for (&writes, &sets) |*write, *set|
            write.* = .{
                .descriptor_set = set,
                .binding = 0,
                .element = 0,
                .contents = .{ .combined_image_sampler = &is },
            };
        try ngl.DescriptorSet.write(gpa, dev, &writes);

        return .{
            .set_layout = set_layt,
            .pipeline_layout = pl_layt,
            .pool = pool,
            .sets = sets,
        };
    }

    fn deinit(self: *Descriptor) void {
        const dev = &context().device;
        self.set_layout.deinit(gpa, dev);
        self.pipeline_layout.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Pass = struct {
    render_pass: ngl.RenderPass,
    frame_buffers: []ngl.FrameBuffer,

    fn init() ngl.Error!Pass {
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
        for (fbs, plat.image_views, 0..) |*fb, *sc_view, i| {
            fb.* = ngl.FrameBuffer.init(gpa, dev, .{
                .render_pass = &rp,
                .attachments = &.{sc_view},
                .width = Platform.width,
                .height = Platform.height,
                .layers = 1,
            }) catch |err| {
                for (0..i) |j| fbs[j].deinit(gpa, dev);
                gpa.free(fbs);
                return err;
            };
        }

        return .{ .render_pass = rp, .frame_buffers = fbs };
    }

    fn deinit(self: *Pass) void {
        const dev = &context().device;
        for (self.frame_buffers) |*fb| fb.deinit(gpa, dev);
        self.render_pass.deinit(gpa, dev);
    }
};

const Pipeline = struct {
    pipelines: [2]ngl.Pipeline,

    const vert_spv align(4) = @embedFile("shader/srgb/vert.spv").*;
    const frag_spv align(4) = @embedFile("shader/srgb/frag.spv").*;

    fn init(descriptor: *Descriptor, pass: *Pass) ngl.Error!Pipeline {
        const dev = &context().device;
        const plat = platform() catch unreachable;

        const conv_in: u32 = 1;
        const conv_out: u32 = @intFromBool(!plat.format.format.isSrgb());

        const vert_shd = ngl.ShaderStage.Desc{
            .stage = .vertex,
            .code = &vert_spv,
            .name = "main",
        };
        const frag_spec_consts = &.{
            // `convert_input`
            .{
                .id = 0,
                .offset = 0,
                .size = 4,
            },
            // `convert_output`
            .{
                .id = 1,
                .offset = 4,
                .size = 4,
            },
            // `accurate`
            .{
                .id = 2,
                .offset = 8,
                .size = 4,
            },
        };
        const frag_spec_data = [2 * 3]u32{
            conv_in,
            conv_out,
            1,
            conv_in,
            conv_out,
            0,
        };
        const frag_shds = [2]ngl.ShaderStage.Desc{
            .{
                .stage = .fragment,
                .code = &frag_spv,
                .name = "main",
                .specialization = .{
                    .constants = frag_spec_consts,
                    .data = @as([*]const u8, @ptrCast(&frag_spec_data))[0..12],
                },
            },
            .{
                .stage = .fragment,
                .code = &frag_spv,
                .name = "main",
                .specialization = .{
                    .constants = frag_spec_consts,
                    .data = @as([*]const u8, @ptrCast(&frag_spec_data))[12..24],
                },
            },
        };

        const prim = ngl.Primitive{
            .bindings = &.{.{
                .binding = 0,
                .stride = @sizeOf(VertexBuffer.Vertex),
                .step_rate = .vertex,
            }},
            .attributes = &.{
                .{
                    .location = 0,
                    .binding = 0,
                    .format = .rgb32_sfloat,
                    .offset = @offsetOf(VertexBuffer.Vertex, "x"),
                },
                .{
                    .location = 1,
                    .binding = 0,
                    .format = .rg32_sfloat,
                    .offset = @offsetOf(VertexBuffer.Vertex, "u"),
                },
            },
            .topology = VertexBuffer.topology,
        };

        const vport = ngl.Viewport{
            .x = 0,
            .y = 0,
            .width = Platform.width,
            .height = Platform.height,
            .near = 0,
            .far = 1,
        };

        const raster = ngl.Rasterization{
            .polygon_mode = .fill,
            .cull_mode = .back,
            .clockwise = VertexBuffer.clockwise,
            .samples = .@"1",
        };

        const blend = ngl.ColorBlend{
            .attachments = &.{.{ .blend = null, .write = .all }},
            .constants = .unused,
        };

        const pls = try ngl.Pipeline.initGraphics(gpa, dev, .{
            .states = &.{
                .{
                    .stages = &.{ vert_shd, frag_shds[0] },
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &prim,
                    .viewport = &vport,
                    .rasterization = &raster,
                    .depth_stencil = null,
                    .color_blend = &blend,
                    .render_pass = &pass.render_pass,
                    .subpass = 0,
                },
                .{
                    .stages = &.{ vert_shd, frag_shds[1] },
                    .layout = &descriptor.pipeline_layout,
                    .primitive = &prim,
                    .viewport = &vport,
                    .rasterization = &raster,
                    .depth_stencil = null,
                    .color_blend = &blend,
                    .render_pass = &pass.render_pass,
                    .subpass = 0,
                },
            },
            .cache = null,
        });
        defer gpa.free(pls);

        return .{ .pipelines = pls[0..2].* };
    }

    fn deinit(self: *Pipeline) void {
        const dev = &context().device;
        for (&self.pipelines) |*pl| pl.deinit(gpa, dev);
    }
};

const VertexBuffer = struct {
    buffer: ngl.Buffer,
    memory: ngl.Memory,

    const Vertex = packed struct {
        x: f32,
        y: f32,
        z: f32,
        u: f32,
        v: f32,
    };

    const vertices = [4]Vertex{
        .{
            .x = -1,
            .y = 1,
            .z = 0.5,
            .u = 0,
            .v = 1,
        },
        .{
            .x = -1,
            .y = -1,
            .z = 0.5,
            .u = 0,
            .v = 0,
        },
        .{
            .x = 1,
            .y = 1,
            .z = 0.5,
            .u = 1,
            .v = 1,
        },
        .{
            .x = 1,
            .y = -1,
            .z = 0.5,
            .u = 1,
            .v = 0,
        },
    };

    const topology = ngl.Primitive.Topology.triangle_strip;
    const clockwise = true;

    fn init() ngl.Error!VertexBuffer {
        const dev = &context().device;

        var buf = try ngl.Buffer.init(gpa, dev, .{
            .size = @sizeOf(@TypeOf(vertices)),
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

        var non_unified: @TypeOf((try init()).non_unified) = blk: {
            if (pres == graph)
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
        errdefer for (&semas) |*sema| sema.deinit(gpa, dev);
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
