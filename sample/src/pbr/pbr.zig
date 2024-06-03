const std = @import("std");
const assert = std.debug.assert;

const ngl = @import("ngl");
const pfm = ngl.pfm;

const Ctx = @import("Ctx");
const mdata = @import("mdata");
const gmath = @import("gmath");

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
const light_n: i32 = 3;
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

    var depth = try Depth.init(gpa);
    defer depth.deinit(gpa);

    var sphr = try mdata.loadObj(gpa, "data/model/sphere.obj");
    defer sphr.deinit(gpa);
    assert(sphr.indices == null);

    const vert_buf_size = sphr.sizeOfPositions() + sphr.sizeOfNormals();
    var vert_buf = try Buffer(.device).init(gpa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(gpa);

    const m = gmath.identity(4);
    const n = blk: {
        const n = gmath.invert3(gmath.upperLeft(4, m));
        break :blk [12]f32{
            n[0], n[3], n[6], undefined,
            n[1], n[4], n[7], undefined,
            n[2], n[5], n[8], undefined,
        };
    };
    const eye = [3]f32{ 0, -3, 6 };
    const v = gmath.lookAt(eye, .{ 0, 0, 0 }, .{ 0, -1, 0 });
    const p = gmath.perspective(std.math.pi / 4.0, @as(f32, width) / height, 0.01, 100);
    const vp = gmath.mulM(4, p, v);
    const globl = Global.init(vp, m, n, eye);

    const light_desc = Light(light_n).Desc{
        .{
            .position = .{ 13, -20, 10 },
            .color = .{ 1, 1, 1 },
            .intensity = 100,
        },
        .{
            .position = .{ -7, 0, 8 },
            .color = .{ 1, 1, 1 },
            .intensity = 100,
        },
        .{
            .position = .{ -4, -15, -2 },
            .color = .{ 1, 1, 1 },
            .intensity = 100,
        },
    };
    const light = Light(light_n).init(light_desc);

    const matl_col = [4]f32{ 0.94, 0.02, 0.83, 1 };
    const metal = 0;
    const smooth = 0.9;
    const reflec = 0.5;
    const matl = Material.init(matl_col, metal, smooth, reflec);

    const globl_off = 0;
    const light_off = (globl_off + Global.size + 255) & ~@as(u64, 255);
    const matl_off = (light_off + @TypeOf(light).size + 255) & ~@as(u64, 255);
    const unif_strd = (matl_off + Material.size + 255) & ~@as(u64, 255);
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

    var desc = try Descriptor.init(gpa);
    defer desc.deinit(gpa);

    var shd = try Shader.init(gpa, &desc);
    defer shd.deinit(gpa);

    var cq = try Command.init(gpa);
    defer cq.deinit(gpa);
    const one_queue = cq.multiqueue == null;

    @memcpy(
        stg_buf.data[vert_cpy_off .. vert_cpy_off + sphr.sizeOfPositions()],
        std.mem.sliceAsBytes(sphr.positions.items),
    );
    @memcpy(
        stg_buf.data[vert_cpy_off + sphr.sizeOfPositions() .. vert_cpy_off + vert_buf_size],
        std.mem.sliceAsBytes(sphr.normals.items),
    );

    for (0..frame_n) |frame| {
        const ub = &unif_buf.buffer;
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd .. unif_cpy_off + strd + unif_strd];

        try desc.write(Global, gpa, frame, ub, strd + globl_off);
        try desc.write(@TypeOf(light), gpa, frame, ub, strd + light_off);
        try desc.write(Material, gpa, frame, ub, strd + matl_off);

        globl.copy(data[globl_off .. globl_off + Global.size]);
        light.copy(data[light_off .. light_off + @TypeOf(light).size]);
        matl.copy(data[matl_off .. matl_off + Material.size]);
    }

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

    try ngl.Fence.reset(gpa, dev, &.{&cq.fences[frame]});

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
        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setVertexBuffers(
            0,
            &.{
                &vert_buf.buffer,
                &vert_buf.buffer,
            },
            &.{
                0,
                sphr.sizeOfPositions(),
            },
            &.{
                sphr.sizeOfPositions(),
                sphr.sizeOfNormals(),
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
        cmd.setFrontFace(.counter_clockwise);
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

        cmd.draw(sphr.vertexCount(), 1, 0, 0);

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

const Depth = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    const format = ngl.Format.d16_unorm;
    const samples = Color.samples;

    fn init(gpa: std.mem.Allocator) ngl.Error!Depth {
        var img = try ngl.Image.init(gpa, dev, .{
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

    fn deinit(self: *Depth, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
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
    sets: [2][frame_n]ngl.DescriptorSet,

    fn init(gpa: std.mem.Allocator) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = Global.binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .vertex = true, .fragment = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = Light(light_n).binding,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);

        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{.{
                .binding = Material.binding,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .fragment = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = 2 * frame_n,
            .pool_size = .{ .uniform_buffer = 3 * frame_n },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = try pool.alloc(gpa, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** frame_n,
        });
        defer gpa.free(sets);

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
        gpa: std.mem.Allocator,
        frame: usize,
        buffer: *ngl.Buffer,
        offset: u64,
    ) ngl.Error!void {
        try ngl.DescriptorSet.write(gpa, dev, &.{.{
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

    fn deinit(self: *Descriptor, gpa: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Shader = struct {
    vertex: ngl.Shader,
    fragment: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(gpa: std.mem.Allocator, descriptor: *Descriptor) ngl.Error!Shader {
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

        const shaders = try ngl.Shader.init(gpa, dev, &.{
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
                .specialization = .{
                    .constants = &.{.{
                        .id = 0,
                        .offset = 0,
                        .size = 4,
                    }},
                    .data = std.mem.asBytes(&light_n),
                },
                .link = true,
            },
        });
        defer gpa.free(shaders);
        errdefer for (shaders) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        var layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(gpa, dev);

        return .{
            .vertex = try shaders[0],
            .fragment = try shaders[1],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, gpa: std.mem.Allocator) void {
        self.vertex.deinit(gpa, dev);
        self.fragment.deinit(gpa, dev);
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
        const rend = if (dev.queues[pres].capabilities.graphics)
            pres
        else
            dev.findQueue(.{ .graphics = true }, null) orelse return ngl.Error.NotSupported;

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

const Global = struct {
    vp_m_n_eye: [16 + 16 + 12 + 3]f32,

    const size = @sizeOf(@typeInfo(Global).Struct.fields[0].type);
    const set_index = 0;
    const binding = 0;

    fn init(vp: [16]f32, m: [16]f32, n: [12]f32, eye: [3]f32) Global {
        var self: Global = undefined;
        self.set(vp, m, n, eye);
        return self;
    }

    fn set(self: *Global, vp: [16]f32, m: [16]f32, n: [12]f32, eye: [3]f32) void {
        @memcpy(self.vp_m_n_eye[0..16], &vp);
        @memcpy(self.vp_m_n_eye[16..32], &m);
        @memcpy(self.vp_m_n_eye[32..44], &n);
        @memcpy(self.vp_m_n_eye[44..47], &eye);
    }

    fn copy(self: Global, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.vp_m_n_eye));
    }
};

fn Light(comptime n: u16) type {
    return struct {
        lights: [n]Element,

        const size = n * @sizeOf(Element);
        const set_index = 0;
        const binding = 1;

        const Element = packed struct {
            pos_x: f32,
            pos_y: f32,
            pos_z: f32,
            _pos_pad: f32 = 0,
            col_r: f32,
            col_g: f32,
            col_b: f32,
            intensity: f32,
        };

        const Desc = [n]struct {
            position: [3]f32,
            color: [3]f32,
            intensity: f32,
        };

        comptime {
            assert(@sizeOf(@typeInfo(@This()).Struct.fields[0].type) == size);
        }

        fn init(desc: Desc) @This() {
            var self: @This() = undefined;
            self.set(desc);
            return self;
        }

        fn set(self: *@This(), desc: Desc) void {
            for (&self.lights, desc) |*l, d|
                l.* = .{
                    .pos_x = d.position[0],
                    .pos_y = d.position[1],
                    .pos_z = d.position[2],
                    .col_r = d.color[0],
                    .col_g = d.color[1],
                    .col_b = d.color[2],
                    .intensity = d.intensity,
                };
        }

        fn copy(self: @This(), dest: []u8) void {
            assert(@intFromPtr(dest.ptr) & 3 == 0);
            assert(dest.len >= size);

            @memcpy(dest[0..size], std.mem.asBytes(&self.lights));
        }
    };
}

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
    const binding = 0;

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
