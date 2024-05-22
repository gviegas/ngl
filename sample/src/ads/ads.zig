const std = @import("std");
const assert = std.debug.assert;

const ngl = @import("ngl");
const pfm = ngl.pfm;

const Context = @import("ctx").Context;
const context = @import("ctx").context;
const cube = &@import("model").cube;
const util = @import("util");

pub fn main() !void {
    try do();
}

pub const ngl_options = ngl.Options{
    .app_name = "My App",
    .app_version = 1,
    .engine_name = "🐐",
    .engine_version = 2,
};

pub const platform_desc = pfm.Platform.Desc{
    .width = width,
    .height = height,
};

const frame_n = 2;
const width = 1024;
const height = 576;

var ctx: *Context = undefined;
var dev: *ngl.Device = undefined;
var plat: *pfm.Platform = undefined;

fn do() !void {
    ctx = context();
    dev = &ctx.device;
    plat = &ctx.platform;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var color = try Color.init(aa);
    defer color.deinit(aa);

    var depth = try Depth.init(aa);
    defer depth.deinit(aa);

    const idx_buf_size = @sizeOf(@TypeOf(cube.indices));
    var idx_buf = try Buffer(.device).init(aa, idx_buf_size, .{
        .index_buffer = true,
        .transfer_dest = true,
    });
    defer idx_buf.deinit(aa);

    const vert_buf_size = @sizeOf(@TypeOf(cube.data));
    var vert_buf = try Buffer(.device).init(aa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(aa);

    const globl_off = 0;
    const light_off = (globl_off + Global.size + 255) & ~@as(u64, 255);
    const matl_off = (light_off + Light.size + 255) & ~@as(u64, 255);
    const unif_strd = (matl_off + Material.size + 255) & ~@as(u64, 255);
    const unif_buf_size = frame_n * unif_strd;
    var unif_buf = try Buffer(.device).init(aa, unif_buf_size, .{
        .uniform_buffer = true,
        .transfer_dest = true,
    });
    defer unif_buf.deinit(aa);

    const idx_cpy_off = 0;
    const vert_cpy_off = (idx_cpy_off + idx_buf_size + 255) & ~@as(u64, 255);
    const unif_cpy_off = (vert_cpy_off + vert_buf_size + 255) & ~@as(u64, 255);
    const stg_buf_size = unif_cpy_off + unif_buf_size;
    var stg_buf = try Buffer(.host).init(aa, stg_buf_size, .{ .transfer_source = true });
    defer stg_buf.deinit(aa);

    var desc = try Descriptor.init(aa);
    defer desc.deinit(aa);

    var shd = try Shader.init(aa, &desc);
    defer shd.deinit(aa);

    var cq = try Command.init(aa);
    defer cq.deinit(aa);
    const one_queue = cq.multiqueue == null;

    const m = util.identity(4);
    const v = util.lookAt(.{ 0, 0, 0 }, .{ -4, -5, -6 }, .{ 0, -1, 0 });
    const p = util.perspective(std.math.pi / 4.0, @as(f32, width) / height, 0.01, 100);
    const mv = util.mulM(4, v, m);
    const mvp = util.mulM(4, p, mv);
    const inv = util.invert3(util.upperLeft(4, mv));
    const n = [12]f32{
        inv[0], inv[3], inv[6], undefined,
        inv[1], inv[4], inv[7], undefined,
        inv[2], inv[5], inv[8], undefined,
    };
    const globl = Global.init(mvp, mv, n);

    const light_pos = util.mulMV(4, v, .{ -4, -6, -4, 1 })[0..3].*;
    const intens = 1;
    const light = Light.init(light_pos, intens);

    const ka = .{ 1e-2, 1e-2, 1e-2 };
    const kd = .{ 1, 0, 0 };
    const ks = .{ 1, 1, 1 };
    const sp = 8;
    const matl = Material.init(ka, kd, ks, sp);

    @memcpy(
        stg_buf.data[idx_cpy_off .. idx_cpy_off + idx_buf_size],
        std.mem.asBytes(&cube.indices),
    );
    @memcpy(
        stg_buf.data[vert_cpy_off .. vert_cpy_off + vert_buf_size],
        std.mem.asBytes(&cube.data),
    );

    for (0..frame_n) |frame| {
        const ub = &unif_buf.buffer;
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd ..];

        try desc.write(Global, aa, frame, ub, strd + globl_off);
        try desc.write(Light, aa, frame, ub, strd + light_off);
        try desc.write(Material, aa, frame, ub, strd + matl_off);

        globl.copy(data[globl_off .. globl_off + Global.size]);
        light.copy(data[light_off .. light_off + Light.size]);
        matl.copy(data[matl_off .. matl_off + Material.size]);
    }

    plat.lock();
    defer plat.unlock();

    var frame: usize = 0;

    var cmd = try cq.buffers[frame].begin(aa, dev, .{
        .one_time_submit = true,
        .inheritance = null,
    });

    cmd.copyBuffer(&.{
        .{
            .source = &stg_buf.buffer,
            .dest = &idx_buf.buffer,
            .regions = &.{.{
                .source_offset = idx_cpy_off,
                .dest_offset = 0,
                .size = idx_buf_size,
            }},
        },
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

    try ngl.Fence.reset(aa, dev, &.{&cq.fences[frame]});

    {
        ctx.lockQueue(cq.queue_index);
        defer ctx.unlockQueue(cq.queue_index);

        try dev.queues[cq.queue_index].submit(aa, dev, &cq.fences[frame], &.{.{
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

        try ngl.Fence.wait(aa, dev, std.time.ns_per_s, &.{fnc});
        try ngl.Fence.reset(aa, dev, &.{fnc});
        const next = try plat.swapchain.nextImage(dev, std.time.ns_per_s, sems[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(aa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.vertex, &shd.fragment });
        cmd.setDescriptors(.graphics, &shd.layout, 0, &.{
            &desc.sets[0][frame],
            &desc.sets[1][frame],
        });

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
        cmd.setPrimitiveTopology(cube.topology);
        cmd.setIndexBuffer(cube.index_type, &idx_buf.buffer, 0, idx_buf_size);
        cmd.setVertexBuffers(
            0,
            &.{
                &vert_buf.buffer,
                &vert_buf.buffer,
            },
            &.{
                @offsetOf(@TypeOf(cube.data), "position"),
                @offsetOf(@TypeOf(cube.data), "normal"),
            },
            &.{
                @sizeOf(@TypeOf(cube.data.position)),
                @sizeOf(@TypeOf(cube.data.normal)),
            },
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

        cmd.setRasterizationEnable(true);
        cmd.setPolygonMode(.fill);
        cmd.setCullMode(.back);
        cmd.setFrontFace(cube.front_face);
        cmd.setSampleCount(Color.samples);
        cmd.setSampleMask(~@as(u64, 0));
        cmd.setDepthBiasEnable(false);

        cmd.setDepthTestEnable(true);
        cmd.setDepthCompareOp(.less);
        cmd.setDepthWriteEnable(true);
        cmd.setStencilTestEnable(false);

        cmd.setColorBlendEnable(0, &.{false});
        cmd.setColorWrite(0, &.{.all});

        cmd.barrier(&.{.{
            .image = &.{
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
            .stencil = null,
            .render_area = .{ .width = width, .height = height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.drawIndexed(cube.indices.len, 1, 0, 0, 0);

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

            try dev.queues[cq.queue_index].submit(aa, dev, fnc, &.{.{
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

            try ngl.Fence.wait(aa, dev, std.time.ns_per_s, &.{&mq.fences[frame]});
            try ngl.Fence.reset(aa, dev, &.{&mq.fences[frame]});

            try mq.pools[frame].reset(dev, .keep);
            cmd = try mq.buffers[frame].begin(aa, dev, .{
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

            try dev.queues[plat.queue_index].submit(aa, dev, &mq.fences[frame], &.{.{
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

        try pres.queue.present(aa, dev, &.{pres.sem}, &.{.{
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

    fn init(arena: std.mem.Allocator) ngl.Error!Color {
        var img = try ngl.Image.init(arena, dev, .{
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
        errdefer img.deinit(arena, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(arena, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{
                    .device_local = true,
                    .lazily_allocated = true,
                }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(arena, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(arena, &mem);

        const view = try ngl.ImageView.init(arena, dev, .{
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

    fn deinit(self: *Color, arena: std.mem.Allocator) void {
        self.view.deinit(arena, dev);
        self.image.deinit(arena, dev);
        dev.free(arena, &self.memory);
    }
};

const Depth = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    const format = ngl.Format.d16_unorm;
    const samples = Color.samples;

    fn init(arena: std.mem.Allocator) ngl.Error!Depth {
        var img = try ngl.Image.init(arena, dev, .{
            .type = .@"2d",
            .format = format,
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
        errdefer img.deinit(arena, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(arena, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{
                    .device_local = true,
                    .lazily_allocated = true,
                }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(arena, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(arena, &mem);

        const view = try ngl.ImageView.init(arena, dev, .{
            .image = &img,
            .type = .@"2d",
            .format = format,
            .range = .{
                .aspect_mask = .{ .depth = true },
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

    fn deinit(self: *Depth, arena: std.mem.Allocator) void {
        self.view.deinit(arena, dev);
        self.image.deinit(arena, dev);
        dev.free(arena, &self.memory);
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

        fn init(arena: std.mem.Allocator, size: u64, usage: ngl.Buffer.Usage) ngl.Error!@This() {
            var buf = try ngl.Buffer.init(arena, dev, .{
                .size = size,
                .usage = usage,
            });
            errdefer buf.deinit(arena, dev);

            const reqs = buf.getMemoryRequirements(dev);
            const props: ngl.Memory.Properties = switch (kind) {
                .host => .{
                    .host_visible = true,
                    .host_coherent = true,
                },
                .device => .{ .device_local = true },
            };
            var mem = try dev.alloc(arena, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, props, null).?,
            });
            errdefer dev.free(arena, &mem);

            try buf.bind(dev, &mem, 0);
            const data = if (kind == .host) try mem.map(dev, 0, size) else {};

            return .{
                .buffer = buf,
                .memory = mem,
                .data = data,
            };
        }

        fn deinit(self: *@This(), arena: std.mem.Allocator) void {
            self.buffer.deinit(arena, dev);
            dev.free(arena, &self.memory);
        }
    };
}

const Descriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pool: ngl.DescriptorPool,
    sets: [2][frame_n]ngl.DescriptorSet,

    fn init(arena: std.mem.Allocator) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(arena, dev, .{
            .bindings = &.{
                .{
                    .binding = 0,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .vertex = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = 1,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt.deinit(arena, dev);

        var set_layt_2 = try ngl.DescriptorSetLayout.init(arena, dev, .{
            .bindings = &.{.{
                .binding = 0,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .fragment = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_2.deinit(arena, dev);

        var pool = try ngl.DescriptorPool.init(arena, dev, .{
            .max_sets = 2 * frame_n,
            .pool_size = .{ .uniform_buffer = 3 * frame_n },
        });
        errdefer pool.deinit(arena, dev);

        const sets = try pool.alloc(arena, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** frame_n,
        });
        defer arena.free(sets);

        return .{
            .set_layouts = .{ set_layt, set_layt_2 },
            .pool = pool,
            .sets = .{
                sets[0..frame_n].*,
                sets[frame_n .. 2 * frame_n].*,
            },
        };
    }

    fn write(
        self: *Descriptor,
        comptime T: type,
        arena: std.mem.Allocator,
        frame: usize,
        buffer: *ngl.Buffer,
        offset: u64,
    ) ngl.Error!void {
        try ngl.DescriptorSet.write(arena, dev, &.{.{
            .descriptor_set = &self.sets[T.set_index][frame],
            .binding = T.binding,
            .element = 0,
            .contents = .{ .uniform_buffer = &.{.{
                .buffer = buffer,
                .offset = offset,
                .range = T.size,
            }} },
        }});
    }

    fn deinit(self: *Descriptor, arena: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(arena, dev);
        self.pool.deinit(arena, dev);
    }
};

const Shader = struct {
    vertex: ngl.Shader,
    fragment: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(arena: std.mem.Allocator, descriptor: *Descriptor) ngl.Error!Shader {
        const dapi = ctx.gpu.getDriverApi();

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
        };

        const shaders = try ngl.Shader.init(arena, dev, &.{
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
                .specialization = null,
                .link = true,
            },
        });
        defer arena.free(shaders);
        errdefer for (shaders) |*shd|
            (shd.* catch continue).deinit(arena, dev);

        var layt = try ngl.ShaderLayout.init(arena, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(arena, dev);

        return .{
            .vertex = try shaders[0],
            .fragment = try shaders[1],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, arena: std.mem.Allocator) void {
        self.vertex.deinit(arena, dev);
        self.fragment.deinit(arena, dev);
        self.layout.deinit(arena, dev);
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

    fn init(arena: std.mem.Allocator) ngl.Error!Command {
        const pres = plat.queue_index;
        const rend = if (dev.queues[pres].capabilities.graphics)
            pres
        else
            dev.findQueue(.{ .graphics = true }, null) orelse return ngl.Error.NotSupported;

        var mq: @TypeOf((try init(arena)).multiqueue) = blk: {
            if (pres == rend)
                break :blk null;

            var pools: [frame_n]ngl.CommandPool = undefined;
            for (&pools, 0..) |*pool, i|
                pool.* = ngl.CommandPool.init(arena, dev, .{
                    .queue = &dev.queues[pres],
                }) catch |err| {
                    for (0..i) |j|
                        pools[j].deinit(arena, dev);
                    return err;
                };
            errdefer for (&pools) |*pool|
                pool.deinit(arena, dev);

            var bufs: [frame_n]ngl.CommandBuffer = undefined;
            for (&bufs, &pools) |*buf, *pool| {
                const s = try pool.alloc(arena, dev, .{
                    .level = .primary,
                    .count = 1,
                });
                buf.* = s[0];
                arena.free(s);
            }

            var sems: [frame_n]ngl.Semaphore = undefined;
            for (&sems, 0..) |*sem, i|
                sem.* = ngl.Semaphore.init(arena, dev, .{}) catch |err| {
                    for (0..i) |j|
                        sems[j].deinit(arena, dev);
                    return err;
                };
            errdefer for (&sems) |*sem|
                sem.deinit(arena, dev);

            var fncs: [frame_n]ngl.Fence = undefined;
            for (&fncs, 0..) |*fnc, i|
                fnc.* = ngl.Fence.init(arena, dev, .{ .status = .signaled }) catch |err| {
                    for (0..i) |j|
                        fncs[j].deinit(arena, dev);
                    return err;
                };

            break :blk .{
                .pools = pools,
                .buffers = bufs,
                .semaphores = sems,
                .fences = fncs,
            };
        };
        errdefer if (mq) |*x| {
            for (&x.pools) |*pool|
                pool.deinit(arena, dev);
            for (&x.semaphores) |*sem|
                sem.deinit(arena, dev);
            for (&x.fences) |*fnc|
                fnc.deinit(arena, dev);
        };

        var pools: [frame_n]ngl.CommandPool = undefined;
        for (&pools, 0..) |*pool, i|
            pool.* = ngl.CommandPool.init(arena, dev, .{ .queue = &dev.queues[rend] }) catch |err| {
                for (0..i) |j|
                    pools[j].deinit(arena, dev);
                return err;
            };
        errdefer for (&pools) |*pool|
            pool.deinit(arena, dev);

        var bufs: [frame_n]ngl.CommandBuffer = undefined;
        for (&bufs, &pools) |*buf, *pool| {
            const s = try pool.alloc(arena, dev, .{
                .level = .primary,
                .count = 1,
            });
            buf.* = s[0];
            arena.free(s);
        }

        var sems: [2 * frame_n]ngl.Semaphore = undefined;
        for (&sems, 0..) |*sem, i|
            sem.* = ngl.Semaphore.init(arena, dev, .{}) catch |err| {
                for (0..i) |j|
                    sems[j].deinit(arena, dev);
                return err;
            };
        errdefer for (&sems) |*sem|
            sem.deinit(arena, dev);

        var fncs: [frame_n]ngl.Fence = undefined;
        for (&fncs, 0..) |*fnc, i|
            fnc.* = ngl.Fence.init(arena, dev, .{ .status = .signaled }) catch |err| {
                for (0..i) |j|
                    fncs[j].deinit(arena, dev);
                return err;
            };

        return .{
            .queue_index = rend,
            .pools = pools,
            .buffers = bufs,
            .semaphores = sems,
            .fences = fncs,
            .multiqueue = mq,
        };
    }

    fn deinit(self: *Command, arena: std.mem.Allocator) void {
        for (&self.pools) |*pool|
            pool.deinit(arena, dev);
        for (&self.semaphores) |*sem|
            sem.deinit(arena, dev);
        for (&self.fences) |*fnc|
            fnc.deinit(arena, dev);
        if (self.multiqueue) |*x| {
            for (&x.pools) |*pool|
                pool.deinit(arena, dev);
            for (&x.semaphores) |*sem|
                sem.deinit(arena, dev);
            for (&x.fences) |*fnc|
                fnc.deinit(arena, dev);
        }
    }
};

const Global = struct {
    mvp_mv_n: [16 + 16 + 12]f32,

    const size = @sizeOf(@typeInfo(Global).Struct.fields[0].type);
    const set_index = 0;
    const binding = 0;

    fn init(mvp: [16]f32, mv: [16]f32, n: [12]f32) Global {
        var self: Global = undefined;
        self.set(mvp, mv, n);
        return self;
    }

    fn set(self: *Global, mvp: [16]f32, mv: [16]f32, n: [12]f32) void {
        @memcpy(self.mvp_mv_n[0..16], &mvp);
        @memcpy(self.mvp_mv_n[16..32], &mv);
        @memcpy(self.mvp_mv_n[32..], &n);
    }

    fn copy(self: Global, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.mvp_mv_n));
    }
};

const Light = packed struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    intensity: f32,

    const size = @sizeOf(Light);
    const set_index = 0;
    const binding = 1;

    fn init(position: [3]f32, intensity: f32) Light {
        var self: Light = undefined;
        self.set(position, intensity);
        return self;
    }

    fn set(self: *Light, position: [3]f32, intensity: f32) void {
        self.pos_x = position[0];
        self.pos_y = position[1];
        self.pos_z = position[2];
        self.intensity = intensity;
    }

    fn copy(self: Light, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Material = packed struct {
    ka_r: f32,
    ka_g: f32,
    ka_b: f32,
    _ka_pad: f32,
    kd_r: f32,
    kd_g: f32,
    kd_b: f32,
    _kd_pad: f32,
    ks_r: f32,
    ks_g: f32,
    ks_b: f32,
    sp: f32,

    const size = @sizeOf(Material);
    const set_index = 1;
    const binding = 0;

    fn init(ka: [3]f32, kd: [3]f32, ks: [3]f32, sp: f32) Material {
        var self: Material = undefined;
        self.set(ka, kd, ks, sp);
        return self;
    }

    fn set(self: *Material, ka: [3]f32, kd: [3]f32, ks: [3]f32, sp: f32) void {
        self.ka_r = ka[0];
        self.ka_g = ka[1];
        self.ka_b = ka[2];
        self.kd_r = kd[0];
        self.kd_g = kd[1];
        self.kd_b = kd[2];
        self.ks_r = ks[0];
        self.ks_g = ks[1];
        self.ks_b = ks[2];
        self.sp = sp;
    }

    fn copy(self: Material, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};
