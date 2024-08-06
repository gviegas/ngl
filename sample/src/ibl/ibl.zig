const std = @import("std");
const log = std.log.scoped(.sample);
const assert = std.debug.assert;
const builtin = @import("builtin");

const ngl = @import("ngl");
const pfm = ngl.pfm;

const Ctx = @import("Ctx");
const mdata = @import("mdata");
const idata = @import("idata");
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
const light_n = 2;
const material_n = 9 * 2;
const render_dielectric = true;
const msaa_count: ?ngl.SampleCount = .@"4";
const sphere_n = material_n;
const draw_n = sphere_n;
const width = 1280;
const height = 720;

var ctx: Ctx = undefined;
var dev: *ngl.Device = undefined;
var plat: *pfm.Platform = undefined;

fn do(gpa: std.mem.Allocator) !void {
    ctx = try Ctx.init(gpa);
    defer ctx.deinit(gpa);
    dev = &ctx.device;
    plat = &ctx.platform;

    var col_ms = try Color(.ms).init(gpa);
    defer col_ms.deinit(gpa);

    var col_s1 = try Color(.@"1").init(gpa);
    defer col_s1.deinit(gpa);

    var depth = try Depth.init(gpa, &col_ms);
    defer depth.deinit(gpa);

    var sphr = try mdata.loadObj(gpa, "data/model/sphere.obj");
    defer sphr.deinit(gpa);
    assert(sphr.indices == null);
    const cube = &mdata.cube;

    const idx_buf_size = @sizeOf(cube.Indices);
    var idx_buf = try Buffer(.device).init(gpa, idx_buf_size, .{
        .index_buffer = true,
        .transfer_dest = true,
    });
    defer idx_buf.deinit(gpa);

    const sphr_pos_off = 0;
    const sphr_norm_off = sphr_pos_off + sphr.sizeOfPositions();
    const cube_pos_off = sphr_norm_off + sphr.sizeOfPositions();
    const vert_buf_size = cube_pos_off + @sizeOf(cube.Positions);
    var vert_buf = try Buffer(.device).init(gpa, vert_buf_size, .{
        .vertex_buffer = true,
        .transfer_dest = true,
    });
    defer vert_buf.deinit(gpa);

    const cam_off = 0;
    const light_off = (cam_off + Camera.size + 255) & ~@as(u64, 255);
    const matl_off = (light_off + Light.size + 255) & ~@as(u64, 255);
    const model_off = matl_off + material_n * ((Material.size + 255) & ~@as(u64, 255));
    const unif_strd = model_off + draw_n * ((Model.size + 255) & ~@as(u64, 255));
    const unif_buf_size = frame_n * unif_strd;
    var unif_buf = try Buffer(.device).init(gpa, unif_buf_size, .{
        .uniform_buffer = true,
        .transfer_dest = true,
    });
    defer unif_buf.deinit(gpa);

    const idx_cpy_off = 0;
    const vert_cpy_off = (idx_cpy_off + idx_buf_size + 3) & ~@as(u64, 3);
    const unif_cpy_off = (vert_cpy_off + vert_buf_size + 3) & ~@as(u64, 3);
    const dist_cpy_off = (unif_cpy_off + unif_buf_size + 3) & ~@as(u64, 3);
    const cmap_cpy_off = (dist_cpy_off + Distribution.size + 511) & ~@as(u64, 511);

    var loader: struct {
        buffer: ?Buffer(.host) = null,
        size_per_layer: u64 = 0,
        offset: u64,
        allocator: std.mem.Allocator,

        pub fn get(self: *@This(), size: u64) ![]u8 {
            const buf = self.buffer orelse blk: {
                self.buffer = try Buffer(.host).init(
                    self.allocator,
                    self.offset + size * 6,
                    .{ .transfer_source = true },
                );
                self.size_per_layer = size;
                break :blk self.buffer.?;
            };
            assert(size == self.size_per_layer);
            defer self.offset += size;
            return buf.data[self.offset .. self.offset + size];
        }
    } = .{
        .offset = cmap_cpy_off,
        .allocator = gpa,
    };

    const Rgba = extern struct {
        r: f16,
        g: f16,
        b: f16,
        a: f16,
    };
    var cmap_fmt: ?ngl.Format = null;
    var cmap_xtnt: u32 = 0;
    var cmap_lum: f32 = 0;
    inline for (.{
        "+x",
        "-x",
        "-y",
        "+y",
        "-z",
        "+z",
    }) |face| {
        var file = try std.fs.cwd().openFile("data/image/" ++ face ++ ".hdri", .{});
        defer file.close();
        const reader = file.reader();
        const w = try reader.readInt(u32, .little);
        const h = try reader.readInt(u32, .little);
        assert(w == h);
        const data = try loader.get(w * h * @sizeOf(Rgba));
        if (try reader.read(data) != w * h * @sizeOf(Rgba))
            return error.ReadFailed;

        if (cmap_fmt == null) {
            cmap_fmt = ngl.Format.rgba16_sfloat;
            cmap_xtnt = w;
        }
        assert(w == cmap_xtnt);

        const cp = @as([*]Rgba, @ptrCast(@alignCast(data)));
        const cs = cp[0 .. w * h];
        for (cs) |*c| {
            if (builtin.cpu.arch.endian() == .big) {
                c.r = @bitCast(@byteSwap(@as(u16, @bitCast(c.r))));
                c.g = @bitCast(@byteSwap(@as(u16, @bitCast(c.g))));
                c.b = @bitCast(@byteSwap(@as(u16, @bitCast(c.b))));
                c.a = @bitCast(@byteSwap(@as(u16, @bitCast(c.a))));
            }
            assert(!std.math.isNan(c.r) and !std.math.isInf(c.r));
            assert(!std.math.isNan(c.g) and !std.math.isInf(c.g));
            assert(!std.math.isNan(c.b) and !std.math.isInf(c.b));
            assert(!std.math.isNan(c.a) and !std.math.isInf(c.a));
            const lum = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;
            cmap_lum += lum;
        }
    }
    cmap_lum /= width * height * 6;
    const ev_100 = @log2(cmap_lum * 100 / 12.5);
    var cube_map = try CubeMap.init(gpa, cmap_fmt.?, cmap_xtnt, ev_100);
    defer cube_map.deinit(gpa);

    var dist = try Distribution.init(gpa);
    defer dist.deinit(gpa);

    var ld = try Ld.init(gpa);
    defer ld.deinit(gpa);

    var dfg = try Dfg.init(gpa);
    defer dfg.deinit(gpa);

    var irrad = try Irradiance.init(gpa);
    defer irrad.deinit(gpa);

    var lum = try Luminance.init(gpa);
    defer lum.deinit(gpa);

    var stg_buf = loader.buffer.?;
    defer stg_buf.deinit(gpa);

    var pre_desc = try PreDescriptor.init(gpa, &cube_map, &ld);
    defer pre_desc.deinit(gpa);

    var desc = try Descriptor.init(gpa, &col_s1, &cube_map, &ld, &dfg, &irrad, &lum);
    defer desc.deinit(gpa);

    var pre_shd = try PreShader.init(gpa, &pre_desc);
    defer pre_shd.deinit(gpa);

    var shd = try Shader.init(gpa, &desc, &cube_map);
    defer shd.deinit(gpa);

    var cq = try Command.init(gpa);
    defer cq.deinit(gpa);
    const one_queue = cq.multiqueue == null;

    var cam = Camera.init(.{ 0, 0, -3.5 }, .{ 0, 0, 0 });

    const light = Light.init(.{
        .{
            .position = .{ -10, -20, -10 },
            .intensity = 1000,
        },
        .{
            .position = .{ 5, -25, -3 },
            .intensity = 750,
        },
    });

    const matls = blk: {
        var matls: [material_n]Material = undefined;
        var smooth: f32 = 1 - 1e-3;
        for (&matls, 0..) |*matl, i| {
            matl.* = if (i & 1 == 0) Material.initDielectric(
                .{ 0, 0, 0, 1 },
                smooth,
                0.04,
            ) else Material.initConductor(
                .{ 0.659777, 0.608679, 0.525649, 1 },
                smooth,
            );
            if (i & 1 == 1)
                smooth = @max(0, smooth - (2 / (@as(f32, material_n - 1))));
        }
        break :blk matls;
    };

    const models = blk: {
        const s = 0.3;
        const d = s * 2.5;
        const scale = gmath.m4f.s(s, s, s);
        const y = d * 0.5;
        var x: f32 = -d * draw_n * 0.25 + d * 0.5;
        var models: [draw_n]Model = undefined;
        for (0..draw_n / 2) |i| {
            models[i * 2] = Model.init(gmath.m4f.mul(gmath.m4f.t(x, -y, 0), scale));
            models[i * 2 + 1] = Model.init(gmath.m4f.mul(gmath.m4f.t(x, y, 0), scale));
            x += d;
        }
        break :blk models;
    };

    const idx_data = stg_buf.data[idx_cpy_off .. idx_cpy_off + idx_buf_size];
    @memcpy(idx_data, std.mem.asBytes(&cube.indices));

    const vert_data = stg_buf.data[vert_cpy_off .. vert_cpy_off + vert_buf_size];
    @memcpy(
        vert_data[sphr_pos_off .. sphr_pos_off + sphr.sizeOfPositions()],
        std.mem.sliceAsBytes(sphr.positions.items),
    );
    @memcpy(
        vert_data[sphr_norm_off .. sphr_norm_off + sphr.sizeOfNormals()],
        std.mem.sliceAsBytes(sphr.normals.items),
    );
    @memcpy(
        vert_data[cube_pos_off .. cube_pos_off + @sizeOf(cube.Positions)],
        std.mem.asBytes(&cube.vertices.positions),
    );

    const dist_data = stg_buf.data[dist_cpy_off..][0..Distribution.size];
    const dist_data_f32 = @as(
        [*]f32,
        @ptrCast(@alignCast(dist_data)),
    )[0 .. dist_data.len / @sizeOf(f32)];

    assert(dist_data_f32.len & 1 == 0);

    for (0..dist_data_f32.len / 2) |i| {
        const xi = Distribution.hammersley(@intCast(i));
        const s = dist_data_f32[i * 2 ..][0..2];
        s.* = xi;
    }

    for (0..frame_n) |frame| {
        const strd = frame * unif_strd;
        const data = stg_buf.data[unif_cpy_off + strd ..][0..unif_strd];

        cam.copy(data[cam_off .. cam_off + Camera.size]);
        light.copy(data[light_off .. light_off + Light.size]);

        for (matls, 0..) |matl, i| {
            const off = matl_off + i * ((Material.size + 255) & ~@as(u64, 255));
            matl.copy(data[off .. off + Material.size]);
        }

        for (models, 0..) |model, i| {
            const off = model_off + i * ((Model.size + 255) & ~@as(u64, 255));
            model.copy(data[off .. off + Model.size]);
        }
    }

    try pre_desc.writeSet0(gpa, &cube_map, &dist, &dfg, &irrad);
    try pre_desc.writeSet1(gpa, &cube_map, &ld);

    try desc.writeSet0(gpa, &col_s1, &cube_map, &ld, &dfg, &irrad, &lum, &unif_buf.buffer, blk: {
        var offs: [frame_n]u64 = undefined;
        for (&offs, 0..) |*off, frame|
            off.* = frame * unif_strd + cam_off;
        break :blk offs;
    }, blk: {
        var offs: [frame_n]u64 = undefined;
        for (&offs, 0..) |*off, frame|
            off.* = frame * unif_strd + light_off;
        break :blk offs;
    });

    try desc.writeSet1(gpa, &unif_buf.buffer, blk: {
        var offs: [frame_n][material_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, matl| {
                off.* = frame * unif_strd + matl_off +
                    matl * ((Material.size + 255) & ~@as(u64, 255));
            };
        break :blk offs;
    });

    try desc.writeSet2(gpa, &unif_buf.buffer, blk: {
        var offs: [frame_n][draw_n]u64 = undefined;
        for (&offs, 0..) |*frm_offs, frame|
            for (frm_offs, 0..) |*off, draw| {
                off.* = frame * unif_strd + model_off +
                    draw * ((Model.size + 255) & ~@as(u64, 255));
            };
        break :blk offs;
    });

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
        .{
            .source = &stg_buf.buffer,
            .dest = &dist.buffer.buffer,
            .regions = &.{.{
                .source_offset = dist_cpy_off,
                .dest_offset = 0,
                .size = Distribution.size,
            }},
        },
    });

    cmd.barrier(&.{.{
        .image = &.{.{
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
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 6,
            },
        }},
        .buffer = &.{.{
            .source_stage_mask = .{ .copy = true },
            .source_access_mask = .{ .transfer_write = true },
            .dest_stage_mask = .{ .compute_shader = true },
            .dest_access_mask = .{ .shader_storage_read = true },
            .queue_transfer = null,
            .buffer = &dist.buffer.buffer,
            .offset = 0,
            .size = Distribution.size,
        }},
    }});

    cmd.copyBufferToImage(&.{.{
        .buffer = &stg_buf.buffer,
        .image = &cube_map.image,
        .image_layout = .transfer_dest_optimal,
        .regions = &.{.{
            .buffer_offset = cmap_cpy_off,
            .buffer_row_length = cmap_xtnt,
            .buffer_image_height = cmap_xtnt,
            .image_aspect = .color,
            .image_level = 0,
            .image_x = 0,
            .image_y = 0,
            .image_z_or_layer = 0,
            .image_width = cmap_xtnt,
            .image_height = cmap_xtnt,
            .image_depth_or_layers = 6,
        }},
    }});

    cmd.barrier(&.{.{
        .image = &.{
            .{
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_sampled_read = true },
                .queue_transfer = null,
                .old_layout = .transfer_dest_optimal,
                .new_layout = .shader_read_only_optimal,
                .image = &cube_map.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 6,
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
                .image = &ld.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = Ld.mip_sizes.len,
                    .layer = 0,
                    .layers = 6,
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
                .image = &dfg.image,
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
                .image = &irrad.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 6,
                },
            },
        },
    }});

    cmd.setDescriptors(.compute, &pre_shd.layout, 0, &.{&pre_desc.sets[0]});

    for (0..Ld.mip_sizes.len) |level| {
        cmd.setDescriptors(.compute, &pre_shd.layout, 1, &.{&pre_desc.sets[1][level]});

        for (0..6) |layer| {
            cmd.setShaders(&.{.compute}, &.{&pre_shd.pre_ld[level * 6 + layer]});
            cmd.dispatch(Ld.mip_sizes[level], Ld.mip_sizes[level], 1);
        }

        cmd.barrier(&.{.{
            .image = &.{.{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_write = true },
                .dest_stage_mask = .{ .compute_shader = true },
                .dest_access_mask = .{ .shader_sampled_read = true },
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .shader_read_only_optimal,
                .image = &ld.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = @intCast(level),
                    .levels = 1,
                    .layer = 0,
                    .layers = 6,
                },
            }},
        }});
    }

    cmd.setShaders(&.{.compute}, &.{&pre_shd.pre_dfg});
    cmd.dispatch(Dfg.extent, Dfg.extent, 1);

    for (0..6) |layer| {
        cmd.setShaders(&.{.compute}, &.{&pre_shd.pre_irradiance[layer]});
        cmd.dispatch(Irradiance.extent, Irradiance.extent, 1);
    }

    cmd.barrier(&.{.{
        .image = &.{
            .{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_write = true },
                .dest_stage_mask = .{},
                .dest_access_mask = .{},
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .shader_read_only_optimal,
                .image = &dfg.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            },
            .{
                .source_stage_mask = .{ .compute_shader = true },
                .source_access_mask = .{ .shader_storage_write = true },
                .dest_stage_mask = .{},
                .dest_access_mask = .{},
                .queue_transfer = null,
                .old_layout = .general,
                .new_layout = .shader_read_only_optimal,
                .image = &irrad.image,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 6,
                },
            },
        },
    }});

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

    var timer = try std.time.Timer.start();
    var prev_input = pfm.Platform.Input{};

    while (true) {
        const dt: f32 = @floatCast(@as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_s);

        const input = plat.poll();
        if (input.done)
            break;
        if (input.option and !prev_input.option) {
            // TODO
        } else if (input.option_2 and !prev_input.option_2) {
            // TODO
        }
        if (input.up) {
            cam.rotateFixedX(dt);
        } else if (input.down) {
            cam.rotateFixedX(-dt);
        }
        if (input.left) {
            cam.rotateFixedY(-dt);
        } else if (input.right) {
            cam.rotateFixedY(dt);
        }
        prev_input = input;

        const unif_upd_off = frame * unif_strd + cam_off;
        const unif_upd_size = Camera.size;
        cam.copy(stg_buf.data[unif_cpy_off + unif_upd_off ..][0..unif_upd_size]);

        const cmd_pool = &cq.pools[frame];
        const cmd_buf = &cq.buffers[frame];
        const sems = .{ &cq.semaphores[frame * 2], &cq.semaphores[frame * 2 + 1] };
        const fnc = &cq.fences[frame];

        // TODO: Only pre-integrations should take long.
        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s * 10, &.{fnc});
        try ngl.Fence.reset(gpa, dev, &.{fnc});
        const next = try plat.swapchain.nextImage(dev, std.time.ns_per_s, sems[0], null);

        try cmd_pool.reset(dev, .keep);
        cmd = try cmd_buf.begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });

        cmd.copyBuffer(&.{.{
            .source = &stg_buf.buffer,
            .dest = &unif_buf.buffer,
            .regions = &.{.{
                .source_offset = unif_cpy_off + unif_upd_off,
                .dest_offset = unif_upd_off,
                .size = unif_upd_size,
            }},
        }});

        cmd.barrier(&.{.{
            .buffer = &.{.{
                .source_stage_mask = .{ .copy = true },
                .source_access_mask = .{ .transfer_write = true },
                .dest_stage_mask = .{
                    .vertex_shader = true,
                    .fragment_shader = true,
                },
                .dest_access_mask = .{ .uniform_read = true },
                .queue_transfer = null,
                .buffer = &unif_buf.buffer,
                .offset = unif_upd_off,
                .size = unif_upd_size,
            }},
        }});

        inline for (.{ .graphics, .compute }) |bp|
            cmd.setDescriptors(bp, &shd.layout, 0, &.{&desc.sets[0][frame]});
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
        cmd.setSampleMask(~@as(u64, 0));
        cmd.setDepthBiasEnable(false);
        cmd.setStencilTestEnable(false);
        cmd.setColorBlendEnable(0, &.{false});
        cmd.setColorWrite(0, &.{.all});

        cmd.setSampleCount(col_ms.samples);
        cmd.setDepthTestEnable(true);
        cmd.setDepthCompareOp(.less_equal);
        cmd.setDepthWriteEnable(true);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &col_ms.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .fragment_shader = true },
                    .source_access_mask = .{ .shader_sampled_read = true },
                    .dest_stage_mask = .{ .color_attachment_output = true },
                    .dest_access_mask = .{ .color_attachment_write = true },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .color_attachment_optimal,
                    .image = &col_s1.image,
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
                .view = &col_ms.view,
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .color_f32 = .{ 0.5, 0.5, 0.5, 1 } },
                .resolve = .{
                    .view = &col_s1.view,
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
            .stencil = blk: {
                assert(!depth.format.getAspectMask().stencil);
                break :blk null;
            },
            .render_area = .{ .width = width, .height = height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.vertex, &shd.fragment });
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
            &.{ &vert_buf.buffer, &vert_buf.buffer },
            &.{ sphr_pos_off, sphr_norm_off },
            &.{ sphr.sizeOfPositions(), sphr.sizeOfNormals() },
        );
        cmd.setCullMode(.back);
        cmd.setFrontFace(.counter_clockwise);
        for (0..sphere_n) |i| {
            cmd.setDescriptors(.graphics, &shd.layout, 1, &.{
                &desc.sets[1][frame][i % material_n],
                &desc.sets[2][frame][i],
            });
            cmd.draw(sphr.vertexCount(), 1, 0, 0);
        }

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.sky_box_vertex, &shd.sky_box_fragment });
        cmd.setVertexInput(&.{.{
            .binding = 0,
            .stride = 3 * @sizeOf(f32),
            .step_rate = .vertex,
        }}, &.{.{
            .location = 0,
            .binding = 0,
            .format = .rgb32_sfloat,
            .offset = 0,
        }});
        cmd.setPrimitiveTopology(cube.topology);
        cmd.setIndexBuffer(cube.index_type, &idx_buf.buffer, 0, idx_buf_size);
        cmd.setVertexBuffers(
            0,
            &.{&vert_buf.buffer},
            &.{cube_pos_off},
            &.{@sizeOf(cube.Positions)},
        );
        cmd.setCullMode(.front);
        cmd.setFrontFace(cube.front_face);
        cmd.drawIndexed(cube.indices.len, 1, 0, 0, 0);

        cmd.endRendering();

        cmd.setSampleCount(.@"1");
        cmd.setDepthTestEnable(false);
        cmd.setDepthWriteEnable(false);

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .color_attachment_output = true },
                    .source_access_mask = .{ .color_attachment_write = true },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .color_attachment_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .image = &col_s1.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{
                        .shader_sampled_read = true,
                        .shader_storage_write = true,
                    },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{
                        .shader_sampled_read = true,
                        .shader_storage_write = true,
                    },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .general,
                    .image = &lum.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 0,
                        .layers = 1,
                    },
                },
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{
                        .shader_sampled_read = true,
                        .shader_storage_write = true,
                    },
                    .dest_stage_mask = .{ .compute_shader = true },
                    .dest_access_mask = .{
                        .shader_sampled_read = true,
                        .shader_storage_write = true,
                    },
                    .queue_transfer = null,
                    .old_layout = .unknown,
                    .new_layout = .shader_read_only_optimal,
                    .image = &lum.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = 1,
                        .layers = 1,
                    },
                },
            },
        }});

        for (Luminance.iterations, 0..) |iter, i| {
            cmd.setShaders(&.{.compute}, &.{
                &if (i == 0)
                    shd.luminance_1st
                else if (i & 1 == 0)
                    shd.luminance_even
                else
                    shd.luminance_odd,
            });
            cmd.dispatch(iter[0], iter[1], 1);

            if (i == Luminance.iterations.len - 1)
                break;

            cmd.barrier(&.{.{
                .image = &.{
                    .{
                        .source_stage_mask = .{ .compute_shader = true },
                        .source_access_mask = .{ .shader_storage_write = true },
                        .dest_stage_mask = .{ .compute_shader = true },
                        .dest_access_mask = .{ .shader_sampled_read = true },
                        .queue_transfer = null,
                        .old_layout = .general,
                        .new_layout = .shader_read_only_optimal,
                        .image = &lum.image,
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .level = 0,
                            .levels = 1,
                            .layer = @intCast(i & 1),
                            .layers = 1,
                        },
                    },
                    .{
                        .source_stage_mask = .{ .compute_shader = true },
                        .source_access_mask = .{ .shader_sampled_read = true },
                        .dest_stage_mask = .{ .compute_shader = true },
                        .dest_access_mask = .{ .shader_storage_write = true },
                        .queue_transfer = null,
                        .old_layout = .shader_read_only_optimal,
                        .new_layout = .general,
                        .image = &lum.image,
                        .range = .{
                            .aspect_mask = .{ .color = true },
                            .level = 0,
                            .levels = 1,
                            .layer = @intCast(i + 1 & 1),
                            .layers = 1,
                        },
                    },
                },
            }});
        }

        cmd.barrier(&.{.{
            .image = &.{
                .{
                    .source_stage_mask = .{ .compute_shader = true },
                    .source_access_mask = .{ .shader_storage_write = true },
                    .dest_stage_mask = .{ .fragment_shader = true },
                    .dest_access_mask = .{ .shader_sampled_read = true },
                    .queue_transfer = null,
                    .old_layout = .general,
                    .new_layout = .shader_read_only_optimal,
                    .image = &lum.image,
                    .range = .{
                        .aspect_mask = .{ .color = true },
                        .level = 0,
                        .levels = 1,
                        .layer = Luminance.final_view,
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
            },
        }});

        cmd.beginRendering(.{
            .colors = &.{.{
                .view = &plat.image_views[next],
                .layout = .color_attachment_optimal,
                .load_op = .dont_care,
                .store_op = .store,
                .clear_value = null,
                .resolve = null,
            }},
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = width, .height = height },
            .layers = 1,
            .contents = .@"inline",
        });

        cmd.setShaders(&.{ .vertex, .fragment }, &.{ &shd.screen, &shd.final });
        cmd.setVertexInput(&.{}, &.{});
        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setCullMode(.back);
        cmd.setFrontFace(.clockwise);
        cmd.draw(3, 1, 0, 0);

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

fn Color(comptime msr: enum { ms, @"1" }) type {
    return struct {
        samples: ngl.SampleCount,
        image: ngl.Image,
        memory: ngl.Memory,
        view: ngl.ImageView,
        sampler: switch (msr) {
            .ms => void,
            .@"1" => ngl.Sampler,
        },

        const format = ngl.Format.rgba16_sfloat;

        fn init(gpa: std.mem.Allocator) ngl.Error!@This() {
            const @"type" = .@"2d";
            const tiling = .optimal;
            const usage = .{
                .sampled_image = msr == .@"1",
                .color_attachment = true,
                .transient_attachment = msr == .ms,
            };
            const misc = ngl.Image.Misc{};
            const spls: ngl.SampleCount = switch (msr) {
                .ms => blk: {
                    const capab = try ngl.Image.getCapabilities(
                        dev,
                        @"type",
                        format,
                        tiling,
                        usage,
                        misc,
                    );
                    if (msaa_count) |s| {
                        if (@field(capab.sample_counts, @tagName(s)))
                            break :blk s;
                        return ngl.Error.NotSupported;
                    }
                    inline for (&[_]ngl.SampleCount{
                        .@"32",
                        .@"16",
                        .@"8",
                        .@"4",
                    }) |s| {
                        if (@field(capab.sample_counts, @tagName(s)))
                            break :blk s;
                    }
                    unreachable;
                },
                .@"1" => .@"1",
            };

            var img = try ngl.Image.init(gpa, dev, .{
                .type = @"type",
                .format = format,
                .width = width,
                .height = height,
                .depth_or_layers = 1,
                .levels = 1,
                .samples = spls,
                .tiling = tiling,
                .usage = usage,
                .misc = misc,
            });
            errdefer img.deinit(gpa, dev);

            var mem = blk: {
                const reqs = img.getMemoryRequirements(dev);
                var mem = try dev.alloc(gpa, .{
                    .size = reqs.size,
                    .type_index = reqs.findType(dev.*, .{
                        .device_local = true,
                        .lazily_allocated = msr == .ms,
                    }, null) orelse reqs.findType(dev.*, .{ .device_local = true }, null).?,
                });
                errdefer dev.free(gpa, &mem);
                try img.bind(dev, &mem, 0);
                break :blk mem;
            };
            errdefer dev.free(gpa, &mem);

            var view = try ngl.ImageView.init(gpa, dev, .{
                .image = &img,
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

            const splr = switch (msr) {
                .ms => {},
                .@"1" => try ngl.Sampler.init(gpa, dev, .{
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
                }),
            };

            return .{
                .samples = spls,
                .image = img,
                .memory = mem,
                .view = view,
                .sampler = splr,
            };
        }

        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.view.deinit(gpa, dev);
            self.image.deinit(gpa, dev);
            dev.free(gpa, &self.memory);
            switch (msr) {
                .ms => {},
                .@"1" => self.sampler.deinit(gpa, dev),
            }
        }
    };
}

const Depth = struct {
    format: ngl.Format,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,

    fn init(gpa: std.mem.Allocator, color_ms: *Color(.ms)) ngl.Error!Depth {
        const @"type" = .@"2d";
        const tiling = .optimal;
        const usage = .{
            .depth_stencil_attachment = true,
            .transient_attachment = true,
        };
        const misc = ngl.Image.Misc{};
        const fmt = for ([_]ngl.Format{
            .d32_sfloat,
            .x8_d24_unorm,
            .d16_unorm,
        }) |fmt| {
            const opt = fmt.getFeatures(dev).optimal_tiling;
            if (!opt.depth_stencil_attachment)
                continue;
            const capab = try ngl.Image.getCapabilities(dev, @"type", fmt, tiling, usage, misc);
            const spl_cnt = ngl.flag.fromEnum(color_ms.samples);
            if (!ngl.flag.empty(ngl.flag.@"and"(spl_cnt, capab.sample_counts)))
                break fmt;
        } else return ngl.Error.NotSupported;

        var img = try ngl.Image.init(gpa, dev, .{
            .type = @"type",
            .format = fmt,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = color_ms.samples,
            .tiling = tiling,
            .usage = usage,
            .misc = misc,
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
            .format = fmt,
            .range = .{
                .aspect_mask = .{ .depth = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });

        return .{
            .format = fmt,
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

const CubeMap = struct {
    format: ngl.Format,
    extent: u32,
    ev_100: f32,
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    fn init(
        gpa: std.mem.Allocator,
        format: ngl.Format,
        extent: u32,
        ev_100: f32,
    ) ngl.Error!CubeMap {
        if (@popCount(extent) != 1 or extent < Ld.mip_sizes[0])
            return ngl.Error.InvalidArgument;
        const ratio = extent / Ld.mip_sizes[0];
        if (ratio > 2)
            log.warn(
                "Cube map's extent is {}x larger than prefiltered environment map's",
                .{ratio},
            );

        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 6,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .transfer_dest = true,
            },
            .misc = .{ .cube_compatible = true },
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
            .type = .cube,
            .format = format,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 6,
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
            .format = format,
            .extent = extent,
            .ev_100 = ev_100,
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *CubeMap, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const Distribution = struct {
    buffer: Buffer(.device),

    const sample_n = 1024;
    const element_size = @sizeOf(f32) * 2;
    const size = sample_n * element_size;

    fn init(gpa: std.mem.Allocator) ngl.Error!Distribution {
        return .{
            .buffer = try Buffer(.device).init(gpa, size, .{
                .storage_buffer = true,
                .transfer_dest = true,
            }),
        };
    }

    fn vanDerCorput(i: u32) f32 {
        var x = (i << 16) | (i >> 16);
        x = ((x & 0x55555555) << 1) | ((x & 0xaaaaaaaa) >> 1);
        x = ((x & 0x33333333) << 2) | ((x & 0xcccccccc) >> 2);
        x = ((x & 0x0f0f0f0f) << 4) | ((x & 0xf0f0f0f0) >> 4);
        x = ((x & 0x00ff00ff) << 8) | ((x & 0xff00ff00) >> 8);
        const xf: f64 = @floatFromInt(x);
        const fac: f64 = 2.3283064365386963e-10;
        return @floatCast(xf * fac);
    }

    fn hammersley(i: u32) [2]f32 {
        return .{
            @as(f32, @floatFromInt(i)) / sample_n,
            vanDerCorput(i),
        };
    }

    fn deinit(self: *Distribution, gpa: std.mem.Allocator) void {
        self.buffer.deinit(gpa);
    }
};

const Ld = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    views: [mip_sizes.len + 1]ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rgba16_sfloat;
    const mip_sizes = [_]u32{
        256,
        128,
        64,
        32,
        16,
        8,
        4,
    };

    fn init(gpa: std.mem.Allocator) ngl.Error!Ld {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = mip_sizes[0],
            .height = mip_sizes[0],
            .depth_or_layers = 6,
            .levels = mip_sizes.len,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
            },
            .misc = .{ .cube_compatible = true },
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var views: [mip_sizes.len + 1]ngl.ImageView = undefined;
        for (&views, 0..) |*view, i|
            view.* = ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .cube,
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = if (i == mip_sizes.len) 0 else @intCast(i),
                    .levels = if (i == mip_sizes.len) mip_sizes.len else 1,
                    .layer = 0,
                    .layers = 6,
                },
            }) catch |err| {
                for (0..i) |j|
                    views[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (views[0..mip_sizes.len]) |*view|
            view.deinit(gpa, dev);

        const splr = try ngl.Sampler.init(gpa, dev, .{
            .normalized_coordinates = true,
            .u_address = .clamp_to_edge,
            .v_address = .clamp_to_edge,
            .w_address = .clamp_to_edge,
            .border_color = null,
            .mag = .linear,
            .min = .linear,
            .mipmap = .linear,
            .min_lod = 0,
            .max_lod = null,
            .max_anisotropy = null,
            .compare = null,
        });

        return .{
            .image = img,
            .memory = mem,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *Ld, gpa: std.mem.Allocator) void {
        for (&self.views) |*view|
            view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const Dfg = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    // TODO: Should be `rg16_sfloat` (note that we will use it
    // as storage image).
    const format = ngl.Format.rgba16_sfloat;
    const extent = 128;

    fn init(gpa: std.mem.Allocator) ngl.Error!Dfg {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
            },
            .misc = .{},
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
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
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *Dfg, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const Irradiance = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    view: ngl.ImageView,
    sampler: ngl.Sampler,

    const format = ngl.Format.rgba16_sfloat;
    const extent = 32;
    const phi_delta = 2 * std.math.pi / 256.0;
    const theta_delta = 0.5 * std.math.pi / 64.0;

    fn init(gpa: std.mem.Allocator) ngl.Error!Irradiance {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = extent,
            .height = extent,
            .depth_or_layers = 6,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
            },
            .misc = .{ .cube_compatible = true },
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var view = try ngl.ImageView.init(gpa, dev, .{
            .image = &img,
            .type = .cube,
            .format = format,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 6,
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
            .image = img,
            .memory = mem,
            .view = view,
            .sampler = splr,
        };
    }

    fn deinit(self: *Irradiance, gpa: std.mem.Allocator) void {
        self.view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
    }
};

const Luminance = struct {
    image: ngl.Image,
    memory: ngl.Memory,
    views: [2]ngl.ImageView,
    sampler: ngl.Sampler,

    const format = Color(.@"1").format;
    const divisor = 2;
    const group_count_x: u32 = @max(1, (width + 1) / divisor);
    const group_count_y: u32 = @max(1, (height + 1) / divisor);

    const iterations = blk: {
        const max: f64 = @max(group_count_x, group_count_y);
        const n: i32 = if (divisor == 2) 1 + @ceil(@log2(max)) else unreachable;
        var iters: [n][2]u32 = undefined;
        var cnts: @Vector(2, u32) = .{ group_count_x, group_count_y };
        for (&iters) |*iter| {
            iter.* = .{ @max(1, cnts[0]), @max(1, cnts[1]) };
            cnts += @splat(1 - (divisor & 1));
            cnts /= @splat(divisor);
        }
        break :blk iters;
    };

    const final_view = iterations.len + 1 & 1;

    fn init(gpa: std.mem.Allocator) ngl.Error!Luminance {
        var img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = format,
            .width = group_count_x,
            .height = group_count_y,
            .depth_or_layers = 2,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{
                .sampled_image = true,
                .storage_image = true,
            },
            .misc = .{},
        });
        errdefer img.deinit(gpa, dev);

        var mem = blk: {
            const reqs = img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = reqs.size,
                .type_index = reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &mem);

        var views: [2]ngl.ImageView = undefined;
        for (&views, 0..) |*view, i|
            view.* = ngl.ImageView.init(gpa, dev, .{
                .image = &img,
                .type = .@"2d",
                .format = format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = @intCast(i),
                    .layers = 1,
                },
            }) catch |err| {
                for (0..i) |j|
                    views[j].deinit(gpa, dev);
                return err;
            };
        errdefer for (&views) |*view|
            view.deinit(gpa, dev);

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
            .image = img,
            .memory = mem,
            .views = views,
            .sampler = splr,
        };
    }

    fn deinit(self: *Luminance, gpa: std.mem.Allocator) void {
        for (&self.views) |*view|
            view.deinit(gpa, dev);
        self.image.deinit(gpa, dev);
        dev.free(gpa, &self.memory);
        self.sampler.deinit(gpa, dev);
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

const PreDescriptor = struct {
    set_layouts: [2]ngl.DescriptorSetLayout,
    pool: ngl.DescriptorPool,
    sets: struct {
        ngl.DescriptorSet,
        [Ld.mip_sizes.len]ngl.DescriptorSet,
    },

    const bindings = struct {
        const distribution = 0;
        const dfg = 1;
        const irradiance_comb = 2;
        const irradiance_stor = 3;

        const ld_comb = 0;
        const ld_stor = 1;
    };

    fn init(gpa: std.mem.Allocator, cube_map: *CubeMap, ld: *Ld) ngl.Error!PreDescriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = bindings.distribution,
                    .type = .storage_buffer,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = bindings.dfg,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = bindings.irradiance_comb,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{&cube_map.sampler},
                },
                .{
                    .binding = bindings.irradiance_stor,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt.deinit(gpa, dev);

        var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = bindings.ld_comb,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{&ld.sampler},
                },
                .{
                    .binding = bindings.ld_stor,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
            },
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = 1 + Ld.mip_sizes.len,
            .pool_size = .{
                .combined_image_sampler = 1 + Ld.mip_sizes.len,
                .storage_image = 2 + Ld.mip_sizes.len,
                .storage_buffer = 1,
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = try pool.alloc(gpa, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** Ld.mip_sizes.len,
        });
        defer gpa.free(sets);

        return .{
            .set_layouts = .{ set_layt, set_layt_2 },
            .pool = pool,
            .sets = .{
                sets[0],
                sets[1 .. 1 + Ld.mip_sizes.len].*,
            },
        };
    }

    fn writeSet0(
        self: *PreDescriptor,
        gpa: std.mem.Allocator,
        cube_map: *CubeMap,
        distribution: *Distribution,
        dfg: *Dfg,
        irradiance: *Irradiance,
    ) ngl.Error!void {
        var writes: [4]ngl.DescriptorSet.Write = undefined;
        const stor_dist = &writes[0];
        const stor_dfg = &writes[1];
        const comb_irrad = &writes[2];
        const stor_irrad = &writes[3];

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [1]Bw = undefined;
        var bw: []Bw = &bw_arr;

        const Iw = ngl.DescriptorSet.Write.ImageWrite;
        var iw_arr: [2]Iw = undefined;
        var iw: []Iw = &iw_arr;

        const Isw = ngl.DescriptorSet.Write.ImageSamplerWrite;
        var isw_arr: [1]Isw = undefined;
        var isw: []Isw = &isw_arr;

        inline for (
            .{bindings.distribution},
            .{&distribution.buffer.buffer},
            .{0},
            .{Distribution.size},
            .{stor_dist},
        ) |bind, buf, off, size, stor| {
            bw[0] = .{
                .buffer = buf,
                .offset = off,
                .size = size,
            };
            stor.* = .{
                .descriptor_set = &self.sets[0],
                .binding = bind,
                .element = 0,
                .contents = .{ .storage_buffer = bw[0..1] },
            };
            bw = bw[1..];
        }

        inline for (
            .{
                bindings.dfg,
                bindings.irradiance_stor,
            },
            .{
                &dfg.view,
                &irradiance.view,
            },
            .{
                stor_dfg,
                stor_irrad,
            },
        ) |bind, view, stor| {
            iw[0] = .{
                .view = view,
                .layout = .general,
            };
            stor.* = .{
                .descriptor_set = &self.sets[0],
                .binding = bind,
                .element = 0,
                .contents = .{ .storage_image = iw[0..1] },
            };
            iw = iw[1..];
        }

        inline for (
            .{bindings.irradiance_comb},
            .{&cube_map.view},
            .{comb_irrad},
        ) |bind, view, comb| {
            isw[0] = .{
                .view = view,
                .layout = .shader_read_only_optimal,
                .sampler = null,
            };
            comb.* = .{
                .descriptor_set = &self.sets[0],
                .binding = bind,
                .element = 0,
                .contents = .{ .combined_image_sampler = isw[0..1] },
            };
            isw = isw[1..];
        }

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn writeSet1(
        self: *PreDescriptor,
        gpa: std.mem.Allocator,
        cube_map: *CubeMap,
        ld: *Ld,
    ) ngl.Error!void {
        var writes: [Ld.mip_sizes.len * 2]ngl.DescriptorSet.Write = undefined;
        const comb_ld = writes[0..Ld.mip_sizes.len];
        const stor_ld = writes[Ld.mip_sizes.len..][0..Ld.mip_sizes.len];

        const Isw = ngl.DescriptorSet.Write.ImageSamplerWrite;
        var isw_arr: [Ld.mip_sizes.len]Isw = undefined;
        var isw: []Isw = &isw_arr;

        const Iw = ngl.DescriptorSet.Write.ImageWrite;
        var iw_arr: [Ld.mip_sizes.len]Iw = undefined;
        var iw: []Iw = &iw_arr;

        // TODO: Experiment using `CubeMap` as source in all
        // LD shaders (note that we will need to generate
        // mip levels for the cube map).
        for (
            &self.sets[1],
            &[_]ngl.ImageView{cube_map.view} ++ ld.views[0 .. Ld.mip_sizes.len - 1],
            ld.views[0..Ld.mip_sizes.len],
            comb_ld,
            stor_ld,
        ) |*set, *comb_view, *stor_view, *comb, *stor| {
            isw[0] = .{
                .view = comb_view,
                .layout = .shader_read_only_optimal,
                .sampler = null,
            };
            comb.* = .{
                .descriptor_set = set,
                .binding = bindings.ld_comb,
                .element = 0,
                .contents = .{ .combined_image_sampler = isw[0..1] },
            };
            iw[0] = .{
                .view = stor_view,
                .layout = .general,
            };
            stor.* = .{
                .descriptor_set = set,
                .binding = bindings.ld_stor,
                .element = 0,
                .contents = .{ .storage_image = iw[0..1] },
            };
            isw = isw[1..];
            iw = iw[1..];
        }

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn deinit(self: *PreDescriptor, gpa: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const Descriptor = struct {
    set_layouts: [3]ngl.DescriptorSetLayout,
    pool: ngl.DescriptorPool,
    sets: struct {
        [frame_n]ngl.DescriptorSet,
        [frame_n][material_n]ngl.DescriptorSet,
        [frame_n][draw_n]ngl.DescriptorSet,
    },

    const bindings = struct {
        const color = 0;
        const cube_map = 1;
        const ld = 2;
        const dfg = 3;
        const irradiance = 4;
        const luminance_comb = 5;
        const luminance_comb_2 = 6;
        const luminance_stor = 7;
        const luminance_stor_2 = 8;
        const camera = 9;
        const light = 10;

        const material = 0;

        const model = 0;
    };

    fn init(
        gpa: std.mem.Allocator,
        color: *Color(.@"1"),
        cube_map: *CubeMap,
        ld: *Ld,
        dfg: *Dfg,
        irradiance: *Irradiance,
        luminance: *Luminance,
    ) ngl.Error!Descriptor {
        var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{
                .{
                    .binding = bindings.color,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&color.sampler},
                },
                .{
                    .binding = bindings.cube_map,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&cube_map.sampler},
                },
                .{
                    .binding = bindings.ld,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&ld.sampler},
                },
                .{
                    .binding = bindings.dfg,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&dfg.sampler},
                },
                .{
                    .binding = bindings.irradiance,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .fragment = true },
                    .immutable_samplers = &.{&irradiance.sampler},
                },
                .{
                    .binding = bindings.luminance_comb,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&luminance.sampler},
                },
                .{
                    .binding = bindings.luminance_comb_2,
                    .type = .combined_image_sampler,
                    .count = 1,
                    .shader_mask = .{ .compute = true, .fragment = true },
                    .immutable_samplers = &.{&luminance.sampler},
                },
                .{
                    .binding = bindings.luminance_stor,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = bindings.luminance_stor_2,
                    .type = .storage_image,
                    .count = 1,
                    .shader_mask = .{ .compute = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = bindings.camera,
                    .type = .uniform_buffer,
                    .count = 1,
                    .shader_mask = .{ .vertex = true, .fragment = true },
                    .immutable_samplers = &.{},
                },
                .{
                    .binding = bindings.light,
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
                .binding = bindings.material,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .fragment = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_2.deinit(gpa, dev);

        var set_layt_3 = try ngl.DescriptorSetLayout.init(gpa, dev, .{
            .bindings = &.{.{
                .binding = bindings.model,
                .type = .uniform_buffer,
                .count = 1,
                .shader_mask = .{ .vertex = true },
                .immutable_samplers = &.{},
            }},
        });
        errdefer set_layt_3.deinit(gpa, dev);

        var pool = try ngl.DescriptorPool.init(gpa, dev, .{
            .max_sets = frame_n * (1 + material_n + draw_n),
            .pool_size = .{
                .combined_image_sampler = frame_n * 7,
                .storage_image = frame_n * 2,
                .uniform_buffer = frame_n * (2 + material_n + draw_n),
            },
        });
        errdefer pool.deinit(gpa, dev);

        const sets = try pool.alloc(gpa, dev, .{
            .layouts = &[_]*ngl.DescriptorSetLayout{&set_layt} ** frame_n ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_2} ** (frame_n * material_n) ++
                &[_]*ngl.DescriptorSetLayout{&set_layt_3} ** (frame_n * draw_n),
        });
        defer gpa.free(sets);

        return .{
            .set_layouts = .{ set_layt, set_layt_2, set_layt_3 },
            .pool = pool,
            .sets = .{
                sets[0..frame_n].*,
                blk: {
                    var dest: [frame_n][material_n]ngl.DescriptorSet = undefined;
                    var source = sets[frame_n..];
                    for (&dest) |*d| {
                        d.* = source[0..material_n].*;
                        source = source[material_n..];
                    }
                    break :blk dest;
                },
                blk: {
                    var dest: [frame_n][draw_n]ngl.DescriptorSet = undefined;
                    var source = sets[frame_n * (1 + material_n) ..];
                    for (&dest) |*d| {
                        d.* = source[0..draw_n].*;
                        source = source[draw_n..];
                    }
                    break :blk dest;
                },
            },
        };
    }

    fn writeSet0(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        color: *Color(.@"1"),
        cube_map: *CubeMap,
        ld: *Ld,
        dfg: *Dfg,
        irradiance: *Irradiance,
        luminance: *Luminance,
        uniform_buffer: *ngl.Buffer,
        camera_offsets: [frame_n]u64,
        light_offsets: [frame_n]u64,
    ) ngl.Error!void {
        var writes: [frame_n * 11]ngl.DescriptorSet.Write = undefined;
        const comb_col = writes[0..frame_n];
        const comb_cube = writes[frame_n .. frame_n * 2];
        const comb_ld = writes[frame_n * 2 .. frame_n * 3];
        const comb_dfg = writes[frame_n * 3 .. frame_n * 4];
        const comb_irrad = writes[frame_n * 4 .. frame_n * 5];
        const comb_lum = writes[frame_n * 5 .. frame_n * 6];
        const comb_lum_2 = writes[frame_n * 6 .. frame_n * 7];
        const stor_lum = writes[frame_n * 7 .. frame_n * 8];
        const stor_lum_2 = writes[frame_n * 8 .. frame_n * 9];
        const unif_cam = writes[frame_n * 9 .. frame_n * 10];
        const unif_light = writes[frame_n * 10 .. frame_n * 11];

        const Isw = ngl.DescriptorSet.Write.ImageSamplerWrite;
        var isw_arr: [frame_n * 7]Isw = undefined;
        var isw: []Isw = &isw_arr;

        const Iw = ngl.DescriptorSet.Write.ImageWrite;
        var iw_arr: [frame_n * 2]Iw = undefined;
        var iw: []Iw = &iw_arr;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [frame_n * 2]Bw = undefined;
        var bw: []Bw = &bw_arr;

        inline for (
            .{
                bindings.color,
                bindings.cube_map,
                bindings.ld,
                bindings.dfg,
                bindings.irradiance,
                bindings.luminance_comb,
                bindings.luminance_comb_2,
            },
            .{
                &color.view,
                &cube_map.view,
                &ld.views[Ld.mip_sizes.len],
                &dfg.view,
                &irradiance.view,
                &luminance.views[1],
                &luminance.views[0],
            },
            .{
                comb_col,
                comb_cube,
                comb_ld,
                comb_dfg,
                comb_irrad,
                comb_lum,
                comb_lum_2,
            },
        ) |bind, view, combs|
            for (combs, &self.sets[0]) |*comb, *set| {
                isw[0] = .{
                    .view = view,
                    .layout = .shader_read_only_optimal,
                    .sampler = null,
                };
                comb.* = .{
                    .descriptor_set = set,
                    .binding = bind,
                    .element = 0,
                    .contents = .{ .combined_image_sampler = isw[0..1] },
                };
                isw = isw[1..];
            };

        inline for (
            .{
                bindings.luminance_stor,
                bindings.luminance_stor_2,
            },
            .{
                &luminance.views[0],
                &luminance.views[1],
            },
            .{
                stor_lum,
                stor_lum_2,
            },
        ) |bind, view, stors|
            for (stors, &self.sets[0]) |*stor, *set| {
                iw[0] = .{
                    .view = view,
                    .layout = .general,
                };
                stor.* = .{
                    .descriptor_set = set,
                    .binding = bind,
                    .element = 0,
                    .contents = .{ .storage_image = iw[0..1] },
                };
                iw = iw[1..];
            };

        inline for (
            .{
                bindings.camera,
                bindings.light,
            },
            .{
                Camera.size,
                Light.size,
            },
            .{
                camera_offsets,
                light_offsets,
            },
            .{
                unif_cam,
                unif_light,
            },
        ) |bind, size, offs, unifs|
            for (unifs, &self.sets[0], offs) |*unif, *set, off| {
                bw[0] = .{
                    .buffer = uniform_buffer,
                    .offset = off,
                    .size = size,
                };
                unif.* = .{
                    .descriptor_set = set,
                    .binding = bind,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };
                bw = bw[1..];
            };

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn writeSet1(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        material_offsets: [frame_n][material_n]u64,
    ) ngl.Error!void {
        try self.writeSet1Or2(Material, gpa, uniform_buffer, material_offsets);
    }

    fn writeSet2(
        self: *Descriptor,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        model_offsets: [frame_n][draw_n]u64,
    ) ngl.Error!void {
        try self.writeSet1Or2(Model, gpa, uniform_buffer, model_offsets);
    }

    fn writeSet1Or2(
        self: *Descriptor,
        comptime T: type,
        gpa: std.mem.Allocator,
        uniform_buffer: *ngl.Buffer,
        offsets: switch (T) {
            Material => [frame_n][material_n]u64,
            Model => [frame_n][draw_n]u64,
            else => unreachable,
        },
    ) ngl.Error!void {
        const n, const set_idx, const bind = switch (T) {
            Material => .{
                frame_n * material_n,
                1,
                bindings.material,
            },
            Model => .{
                frame_n * draw_n,
                2,
                bindings.model,
            },
            else => unreachable,
        };

        var writes: [n]ngl.DescriptorSet.Write = undefined;
        var w: []ngl.DescriptorSet.Write = &writes;

        const Bw = ngl.DescriptorSet.Write.BufferWrite;
        var bw_arr: [n]Bw = undefined;
        var bw: []Bw = &bw_arr;

        for (&self.sets[set_idx], offsets) |*sets, offs|
            for (sets, offs) |*set, off| {
                bw[0] = .{
                    .buffer = uniform_buffer,
                    .offset = off,
                    .size = T.size,
                };
                w[0] = .{
                    .descriptor_set = set,
                    .binding = bind,
                    .element = 0,
                    .contents = .{ .uniform_buffer = bw[0..1] },
                };
                bw = bw[1..];
                w = w[1..];
            };

        try ngl.DescriptorSet.write(gpa, dev, &writes);
    }

    fn deinit(self: *Descriptor, gpa: std.mem.Allocator) void {
        for (&self.set_layouts) |*layt|
            layt.deinit(gpa, dev);
        self.pool.deinit(gpa, dev);
    }
};

const PreShader = struct {
    pre_ld: [Ld.mip_sizes.len * 6]ngl.Shader,
    pre_dfg: ngl.Shader,
    pre_irradiance: [6]ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(gpa: std.mem.Allocator, pre_descriptor: *PreDescriptor) ngl.Error!PreShader {
        const dapi = ctx.gpu.getDriverApi();

        const pre_ld_code_spv align(4) = @embedFile("shader/pre_ld.comp.spv").*;
        const pre_ld_code = switch (dapi) {
            .vulkan => &pre_ld_code_spv,
        };

        const pre_dfg_code_spv align(4) = @embedFile("shader/pre_dfg.comp.spv").*;
        const pre_dfg_code = switch (dapi) {
            .vulkan => &pre_dfg_code_spv,
        };

        const pre_irrad_code_spv align(4) = @embedFile("shader/pre_irradiance.comp.spv").*;
        const pre_irrad_code = switch (dapi) {
            .vulkan => &pre_irrad_code_spv,
        };

        const set_layts = &.{
            &pre_descriptor.set_layouts[0],
            &pre_descriptor.set_layouts[1],
        };

        const PreLdSpecData = packed struct {
            layer: u32,
            inv_group_size: f32,
            roughness: f32,
            sample_n: u32,
        };
        const pre_ld_spec_n = @typeInfo(PreLdSpecData).Struct.fields.len;

        const pre_ld_spec_consts, const pre_ld_spec_data = blk: {
            const strd = @sizeOf(PreLdSpecData);
            const consts_n = Ld.mip_sizes.len * 6 * pre_ld_spec_n;
            const data_n = Ld.mip_sizes.len * 6;
            var spec_consts: [consts_n]ngl.Shader.Specialization.Constant = undefined;
            var spec_data: [data_n]PreLdSpecData = undefined;

            for (0..Ld.mip_sizes.len) |level| {
                const rough = @as(f32, @floatFromInt(level)) / @as(f32, Ld.mip_sizes.len);
                for (0..6) |layer| {
                    const base_off: u32 = @intCast(strd * level * 6 + strd * layer);
                    inline for (@typeInfo(PreLdSpecData).Struct.fields, 0..) |field, id| {
                        const off = base_off + @offsetOf(PreLdSpecData, field.name);
                        spec_consts[level * 6 * pre_ld_spec_n + layer * pre_ld_spec_n + id] = .{
                            .id = id,
                            .offset = off,
                            .size = @sizeOf(field.type),
                        };
                    }
                    spec_data[level * 6 + layer] = .{
                        .layer = @intCast(layer),
                        .inv_group_size = 1 / @as(f32, @floatFromInt(Ld.mip_sizes[level])),
                        .roughness = rough * rough,
                        .sample_n = Distribution.sample_n,
                    };
                }
            }

            break :blk .{ spec_consts, spec_data };
        };

        const PreDfgSpecData = packed struct {
            inv_group_size: f32,
            sample_n: u32,
        };
        const pre_dfg_spec_n = @typeInfo(PreDfgSpecData).Struct.fields.len;

        const pre_dfg_spec_consts, const pre_dfg_spec_data = blk: {
            var spec_consts: [pre_dfg_spec_n]ngl.Shader.Specialization.Constant = undefined;
            inline for (@typeInfo(PreDfgSpecData).Struct.fields, 0..) |field, id|
                spec_consts[id] = .{
                    .id = id,
                    .offset = @offsetOf(PreDfgSpecData, field.name),
                    .size = @sizeOf(field.type),
                };
            break :blk .{ spec_consts, PreDfgSpecData{
                .inv_group_size = 1 / @as(f32, Dfg.extent),
                .sample_n = Distribution.sample_n,
            } };
        };

        const PreIrradSpecData = packed struct {
            layer: u32,
            inv_group_size: f32,
            phi_delta: f32,
            theta_delta: f32,
        };
        const pre_irrad_spec_n = @typeInfo(PreIrradSpecData).Struct.fields.len;

        const pre_irrad_spec_consts, const pre_irrad_spec_data = blk: {
            const strd = @sizeOf(PreIrradSpecData);
            var spec_consts: [6 * pre_irrad_spec_n]ngl.Shader.Specialization.Constant = undefined;
            var spec_data: [6]PreIrradSpecData = undefined;

            for (0..6) |layer| {
                const base_off: u32 = @intCast(strd * layer);
                inline for (@typeInfo(PreIrradSpecData).Struct.fields, 0..) |field, id| {
                    const off = base_off + @offsetOf(PreIrradSpecData, field.name);
                    spec_consts[layer * pre_ld_spec_n + id] = .{
                        .id = id,
                        .offset = off,
                        .size = @sizeOf(field.type),
                    };
                }
                spec_data[layer] = .{
                    .layer = @intCast(layer),
                    .inv_group_size = 1 / @as(f32, Irradiance.extent),
                    .phi_delta = Irradiance.phi_delta,
                    .theta_delta = Irradiance.theta_delta,
                };
            }

            break :blk .{ spec_consts, spec_data };
        };

        const pre_ld_shds = blk: {
            var shd_descs: [Ld.mip_sizes.len * 6]ngl.Shader.Desc = undefined;
            for (&shd_descs, 0..) |*shd_desc, i| {
                shd_desc.* = .{
                    .type = .compute,
                    .next = .{},
                    .code = pre_ld_code,
                    .name = "main",
                    .set_layouts = set_layts,
                    .push_constants = &.{},
                    .specialization = .{
                        .constants = pre_ld_spec_consts[i * pre_ld_spec_n ..][0..pre_ld_spec_n],
                        .data = std.mem.asBytes(&pre_ld_spec_data),
                    },
                    .link = false,
                };
            }
            break :blk try ngl.Shader.init(gpa, dev, &shd_descs);
        };
        defer gpa.free(pre_ld_shds);
        errdefer for (pre_ld_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const pre_dfg_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .compute,
            .next = .{},
            .code = pre_dfg_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = .{
                .constants = &pre_dfg_spec_consts,
                .data = std.mem.asBytes(&pre_dfg_spec_data),
            },
            .link = false,
        }});
        defer gpa.free(pre_dfg_shd);
        errdefer if (pre_dfg_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        const pre_irrad_shds = blk: {
            var shd_descs: [6]ngl.Shader.Desc = undefined;
            for (&shd_descs, 0..) |*shd_desc, i| {
                const consts_i = i * pre_irrad_spec_n;
                shd_desc.* = .{
                    .type = .compute,
                    .next = .{},
                    .code = pre_irrad_code,
                    .name = "main",
                    .set_layouts = set_layts,
                    .push_constants = &.{},
                    .specialization = .{
                        .constants = pre_irrad_spec_consts[consts_i..][0..pre_irrad_spec_n],
                        .data = std.mem.asBytes(&pre_irrad_spec_data),
                    },
                    .link = false,
                };
            }
            break :blk try ngl.Shader.init(gpa, dev, &shd_descs);
        };
        defer gpa.free(pre_irrad_shds);
        errdefer for (pre_irrad_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });

        return .{
            .pre_ld = blk: {
                var shds: [Ld.mip_sizes.len * 6]ngl.Shader = undefined;
                for (&shds, pre_ld_shds) |*dest, source|
                    dest.* = try source;
                break :blk shds;
            },
            .pre_dfg = try pre_dfg_shd[0],
            .pre_irradiance = blk: {
                var shds: [6]ngl.Shader = undefined;
                for (&shds, pre_irrad_shds) |*dest, source|
                    dest.* = try source;
                break :blk shds;
            },
            .layout = layt,
        };
    }

    fn deinit(self: *PreShader, gpa: std.mem.Allocator) void {
        for (&self.pre_ld) |*shd|
            shd.deinit(gpa, dev);
        self.pre_dfg.deinit(gpa, dev);
        for (&self.pre_irradiance) |*shd|
            shd.deinit(gpa, dev);
        self.layout.deinit(gpa, dev);
    }
};

const Shader = struct {
    vertex: ngl.Shader,
    fragment: ngl.Shader,
    sky_box_vertex: ngl.Shader,
    sky_box_fragment: ngl.Shader,
    luminance_1st: ngl.Shader,
    luminance_even: ngl.Shader,
    luminance_odd: ngl.Shader,
    screen: ngl.Shader,
    final: ngl.Shader,
    layout: ngl.ShaderLayout,

    fn init(gpa: std.mem.Allocator, descriptor: *Descriptor, cube_map: *CubeMap) ngl.Error!Shader {
        const dapi = ctx.gpu.getDriverApi();

        const vert_code_spv align(4) = @embedFile("shader/vert.spv").*;
        const vert_code = switch (dapi) {
            .vulkan => &vert_code_spv,
        };

        const frag_code_spv align(4) = @embedFile("shader/frag.spv").*;
        const frag_code = switch (dapi) {
            .vulkan => &frag_code_spv,
        };

        const sbox_vert_code_spv align(4) = @embedFile("shader/sky_box.vert.spv").*;
        const sbox_vert_code = switch (dapi) {
            .vulkan => &sbox_vert_code_spv,
        };

        const sbox_frag_code_spv align(4) = @embedFile("shader/sky_box.frag.spv").*;
        const sbox_frag_code = switch (dapi) {
            .vulkan => &sbox_frag_code_spv,
        };

        const lum_1st_code_spv align(4) = @embedFile("shader/luminance_1st.comp.spv").*;
        const lum_1st_code = switch (dapi) {
            .vulkan => &lum_1st_code_spv,
        };

        const lum_even_code_spv align(4) = @embedFile("shader/luminance_even.comp.spv").*;
        const lum_even_code = switch (dapi) {
            .vulkan => &lum_even_code_spv,
        };

        const lum_odd_code_spv align(4) = @embedFile("shader/luminance_odd.comp.spv").*;
        const lum_odd_code = switch (dapi) {
            .vulkan => &lum_odd_code_spv,
        };

        const scrn_code_spv align(4) = @embedFile("shader/screen.vert.spv").*;
        const scrn_code = switch (dapi) {
            .vulkan => &scrn_code_spv,
        };

        const final_code_spv align(4) = @embedFile("shader/final.frag.spv").*;
        const final_code = switch (dapi) {
            .vulkan => &final_code_spv,
        };

        const set_layts = &.{
            &descriptor.set_layouts[0],
            &descriptor.set_layouts[1],
            &descriptor.set_layouts[2],
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
                    .data = std.mem.asBytes(&[1]u32{light_n}),
                },
                .link = true,
            },
        });
        defer gpa.free(shaders);
        errdefer for (shaders) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const sbox_shds = try ngl.Shader.init(gpa, dev, &.{
            .{
                .type = .vertex,
                .next = .{ .fragment = true },
                .code = sbox_vert_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
            .{
                .type = .fragment,
                .next = .{},
                .code = sbox_frag_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = null,
                .link = true,
            },
        });
        defer gpa.free(sbox_shds);
        errdefer for (sbox_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const lum_shds = blk: {
            const spec_consts_1st = [2]ngl.Shader.Specialization.Constant{
                .{
                    .id = 0,
                    .offset = 0,
                    .size = @sizeOf(f32),
                },
                .{
                    .id = 1,
                    .offset = @sizeOf(f32),
                    .size = @sizeOf(f32),
                },
            };
            const spec_consts_even_odd = [2]ngl.Shader.Specialization.Constant{
                .{
                    .id = 0,
                    .offset = @sizeOf(f32) * 2,
                    .size = @sizeOf(f32),
                },
                .{
                    .id = 1,
                    .offset = @sizeOf(f32) * 3,
                    .size = @sizeOf(f32),
                },
            };
            const spec_data = [4]f32{
                1 / @as(f32, @floatFromInt(Luminance.iterations[0][0])),
                1 / @as(f32, @floatFromInt(Luminance.iterations[0][1])),
                1 / @as(f32, @floatFromInt(Luminance.iterations[1][0])),
                1 / @as(f32, @floatFromInt(Luminance.iterations[1][1])),
            };

            var shd_descs: [3]ngl.Shader.Desc = undefined;
            for (&shd_descs, 0..) |*shd_desc, i|
                shd_desc.* = .{
                    .type = .compute,
                    .next = .{},
                    .code = switch (i) {
                        0 => lum_1st_code,
                        1 => lum_even_code,
                        2 => lum_odd_code,
                        else => unreachable,
                    },
                    .name = "main",
                    .set_layouts = set_layts,
                    .push_constants = &.{},
                    .specialization = .{
                        .constants = if (i == 0) &spec_consts_1st else &spec_consts_even_odd,
                        .data = std.mem.asBytes(&spec_data),
                    },
                    .link = false,
                };

            break :blk try ngl.Shader.init(gpa, dev, &shd_descs);
        };
        defer gpa.free(lum_shds);
        errdefer for (lum_shds) |*shd|
            (shd.* catch continue).deinit(gpa, dev);

        const scrn_shd = try ngl.Shader.init(gpa, dev, &.{.{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = scrn_code,
            .name = "main",
            .set_layouts = set_layts,
            .push_constants = &.{},
            .specialization = null,
            .link = false,
        }});
        defer gpa.free(scrn_shd);
        errdefer if (scrn_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        const final_shd = blk: {
            const spec_data: packed struct {
                use_luminance_1: u32,
                gamma: f32,
                white_scale: f32,
                exposure_bias: f32,
            } = .{
                .use_luminance_1 = @intFromBool(Luminance.final_view == 1),
                .gamma = if (plat.format.format.isSrgb()) 1 else 2.2,
                .white_scale = 11.2,
                // TODO: Find a better value for this parameter.
                .exposure_bias = 2 / (1.2 * @exp2(cube_map.ev_100)),
            };

            var spec_consts: [4]ngl.Shader.Specialization.Constant = undefined;
            inline for (@typeInfo(@TypeOf(spec_data)).Struct.fields, 0..) |field, id|
                spec_consts[id] = .{
                    .id = id,
                    .offset = @offsetOf(@TypeOf(spec_data), field.name),
                    .size = @sizeOf(field.type),
                };

            break :blk try ngl.Shader.init(gpa, dev, &.{.{
                .type = .fragment,
                .next = .{},
                .code = final_code,
                .name = "main",
                .set_layouts = set_layts,
                .push_constants = &.{},
                .specialization = .{
                    .constants = &spec_consts,
                    .data = std.mem.asBytes(&spec_data),
                },
                .link = false,
            }});
        };
        defer gpa.free(final_shd);
        errdefer if (final_shd[0]) |*shd| shd.deinit(gpa, dev) else |_| {};

        var layt = try ngl.ShaderLayout.init(gpa, dev, .{
            .set_layouts = set_layts,
            .push_constants = &.{},
        });
        errdefer layt.deinit(gpa, dev);

        return .{
            .vertex = try shaders[0],
            .fragment = try shaders[1],
            .sky_box_vertex = try sbox_shds[0],
            .sky_box_fragment = try sbox_shds[1],
            .luminance_1st = try lum_shds[0],
            .luminance_even = try lum_shds[1],
            .luminance_odd = try lum_shds[2],
            .screen = try scrn_shd[0],
            .final = try final_shd[0],
            .layout = layt,
        };
    }

    fn deinit(self: *Shader, gpa: std.mem.Allocator) void {
        self.vertex.deinit(gpa, dev);
        self.fragment.deinit(gpa, dev);
        self.sky_box_vertex.deinit(gpa, dev);
        self.sky_box_fragment.deinit(gpa, dev);
        self.luminance_1st.deinit(gpa, dev);
        self.luminance_even.deinit(gpa, dev);
        self.luminance_odd.deinit(gpa, dev);
        self.screen.deinit(gpa, dev);
        self.final.deinit(gpa, dev);
        self.layout.deinit(gpa, dev);
    }
};

const Command = struct {
    queue_index: ngl.Queue.Index,
    pools: [frame_n]ngl.CommandPool,
    buffers: [frame_n]ngl.CommandBuffer,
    semaphores: [frame_n * 2]ngl.Semaphore,
    fences: [frame_n]ngl.Fence,
    multiqueue: ?struct {
        pools: [frame_n]ngl.CommandPool,
        buffers: [frame_n]ngl.CommandBuffer,
        semaphores: [frame_n]ngl.Semaphore,
        fences: [frame_n]ngl.Fence,
    },

    fn init(gpa: std.mem.Allocator) ngl.Error!Command {
        const pres = plat.queue_index;
        const rend = blk: {
            const capab = dev.queues[pres].capabilities;
            break :blk if (capab.graphics and capab.compute)
                pres
            else
                dev.findQueue(.{
                    .graphics = true,
                    .compute = true,
                }, null) orelse return ngl.Error.NotSupported;
        };

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

const Camera = struct {
    vp_v_p_pos_s: [16 + 16 + 16 + 3 + 1]f32,
    position: [3]f32,
    target: [3]f32,
    direction: [3]f32,
    stale: bool,

    const up = [3]f32{ 0, 1, 0 };
    const size = @sizeOf(@typeInfo(Camera).Struct.fields[0].type);

    fn init(position: [3]f32, target: [3]f32) Camera {
        var self: Camera = undefined;
        const p = gmath.m4f.perspective(std.math.pi / 3.0, @as(f32, width) / height, 0.01, 100);
        @memcpy(self.vp_v_p_pos_s[32..48], &p);
        const s = 50;
        self.vp_v_p_pos_s[51] = s;
        self.stale = true;
        self.position = position;
        self.target = target;
        const u = gmath.v3f.sub(target, position);
        assert(gmath.v3f.dot(u, u) > 1e-5);
        self.direction = gmath.v3f.normalize(u);
        return self;
    }

    fn turnX(self: *Camera, angle: f32) void {
        const ca = gmath.v3f.dot(self.direction, up);
        if (ca > 0.999) {
            if (angle > 0)
                return;
        } else if (ca < -0.999) {
            if (angle < 0)
                return;
        }
        const l = gmath.v3f.cross(self.direction, up);
        const r = gmath.m3f.r(gmath.qf.rotate(l, angle));
        self.direction = gmath.m3f.mul(r, self.direction);
        self.stale = true;
    }

    fn turnY(self: *Camera, angle: f32) void {
        const l = gmath.v3f.cross(self.direction, up);
        const u = gmath.v3f.cross(self.direction, l);
        const r = gmath.m3f.r(gmath.qf.rotate(u, angle));
        self.direction = gmath.m3f.mul(r, self.direction);
        self.stale = true;
    }

    fn rotateFixedX(self: *Camera, angle: f32) void {
        const un_dir = gmath.v3f.sub(self.position, self.target);
        const dir = gmath.v3f.normalize(un_dir);
        const ca = gmath.v3f.dot(dir, up);
        if (ca > 0.999) {
            if (angle > 0)
                return;
        } else if (ca < -0.999) {
            if (angle < 0)
                return;
        }
        const l = gmath.v3f.cross(dir, up);
        const r = gmath.m3f.r(gmath.qf.rotate(l, angle));
        const rev_dir = gmath.m3f.mul(r, dir);
        const dist = gmath.v3f.length(un_dir);
        self.position = gmath.v3f.add(self.target, gmath.v3f.scale(rev_dir, dist));
        self.direction = gmath.v3f.scale(rev_dir, -1);
        self.stale = true;
    }

    fn rotateFixedY(self: *Camera, angle: f32) void {
        const un_dir = gmath.v3f.sub(self.position, self.target);
        const dir = gmath.v3f.normalize(un_dir);
        const l = gmath.v3f.cross(dir, up);
        const u = gmath.v3f.cross(dir, l);
        const r = gmath.m3f.r(gmath.qf.rotate(u, angle));
        const rev_dir = gmath.m3f.mul(r, dir);
        const dist = gmath.v3f.length(un_dir);
        self.position = gmath.v3f.add(self.target, gmath.v3f.scale(rev_dir, dist));
        self.direction = gmath.v3f.scale(rev_dir, -1);
        self.stale = true;
    }

    fn copy(self: *Camera, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        if (self.stale) {
            const v = gmath.m4f.lookAt(
                self.position,
                gmath.v3f.add(self.position, self.direction),
                up,
            );
            const vp = gmath.m4f.mul(self.vp_v_p_pos_s[32..48].*, v);
            @memcpy(self.vp_v_p_pos_s[0..16], &vp);
            @memcpy(self.vp_v_p_pos_s[16..32], &v);
            @memcpy(self.vp_v_p_pos_s[48..51], &self.position);
            self.stale = false;
        }

        @memcpy(dest[0..size], std.mem.asBytes(&self.vp_v_p_pos_s));
    }
};

const Light = struct {
    lights: [light_n]Element,

    const size = light_n * @sizeOf(Element);

    const Element = packed struct {
        pos_x: f32,
        pos_y: f32,
        pos_z: f32,
        _pos_pad: f32 = 0,
        col_x: f32 = 1,
        col_y: f32 = 1,
        col_z: f32 = 1,
        intensity: f32,
    };

    const Desc = [light_n]struct {
        position: [3]f32,
        intensity: f32,
    };

    comptime {
        assert(@sizeOf(@typeInfo(Light).Struct.fields[0].type) == size);
    }

    fn init(desc: Desc) Light {
        var self: Light = undefined;
        for (&self.lights, desc) |*l, d|
            l.* = .{
                .pos_x = d.position[0],
                .pos_y = d.position[1],
                .pos_z = d.position[2],
                .intensity = d.intensity,
            };
        return self;
    }

    fn copy(self: Light, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self.lights));
    }
};

const Material = packed struct {
    col_r: f32,
    col_g: f32,
    col_b: f32,
    col_a: f32,
    metallic: f32,
    smoothness: f32,
    reflectance: f32,

    const size = @sizeOf(Material);

    fn initDielectric(color: [4]f32, smoothness: f32, reflectance: f32) Material {
        return .{
            .col_r = color[0],
            .col_g = color[1],
            .col_b = color[2],
            .col_a = color[3],
            .metallic = 0,
            .smoothness = smoothness,
            .reflectance = reflectance,
        };
    }

    fn initConductor(color: [4]f32, smoothness: f32) Material {
        return .{
            .col_r = color[0],
            .col_g = color[1],
            .col_b = color[2],
            .col_a = color[3],
            .metallic = 1,
            .smoothness = smoothness,
            .reflectance = 0,
        };
    }

    fn copy(self: Material, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};

const Model = struct {
    m_n: [16 + 12]f32,

    const size = @sizeOf(@typeInfo(Model).Struct.fields[0].type);

    fn init(m: [16]f32) Model {
        var self: Model = undefined;
        const inv = gmath.m3f.invert(gmath.m4f.upperLeft(m));
        const n = gmath.m3f.to3x4(gmath.m3f.transpose(inv), undefined);
        @memcpy(self.m_n[0..16], &m);
        @memcpy(self.m_n[16..28], &n);
        return self;
    }

    fn copy(self: Model, dest: []u8) void {
        assert(@intFromPtr(dest.ptr) & 3 == 0);
        assert(dest.len >= size);

        @memcpy(dest[0..size], std.mem.asBytes(&self));
    }
};
