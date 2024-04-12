const std = @import("std");

const ngl = @import("ngl");

const gpa = std.heap.c_allocator;
const context = @import("ctx.zig").context;
const Platform = @import("plat.zig").Platform;
const platform = @import("plat.zig").platform;
const cube = &@import("model.zig").cube;
const util = @import("util.zig");

pub fn main() !void {
    try do();
}

pub const ngl_options = struct {
    pub const app_name = "My App";
    pub const app_version = 1;
    pub const engine_name = "🐐";
    pub const engine_version = 2;
};

fn do() !void {
    const ctx = context();
    const dev = &ctx.device;
    const plat = try platform();
    plat.lock();
    defer plat.unlock();

    var d = try Data.init(dev, plat.queue_index, plat.format.format, plat.image_views);
    defer d.deinit(dev);

    // Update descriptor sets ------------------------------

    const Transform = [16 + 16 + 12]f32;
    const Light = [4 + 3]f32;
    const Material = [4 + 4 + 4 + 1]f32;

    const xform_off = 0;
    const light_off = 256;
    const matl_off = 512;
    const unif_off = 768;

    const writes = blk: {
        var writes: [Data.frame_n * 4]ngl.DescriptorSet.Write = undefined;
        for (0..Data.frame_n) |i| {
            writes[i * 4] = .{
                .descriptor_set = &d.descriptor.sets[i * 2],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = &.{.{
                    .buffer = &d.uniform.buffer,
                    .offset = unif_off * i + xform_off,
                    .range = @sizeOf(Transform),
                }} },
            };
            writes[i * 4 + 1] = .{
                .descriptor_set = &d.descriptor.sets[i * 2],
                .binding = 1,
                .element = 0,
                .contents = .{ .uniform_buffer = &.{.{
                    .buffer = &d.uniform.buffer,
                    .offset = unif_off * i + light_off,
                    .range = @sizeOf(Light),
                }} },
            };
            writes[i * 4 + 2] = .{
                .descriptor_set = &d.descriptor.sets[i * 2 + 1],
                .binding = 0,
                .element = 0,
                .contents = .{ .uniform_buffer = &.{.{
                    .buffer = &d.uniform.buffer,
                    .offset = unif_off * i + matl_off,
                    .range = @sizeOf(Material),
                }} },
            };
            writes[i * 4 + 3] = .{
                .descriptor_set = &d.descriptor.sets[i * 2 + 1],
                .binding = 1,
                .element = 0,
                .contents = .{ .combined_image_sampler = &.{.{
                    .view = &d.texture.view,
                    .layout = .shader_read_only_optimal,
                    .sampler = &d.texture.sampler,
                }} },
            };
        }
        break :blk writes;
    };
    try ngl.DescriptorSet.write(gpa, dev, &writes);

    // Upload data upfront ---------------------------------

    const upl_p = try d.upload.memory.map(dev, 0, null);

    const pixel: [4]u8 = .{ 255, 255, 255, 255 };
    const v = util.lookAt(.{ 0, 0, 0 }, .{ 4, -4, 6 }, .{ 0, -1, 0 });
    const transform = blk: {
        const m = util.identity(4);
        const p = util.perspective(
            std.math.pi / 4.0,
            @as(f32, @floatFromInt(Data.width)) / Data.height,
            0.01,
            100,
        );
        const mv = util.mulM(4, v, m);
        const mvp = util.mulM(4, p, mv);
        const n = util.invert3(util.upperLeft(4, mv));
        var xform: Transform = undefined;
        @memcpy(xform[0..16], &mvp);
        @memcpy(xform[16..32], &mv);
        @memcpy(xform[32..], &[12]f32{
            n[0], n[3], n[6], undefined,
            n[1], n[4], n[7], undefined,
            n[2], n[5], n[8], undefined,
        });
        break :blk xform;
    };
    const light: Light =
        util.mulMV(4, v, .{ 2, -3, 4, 1 }) // Position.
    ++ [3]f32{ 0.25, 0.25, 0.25 }; // Intensity.
    const material = Material{
        0, 0, 0.2, undefined, // Ka.
        0.9, 0, 0, undefined, // Kd.
        0, 0.1, 0, undefined, // Ks.
        200, // Specular power.
    };

    const pixel_cpy_off = 0;
    const idx_cpy_off = 256;
    const vert_cpy_off = (idx_cpy_off + @sizeOf(@TypeOf(cube.indices)) + 255) & ~@as(u64, 255);
    const xform_cpy_off = (vert_cpy_off + @sizeOf(@TypeOf(cube.data)) + 255) & ~@as(u64, 255);
    const light_cpy_off = (xform_cpy_off + @sizeOf(Transform) + 255) & ~@as(u64, 255);
    const matl_cpy_off = (light_cpy_off + @sizeOf(Light) + 255) & ~@as(u64, 255);

    @memcpy(
        upl_p + pixel_cpy_off,
        &pixel,
    );
    @memcpy(
        upl_p + idx_cpy_off,
        @as([*]const u8, @ptrCast(&cube.indices))[0..@sizeOf(@TypeOf(cube.indices))],
    );
    @memcpy(
        upl_p + vert_cpy_off,
        @as([*]const u8, @ptrCast(&cube.data))[0..@sizeOf(@TypeOf(cube.data))],
    );
    for (0..Data.frame_n) |i| {
        @memcpy(
            upl_p + unif_off * i + xform_cpy_off,
            @as([*]const u8, @ptrCast(&transform))[0..@sizeOf(Transform)],
        );
        @memcpy(
            upl_p + unif_off * i + light_cpy_off,
            @as([*]const u8, @ptrCast(&light))[0..@sizeOf(Light)],
        );
        @memcpy(
            upl_p + unif_off * i + matl_cpy_off,
            @as([*]const u8, @ptrCast(&material))[0..@sizeOf(Material)],
        );
    }

    var cmd = try d.submit.buffers[0].begin(gpa, dev, .{
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
            .image = &d.texture.image,
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
        .buffer = &d.upload.buffer,
        .image = &d.texture.image,
        .image_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .buffer_offset = pixel_cpy_off,
            .buffer_row_length = 1,
            .buffer_image_height = 1,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = 1,
            .image_height = 1,
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
            .image = &d.texture.image,
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
    cmd.copyBuffer(&.{
        .{
            .source = &d.upload.buffer,
            .dest = &d.index.buffer,
            .regions = &.{.{
                .source_offset = idx_cpy_off,
                .dest_offset = 0,
                .size = @sizeOf(@TypeOf(cube.indices)),
            }},
        },
        .{
            .source = &d.upload.buffer,
            .dest = &d.vertex.buffer,
            .regions = &.{.{
                .source_offset = vert_cpy_off,
                .dest_offset = 0,
                .size = @sizeOf(@TypeOf(cube.data)),
            }},
        },
        .{
            .source = &d.upload.buffer,
            .dest = &d.uniform.buffer,
            .regions = &.{.{
                .source_offset = xform_cpy_off,
                .dest_offset = 0,
                .size = Data.frame_n * unif_off,
            }},
        },
    });
    try cmd.end();

    {
        ctx.lockQueue(d.submit.queue_index);
        defer ctx.unlockQueue(d.submit.queue_index);

        try ngl.Fence.reset(gpa, dev, &.{&d.submit.fences[0]});

        try dev.queues[d.submit.queue_index].submit(gpa, dev, &d.submit.fences[0], &.{.{
            .commands = &.{.{ .command_buffer = &d.submit.buffers[0] }},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&d.submit.fences[0]});

    // Render ----------------------------------------------

    var frame: usize = 0;
    var timer = try std.time.Timer.start();
    const need_queue_transfer = d.present.need_queue_transfer;

    while (timer.read() < std.time.ns_per_min) {
        if (plat.poll().done) break;

        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&d.submit.fences[frame]});
        try ngl.Fence.reset(gpa, dev, &.{&d.submit.fences[frame]});

        // TODO: Confirm that reusing the 2nd semaphore is valid
        // since presentation is not waited for.
        const semas = .{ &d.submit.semaphores[frame * 2], &d.submit.semaphores[frame * 2 + 1] };

        const next = try plat.swap_chain.nextImage(dev, std.time.ns_per_s, semas[0], null);

        try d.submit.pools[frame].reset(dev, .keep);
        cmd = try d.submit.buffers[frame].begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });
        cmd.beginRenderPass(.{
            .render_pass = &d.pass.render_pass,
            .frame_buffer = &d.pass.frame_buffers[next],
            .render_area = .{
                .x = 0,
                .y = 0,
                .width = Data.width,
                .height = Data.height,
            },
            .clear_values = &.{
                .{ .color_f32 = .{ 0.6, 0.6, 0, 1 } },
                .{ .depth_stencil = .{ 1, undefined } },
            },
        }, .{ .contents = .inline_only });
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
        cmd.setPipeline(&d.state.pipeline);
        cmd.setDescriptors(.graphics, &d.descriptor.pipeline_layout, 0, &.{
            &d.descriptor.sets[frame * 2],
            &d.descriptor.sets[frame * 2 + 1],
        });
        cmd.setIndexBuffer(cube.index_type, &d.index.buffer, 0, @sizeOf(@TypeOf(cube.indices)));
        cmd.setVertexBuffers(
            0,
            &.{
                &d.vertex.buffer,
                &d.vertex.buffer,
                &d.vertex.buffer,
            },
            &.{
                @offsetOf(@TypeOf(cube.data), "position"),
                @offsetOf(@TypeOf(cube.data), "normal"),
                @offsetOf(@TypeOf(cube.data), "tex_coord"),
            },
            &.{
                @sizeOf(@TypeOf(cube.data.position)),
                @sizeOf(@TypeOf(cube.data.normal)),
                @sizeOf(@TypeOf(cube.data.tex_coord)),
            },
        );
        cmd.drawIndexed(cube.indices.len, 1, 0, 0, 0);
        cmd.endRenderPass(.{});
        if (need_queue_transfer)
            // TODO: Record a queue transfer.
            @panic("TODO");
        try cmd.end();

        ctx.lockQueue(d.submit.queue_index);
        defer ctx.unlockQueue(d.submit.queue_index);

        try dev.queues[d.submit.queue_index].submit(gpa, dev, &d.submit.fences[frame], &.{.{
            .commands = &.{.{ .command_buffer = &d.submit.buffers[frame] }},
            .wait = &.{.{
                .semaphore = semas[0],
                .stage_mask = .{ .color_attachment_output = true },
            }},
            .signal = &.{.{
                .semaphore = semas[1],
                .stage_mask = .{ .color_attachment_output = true },
            }},
        }});

        const pres_sema = if (need_queue_transfer) {
            // TODO: Record a queue transfer for the present queue, lock it
            // and submit the command for execution (will need to use
            // pool/buffer/semaphore from `Data.present`).
            @panic("TODO");
        } else semas[1];

        try dev.queues[d.present.queue_index].present(gpa, dev, &.{pres_sema}, &.{.{
            .swap_chain = &plat.swap_chain,
            .image_index = next,
        }});

        frame = (frame + 1) % Data.frame_n;
    }

    try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 5, blk: {
        var fences: [Data.frame_n]*ngl.Fence = undefined;
        for (0..fences.len) |i| fences[i] = &d.submit.fences[i];
        break :blk &fences;
    });
}

const Data = struct {
    const frame_n = 2;
    const width = Platform.width;
    const height = Platform.height;

    depth: struct {
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.image = try ngl.Image.init(gpa, device, .{
                .type = .@"2d",
                .format = .d16_unorm,
                .width = width,
                .height = height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = .@"1",
                .tiling = .optimal,
                .usage = .{ .depth_stencil_attachment = true },
                .misc = .{},
                .initial_layout = .unknown,
            });
            self.memory = blk: {
                errdefer self.image.deinit(gpa, device);
                const mem_reqs = self.image.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{ .device_local = true }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.image.bind(device, &mem, 0);
                break :blk mem;
            };
            self.view = ngl.ImageView.init(gpa, device, .{
                .image = &self.image,
                .type = .@"2d",
                .format = .d16_unorm,
                .range = .{
                    .aspect_mask = .{ .depth = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            }) catch |err| {
                self.image.deinit(gpa, device);
                device.free(gpa, &self.memory);
                return err;
            };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.view.deinit(gpa, device);
            self.image.deinit(gpa, device);
            device.free(gpa, &self.memory);
            self.* = undefined;
        }
    },

    texture: struct {
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,
        sampler: ngl.Sampler,

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.image = try ngl.Image.init(gpa, device, .{
                .type = .@"2d",
                .format = .rgba8_unorm,
                .width = 1,
                .height = 1,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = .@"1",
                .tiling = .optimal,
                .usage = .{ .sampled_image = true, .transfer_dest = true },
                .misc = .{},
                .initial_layout = .unknown,
            });
            self.memory = blk: {
                errdefer self.image.deinit(gpa, device);
                const mem_reqs = self.image.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{ .device_local = true }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.image.bind(device, &mem, 0);
                break :blk mem;
            };
            errdefer {
                self.image.deinit(gpa, device);
                device.free(gpa, &self.memory);
            }
            self.view = try ngl.ImageView.init(gpa, device, .{
                .image = &self.image,
                .type = .@"2d",
                .format = .rgba8_unorm,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            });
            errdefer self.view.deinit(gpa, device);
            self.sampler = try ngl.Sampler.init(gpa, device, .{
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
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.sampler.deinit(gpa, device);
            self.view.deinit(gpa, device);
            self.image.deinit(gpa, device);
            device.free(gpa, &self.memory);
            self.* = undefined;
        }
    },

    index: struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.buffer = try ngl.Buffer.init(gpa, device, .{
                .size = @sizeOf(@TypeOf(cube.indices)),
                .usage = .{ .index_buffer = true, .transfer_dest = true },
            });
            self.memory = blk: {
                errdefer self.buffer.deinit(gpa, device);
                const mem_reqs = self.buffer.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{ .device_local = true }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.buffer.bind(device, &mem, 0);
                break :blk mem;
            };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.buffer.deinit(gpa, device);
            device.free(gpa, &self.memory);
            self.* = undefined;
        }
    },

    vertex: struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.buffer = try ngl.Buffer.init(gpa, device, .{
                .size = @sizeOf(@TypeOf(cube.data)),
                .usage = .{ .vertex_buffer = true, .transfer_dest = true },
            });
            self.memory = blk: {
                errdefer self.buffer.deinit(gpa, device);
                const mem_reqs = self.buffer.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{ .device_local = true }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.buffer.bind(device, &mem, 0);
                break :blk mem;
            };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.buffer.deinit(gpa, device);
            device.free(gpa, &self.memory);
            self.* = undefined;
        }
    },

    uniform: struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,

        const size = frame_n * 3 * 256;

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.buffer = try ngl.Buffer.init(gpa, device, .{
                .size = size,
                .usage = .{ .uniform_buffer = true, .transfer_dest = true },
            });
            self.memory = blk: {
                errdefer self.buffer.deinit(gpa, device);
                const mem_reqs = self.buffer.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{ .device_local = true }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.buffer.bind(device, &mem, 0);
                break :blk mem;
            };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.buffer.deinit(gpa, device);
            device.free(gpa, &self.memory);
        }
    },

    upload: struct {
        buffer: ngl.Buffer,
        memory: ngl.Memory,

        const size = 1 << 20;

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.buffer = try ngl.Buffer.init(gpa, device, .{
                .size = size,
                .usage = .{ .transfer_source = true },
            });
            self.memory = blk: {
                errdefer self.buffer.deinit(gpa, device);
                const mem_reqs = self.buffer.getMemoryRequirements(device);
                var mem = try device.alloc(gpa, .{
                    .size = mem_reqs.size,
                    .type_index = mem_reqs.findType(device.*, .{
                        .host_visible = true,
                        .host_coherent = true,
                    }, null).?,
                });
                errdefer device.free(gpa, &mem);
                try self.buffer.bind(device, &mem, 0);
                break :blk mem;
            };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.buffer.deinit(gpa, device);
            device.free(gpa, &self.memory);
            self.* = undefined;
        }
    },

    descriptor: struct {
        set_layouts: [2]ngl.DescriptorSetLayout,
        pipeline_layout: ngl.PipelineLayout,
        pool: ngl.DescriptorPool,
        sets: [frame_n * 2]ngl.DescriptorSet,

        fn init(self: *@This(), device: *ngl.Device) ngl.Error!void {
            self.set_layouts[0] = try ngl.DescriptorSetLayout.init(gpa, device, .{
                .bindings = &.{
                    // Transform.
                    .{
                        .binding = 0,
                        .type = .uniform_buffer,
                        .count = 1,
                        .stage_mask = .{ .vertex = true },
                        .immutable_samplers = null,
                    },
                    // Light.
                    .{
                        .binding = 1,
                        .type = .uniform_buffer,
                        .count = 1,
                        .stage_mask = .{ .fragment = true },
                        .immutable_samplers = null,
                    },
                },
            });
            errdefer self.set_layouts[0].deinit(gpa, device);
            self.set_layouts[1] = try ngl.DescriptorSetLayout.init(gpa, device, .{
                .bindings = &.{
                    // Material.
                    .{
                        .binding = 0,
                        .type = .uniform_buffer,
                        .count = 1,
                        .stage_mask = .{ .fragment = true },
                        .immutable_samplers = null,
                    },
                    // Base color.
                    .{
                        .binding = 1,
                        .type = .combined_image_sampler,
                        .count = 1,
                        .stage_mask = .{ .fragment = true },
                        .immutable_samplers = null,
                    },
                },
            });
            errdefer self.set_layouts[1].deinit(gpa, device);
            self.pipeline_layout = try ngl.PipelineLayout.init(gpa, device, .{
                .descriptor_set_layouts = &.{ &self.set_layouts[0], &self.set_layouts[1] },
                .push_constant_ranges = null,
            });
            errdefer self.pipeline_layout.deinit(gpa, device);
            self.pool = try ngl.DescriptorPool.init(gpa, device, .{
                .max_sets = frame_n * 2,
                .pool_size = .{ .uniform_buffer = frame_n * 3, .combined_image_sampler = frame_n },
            });
            errdefer self.pool.deinit(gpa, device);
            const layts = [_]*ngl.DescriptorSetLayout{
                &self.set_layouts[0],
                &self.set_layouts[1],
            } ** frame_n;
            const sets = try self.pool.alloc(gpa, device, .{ .layouts = &layts });
            @memcpy(&self.sets, sets);
            gpa.free(sets);
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.pool.deinit(gpa, device);
            self.pipeline_layout.deinit(gpa, device);
            self.set_layouts[0].deinit(gpa, device);
            self.set_layouts[1].deinit(gpa, device);
            self.* = undefined;
        }
    },

    pass: struct {
        render_pass: ngl.RenderPass,
        frame_buffers: []ngl.FrameBuffer,

        fn init(
            self: *@This(),
            device: *ngl.Device,
            swap_chain_format: ngl.Format,
            swap_chain_views: []ngl.ImageView,
            depth_format: ngl.Format,
            depth_view: *ngl.ImageView,
        ) ngl.Error!void {
            self.render_pass = try ngl.RenderPass.init(gpa, device, .{
                .attachments = &.{
                    .{
                        .format = swap_chain_format,
                        .samples = .@"1",
                        .load_op = .clear,
                        .store_op = .store,
                        .initial_layout = .unknown,
                        .final_layout = .present_source,
                        .resolve_mode = null,
                        .combined = null,
                        .may_alias = false,
                    },
                    .{
                        .format = depth_format,
                        .samples = .@"1",
                        .load_op = .clear,
                        .store_op = .dont_care,
                        .initial_layout = .unknown,
                        .final_layout = .depth_stencil_attachment_optimal,
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
            errdefer self.render_pass.deinit(gpa, device);
            self.frame_buffers = try gpa.alloc(ngl.FrameBuffer, swap_chain_views.len);
            for (self.frame_buffers, swap_chain_views, 0..) |*fb, *sc_view, i|
                fb.* = ngl.FrameBuffer.init(gpa, device, .{
                    .render_pass = &self.render_pass,
                    .attachments = &.{ sc_view, depth_view },
                    .width = width,
                    .height = height,
                    .layers = 1,
                }) catch |err| {
                    for (0..i) |j| self.frame_buffers[j].deinit(gpa, device);
                    gpa.free(self.frame_buffers);
                    return err;
                };
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            for (self.frame_buffers) |*fb| fb.deinit(gpa, device);
            gpa.free(self.frame_buffers);
            self.render_pass.deinit(gpa, device);
            self.* = undefined;
        }
    },

    state: struct {
        pipeline: ngl.Pipeline,

        const vert_spv align(4) = @embedFile("shader/ads/vert.spv").*;
        const frag_spv align(4) = @embedFile("shader/ads/frag.spv").*;

        fn init(
            self: *@This(),
            device: *ngl.Device,
            layout: *ngl.PipelineLayout,
            render_pass: *ngl.RenderPass,
        ) ngl.Error!void {
            const s = try ngl.Pipeline.initGraphics(gpa, device, .{
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
                    .layout = layout,
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
                            // Position.
                            .{
                                .location = 0,
                                .binding = 0,
                                .format = .rgb32_sfloat,
                                .offset = 0,
                            },
                            // Normal.
                            .{
                                .location = 1,
                                .binding = 1,
                                .format = .rgb32_sfloat,
                                .offset = 0,
                            },
                            // Texture coordinates.
                            .{
                                .location = 2,
                                .binding = 2,
                                .format = .rg32_sfloat,
                                .offset = 0,
                            },
                        },
                        .topology = cube.topology,
                    },
                    .rasterization = &.{
                        .polygon_mode = .fill,
                        .cull_mode = .back,
                        .clockwise = cube.clockwise,
                        .samples = .@"1",
                    },
                    .depth_stencil = &.{
                        .depth_compare = .less_equal,
                        .depth_write = true,
                        .stencil_front = null,
                        .stencil_back = null,
                    },
                    .color_blend = &.{
                        .attachments = &.{.{ .blend = null, .write = .all }},
                    },
                    .render_pass = render_pass,
                    .subpass = 0,
                }},
                .cache = null,
            });
            self.pipeline = s[0];
            gpa.free(s);
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            self.pipeline.deinit(gpa, device);
            self.* = undefined;
        }
    },

    submit: struct {
        queue_index: ngl.Queue.Index,
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        // Signaled.
        fences: [frame_n]ngl.Fence,
        semaphores: [frame_n * 2]ngl.Semaphore,

        fn init(self: *@This(), device: *ngl.Device, queue_index: ngl.Queue.Index) ngl.Error!void {
            self.queue_index = queue_index;
            var pool_i: usize = 0;
            errdefer for (self.pools[0..pool_i]) |*pool| pool.deinit(gpa, device);
            for (&self.pools) |*pool| {
                pool.* = try ngl.CommandPool.init(
                    gpa,
                    device,
                    .{ .queue = &device.queues[queue_index] },
                );
                pool_i += 1;
            }
            for (&self.buffers, &self.pools) |*buf, *pool| {
                const s = try pool.alloc(gpa, device, .{ .level = .primary, .count = 1 });
                buf.* = s[0];
                gpa.free(s);
            }
            var fence_i: usize = 0;
            errdefer for (self.fences[0..fence_i]) |*fence| fence.deinit(gpa, device);
            for (&self.fences) |*fence| {
                fence.* = try ngl.Fence.init(gpa, device, .{ .initial_status = .signaled });
                fence_i += 1;
            }
            var sema_i: usize = 0;
            errdefer for (self.semaphores[0..sema_i]) |*sema| sema.deinit(gpa, device);
            for (&self.semaphores) |*sema| {
                sema.* = try ngl.Semaphore.init(gpa, device, .{});
                sema_i += 1;
            }
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            for (&self.pools) |*pool| pool.deinit(gpa, device);
            for (&self.fences) |*fence| fence.deinit(gpa, device);
            for (&self.semaphores) |*sema| sema.deinit(gpa, device);
            self.* = undefined;
        }
    },

    present: struct {
        queue_index: ngl.Queue.Index,
        need_queue_transfer: bool,
        // The following are invalid if `!need_queue_transfer`.
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        semaphores: [frame_n]ngl.Semaphore,

        fn init(
            self: *@This(),
            device: *ngl.Device,
            queue_index: ngl.Queue.Index,
            need_queue_transfer: bool,
        ) ngl.Error!void {
            self.queue_index = queue_index;
            self.need_queue_transfer = need_queue_transfer;
            if (!need_queue_transfer) return;
            var pool_i: usize = 0;
            errdefer for (self.pools[0..pool_i]) |*pool| pool.deinit(gpa, device);
            for (&self.pools) |*pool| {
                pool.* = try ngl.CommandPool.init(
                    gpa,
                    device,
                    .{ .queue = &device.queues[queue_index] },
                );
                pool_i += 1;
            }
            for (&self.buffers, &self.pools) |*buf, *pool| {
                const s = try pool.alloc(gpa, device, .{ .level = .primary, .count = 1 });
                buf.* = s[0];
                gpa.free(s);
            }
            var sema_i: usize = 0;
            errdefer for (self.semaphores[0..sema_i]) |*sema| sema.deinit(gpa, device);
            for (&self.semaphores) |*sema| {
                sema.* = try ngl.Semaphore.init(gpa, device, .{});
                sema_i += 1;
            }
        }

        fn deinit(self: *@This(), device: *ngl.Device) void {
            if (self.need_queue_transfer) {
                for (&self.pools) |*pool| pool.deinit(gpa, device);
                for (&self.semaphores) |*sema| sema.deinit(gpa, device);
            }
            self.* = undefined;
        }
    },

    fn init(
        device: *ngl.Device,
        present_queue_index: ngl.Queue.Index,
        swap_chain_format: ngl.Format,
        swap_chain_views: []ngl.ImageView,
    ) ngl.Error!@This() {
        const present_queue = &device.queues[present_queue_index];
        const submit_queue_index = if (present_queue.capabilities.graphics)
            present_queue_index
        else
            device.findQueue(.{ .graphics = true }, null) orelse return error.NotSupported;
        var self: @This() = undefined;
        try self.depth.init(device);
        errdefer self.depth.deinit(device);
        try self.texture.init(device);
        errdefer self.texture.deinit(device);
        try self.index.init(device);
        errdefer self.index.deinit(device);
        try self.vertex.init(device);
        errdefer self.vertex.deinit(device);
        try self.uniform.init(device);
        errdefer self.uniform.deinit(device);
        try self.upload.init(device);
        errdefer self.upload.deinit(device);
        try self.descriptor.init(device);
        errdefer self.descriptor.deinit(device);
        try self.pass.init(
            device,
            swap_chain_format,
            swap_chain_views,
            .d16_unorm,
            &self.depth.view,
        );
        errdefer self.pass.deinit(device);
        try self.state.init(device, &self.descriptor.pipeline_layout, &self.pass.render_pass);
        errdefer self.state.deinit(device);
        try self.submit.init(device, submit_queue_index);
        errdefer self.submit.deinit(device);
        try self.present.init(
            device,
            present_queue_index,
            present_queue_index != submit_queue_index,
        );
        errdefer self.present.deinit(device);
        return self;
    }

    fn deinit(self: *@This(), device: *ngl.Device) void {
        self.depth.deinit(device);
        self.texture.deinit(device);
        self.index.deinit(device);
        self.vertex.deinit(device);
        self.uniform.deinit(device);
        self.upload.deinit(device);
        self.descriptor.deinit(device);
        self.pass.deinit(device);
        self.state.deinit(device);
        self.submit.deinit(device);
        self.present.deinit(device);
    }
};
