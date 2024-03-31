const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "color blending" {
    var t = try T.init();
    defer t.deinit();
    {
        try t.setColorBlend(.{
            .color_source_factor = .one,
            .color_dest_factor = .one,
            .color_op = .add,
            .alpha_source_factor = .one,
            .alpha_dest_factor = .one,
            .alpha_op = .subtract,
        });
        const source = @Vector(4, f32){ 0.35, 0.125, 0.2, 1 };
        const dest = @Vector(4, f32){ 0.25, 0.6, 0.01, 0.75 };
        try t.render(source, dest, null);
        try t.validate(@as([4]f32, source + dest)[0..3].* ++ [_]f32{(source - dest)[3]});
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .dest_alpha,
            .color_dest_factor = .source_alpha,
            .color_op = .subtract,
            .alpha_source_factor = .zero,
            .alpha_dest_factor = .one_minus_dest_alpha,
            .alpha_op = .add,
        });
        const source = @Vector(4, f32){ 1, 0.8, 0.6, 0.5 };
        const dest = @Vector(4, f32){ 0.5, 0.9, 0.2, 1 };
        try t.render(source, dest, null);
        try t.validate(
            source * @as(@Vector(4, f32), @splat(dest[3])) -
                dest * @as(@Vector(4, f32), @splat(source[3])),
            // Alpha is already zero.
        );
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .source_color,
            .color_dest_factor = .one,
            .color_op = .reverse_subtract,
            .alpha_source_factor = .source_alpha,
            .alpha_dest_factor = .dest_alpha,
            .alpha_op = .min,
        });
        const source = @Vector(4, f32){ 0.05, 0.1, 0.3333, 0.6666 };
        const dest = @Vector(4, f32){ 1, 1, 1, 1 };
        try t.render(source, dest, null);
        try t.validate(
            @as([4]f32, dest - source * source)[0..3].* ++ [_]f32{@min(source, dest)[3]},
        );
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .source_alpha,
            .color_dest_factor = .one_minus_source_alpha,
            .color_op = .add,
            .alpha_source_factor = .source_alpha,
            .alpha_dest_factor = .one_minus_source_alpha,
            .alpha_op = .add,
        });
        const source = @Vector(4, f32){ 0.2, 0.4, 0.6, 0.8 };
        const dest = @Vector(4, f32){ 0.3, 0.6, 0.9, 1 };
        try t.render(source, dest, null);
        try t.validate(
            source * @as(@Vector(4, f32), @splat(source[3])) +
                dest * @as(@Vector(4, f32), @splat(1 - source[3])),
        );
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .constant_color,
            .color_dest_factor = .constant_color,
            .color_op = .add,
            .alpha_source_factor = .constant_alpha,
            .alpha_dest_factor = .constant_alpha,
            .alpha_op = .add,
        });
        const source = @Vector(4, f32){ 0.4, 0.3, 0.2, 0.1 };
        const dest = @Vector(4, f32){ 0.6, 0.4, 0.25, 0.75 };
        const consts = @Vector(4, f32){ 0.5, 0, 1, 0.25 };
        try t.render(source, dest, consts);
        try t.validate(source * consts + dest * consts);
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .one,
            .color_dest_factor = .one_minus_constant_color,
            .color_op = .reverse_subtract,
            .alpha_source_factor = .constant_color,
            .alpha_dest_factor = .zero,
            .alpha_op = .add,
        });
        const source = @Vector(4, f32){ 0.4444, 0.3333, 0.2222, 0.1111 };
        const dest = @Vector(4, f32){ 1, 0.9, 0.8, 0 };
        const consts = @Vector(4, f32){ 0.5, 0.6, 0.7, 0.8 };
        try t.render(source, dest, consts);
        try t.validate(
            @as([4]f32, dest * (@Vector(4, f32){ 1, 1, 1, 1 } - consts) - source)[0..3].* ++
                [_]f32{source[3] * consts[3]},
        );
    }
    {
        try t.setColorBlend(.{
            .color_source_factor = .constant_color,
            .color_dest_factor = .zero,
            .color_op = .min,
            .alpha_source_factor = .one,
            .alpha_dest_factor = .constant_alpha,
            .alpha_op = .max,
        });
        const source = @Vector(4, f32){ 1, 0.8, 0.04, 0.95 };
        const dest = @Vector(4, f32){ 0.5, 0.9, 0.3, 1 };
        const consts: @Vector(4, f32) = @splat(0.1);
        try t.render(source, dest, consts);
        try t.validate(
            @as([4]f32, @min(source, dest))[0..3].* ++ [_]f32{@max(source[3], dest[3])},
        );
    }
}

const T = struct {
    queue_i: ngl.Queue.Index,
    queue: *ngl.Queue,
    cmd_pool: ngl.CommandPool,
    cmd_buf: ngl.CommandBuffer,
    fence: ngl.Fence,
    col_img: ngl.Image,
    col_mem: ngl.Memory,
    col_view: ngl.ImageView,
    vert_buf: ngl.Buffer,
    vert_mem: ngl.Memory,
    stg_buf: ngl.Buffer,
    stg_mem: ngl.Memory,
    stg_data: []u8,
    rp: ngl.RenderPass,
    fb: ngl.FrameBuffer,
    pl_layt: ngl.PipelineLayout,
    pl: ?ngl.Pipeline,
    clear_col: ?[4]f32,

    const width = 100;
    const height = 65;
    comptime {
        if (width & 1 != 0) unreachable;
    }

    const triangle = struct {
        const format = ngl.Format.rgb32_sfloat;
        const stride = 12;
        const topology = ngl.Primitive.Topology.triangle_list;
        const clockwise = false;

        const data = [3 * 3]f32{
            0, -1, 0,
            0, 2,  0,
            3, -1, 0,
        };
    };

    fn init() !@This() {
        const ctx = context();
        const dev = &ctx.device;
        const queue_i = dev.findQueue(.{ .graphics = true }, null) orelse return error.SkipZigTest;

        const queue = &dev.queues[queue_i];
        var cmd_pool = try ngl.CommandPool.init(gpa, dev, .{ .queue = queue });
        errdefer cmd_pool.deinit(gpa, dev);
        const cmd_buf = try cmd_pool.alloc(gpa, dev, .{ .level = .primary, .count = 1 });
        defer gpa.free(cmd_buf);
        var fence = try ngl.Fence.init(gpa, dev, .{});
        errdefer fence.deinit(gpa, dev);

        var col_img = try ngl.Image.init(gpa, dev, .{
            .type = .@"2d",
            .format = .rgba8_unorm,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = .@"1",
            .tiling = .optimal,
            .usage = .{ .color_attachment = true, .transfer_source = true },
            .misc = .{},
            .initial_layout = .unknown,
        });
        errdefer col_img.deinit(gpa, dev);
        var col_mem = blk: {
            const mem_reqs = col_img.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try col_img.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &col_mem);
        var col_view = try ngl.ImageView.init(gpa, dev, .{
            .image = &col_img,
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
        errdefer col_view.deinit(gpa, dev);

        var vert_buf = try ngl.Buffer.init(gpa, dev, .{
            .size = @sizeOf(@TypeOf(triangle.data)),
            .usage = .{ .vertex_buffer = true, .transfer_dest = true },
        });
        errdefer vert_buf.deinit(gpa, dev);
        var vert_mem = blk: {
            const mem_reqs = vert_buf.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{ .device_local = true }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try vert_buf.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &vert_mem);

        const stg_size = @max(width * height * 4, @sizeOf(@TypeOf(triangle.data)));
        var stg_buf = try ngl.Buffer.init(gpa, dev, .{
            .size = stg_size,
            .usage = .{ .transfer_source = true, .transfer_dest = true },
        });
        errdefer stg_buf.deinit(gpa, dev);
        var stg_mem = blk: {
            const mem_reqs = stg_buf.getMemoryRequirements(dev);
            var mem = try dev.alloc(gpa, .{
                .size = mem_reqs.size,
                .type_index = mem_reqs.findType(dev.*, .{
                    .host_visible = true,
                    .host_coherent = true,
                }, null).?,
            });
            errdefer dev.free(gpa, &mem);
            try stg_buf.bind(dev, &mem, 0);
            break :blk mem;
        };
        errdefer dev.free(gpa, &stg_mem);
        const stg_data = (try stg_mem.map(dev, 0, stg_size))[0..stg_size];

        var rp = try ngl.RenderPass.init(gpa, dev, .{
            .attachments = &.{.{
                .format = .rgba8_unorm,
                .samples = .@"1",
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .unknown,
                .final_layout = .transfer_source_optimal,
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
            .dependencies = null,
        });
        errdefer rp.deinit(gpa, dev);

        var fb = try ngl.FrameBuffer.init(gpa, dev, .{
            .render_pass = &rp,
            .attachments = &.{&col_view},
            .width = width,
            .height = height,
            .layers = 1,
        });
        errdefer fb.deinit(gpa, dev);

        var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = null,
            .push_constant_ranges = &.{.{
                .offset = 0,
                .size = 16,
                .stage_mask = .{ .fragment = true },
            }},
        });
        errdefer pl_layt.deinit(gpa, dev);

        // Vertices won't change so copy them upfront.
        @memcpy(
            stg_data[0..@sizeOf(@TypeOf(triangle.data))],
            @as([*]const u8, @ptrCast(&triangle.data))[0..@sizeOf(@TypeOf(triangle.data))],
        );
        var cmd = try cmd_buf[0].begin(gpa, dev, .{ .one_time_submit = true, .inheritance = null });
        cmd.copyBuffer(&.{.{
            .source = &stg_buf,
            .dest = &vert_buf,
            .regions = &.{.{
                .source_offset = 0,
                .dest_offset = 0,
                .size = @sizeOf(@TypeOf(triangle.data)),
            }},
        }});
        try cmd.end();
        {
            ctx.lockQueue(queue_i);
            defer ctx.unlockQueue(queue_i);
            try queue.submit(gpa, dev, &fence, &.{.{
                .commands = &.{.{ .command_buffer = &cmd_buf[0] }},
                .wait = &.{},
                .signal = &.{},
            }});
        }
        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&fence});

        return .{
            .queue = queue,
            .queue_i = queue_i,
            .cmd_pool = cmd_pool,
            .cmd_buf = cmd_buf[0],
            .fence = fence,
            .col_img = col_img,
            .col_mem = col_mem,
            .col_view = col_view,
            .vert_buf = vert_buf,
            .vert_mem = vert_mem,
            .stg_buf = stg_buf,
            .stg_mem = stg_mem,
            .stg_data = stg_data,
            .rp = rp,
            .fb = fb,
            .pl_layt = pl_layt,
            .pl = null,
            .clear_col = null,
        };
    }

    // This will create/recreate the pipeline.
    fn setColorBlend(self: *@This(), blend_equation: ngl.ColorBlend.BlendEquation) !void {
        const dev = &context().device;

        if (self.pl) |*pl| {
            pl.deinit(gpa, dev);
            self.pl = null;
            self.clear_col = null;
        }

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
                .layout = &self.pl_layt,
                .primitive = &.{
                    .bindings = &.{.{
                        .binding = 0,
                        .stride = triangle.stride,
                        .step_rate = .vertex,
                    }},
                    .attributes = &.{.{
                        .location = 0,
                        .binding = 0,
                        .format = triangle.format,
                        .offset = 0,
                    }},
                    .topology = triangle.topology,
                },
                .rasterization = &.{
                    .polygon_mode = .fill,
                    .cull_mode = .back,
                    .clockwise = triangle.clockwise,
                    .samples = .@"1",
                },
                .depth_stencil = null,
                .color_blend = &.{
                    .attachments = &.{.{ .blend = blend_equation, .write = .all }},
                },
                .render_pass = &self.rp,
                .subpass = 0,
            }},
            .cache = null,
        });
        defer gpa.free(pl);

        self.pl = pl[0];
    }

    fn render(self: *@This(), source_color: [4]f32, dest_color: [4]f32, constants: ?[4]f32) !void {
        const ctx = context();
        const dev = &ctx.device;

        try self.cmd_pool.reset(dev, .keep);
        var cmd = try self.cmd_buf.begin(gpa, dev, .{
            .one_time_submit = true,
            .inheritance = null,
        });
        cmd.beginRenderPass(
            .{
                .render_pass = &self.rp,
                .frame_buffer = &self.fb,
                .render_area = .{
                    .x = 0,
                    .y = 0,
                    .width = width,
                    .height = height,
                },
                .clear_values = &.{.{ .color_f32 = dest_color }},
            },
            .{ .contents = .inline_only },
        );
        cmd.setPipeline(&self.pl.?);
        cmd.setPushConstants(
            &self.pl_layt,
            .{ .fragment = true },
            0,
            @as([*]align(4) const u8, @ptrCast(&source_color))[0..16],
        );
        cmd.setVertexBuffers(0, &.{&self.vert_buf}, &.{0}, &.{@sizeOf(@TypeOf(triangle.data))});
        cmd.setViewports(&.{.{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
            .znear = 0,
            .zfar = 0,
        }});
        cmd.setScissorRects(&.{.{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        }});
        if (constants) |x|
            cmd.setBlendConstants(x);
        cmd.draw(3, 1, 0, 0);
        cmd.endRenderPass(.{});
        cmd.pipelineBarrier(&.{.{
            .global_dependencies = &.{.{
                .source_stage_mask = .{ .color_attachment_output = true },
                .source_access_mask = .{ .color_attachment_write = true },
                .dest_stage_mask = .{ .copy = true },
                .dest_access_mask = .{ .transfer_read = true, .transfer_write = true },
            }},
            .by_region = false,
        }});
        cmd.copyImageToBuffer(&.{.{
            .buffer = &self.stg_buf,
            .image = &self.col_img,
            .image_layout = .transfer_source_optimal,
            .image_type = .@"2d",
            .regions = &.{.{
                .buffer_offset = 0,
                .buffer_row_length = width,
                .buffer_image_height = height,
                .image_aspect = .color,
                .image_level = 0,
                .image_x = 0,
                .image_y = 0,
                .image_z_or_layer = 0,
                .image_width = width,
                .image_height = height,
                .image_depth_or_layers = 1,
            }},
        }});
        try cmd.end();

        try ngl.Fence.reset(gpa, dev, &.{&self.fence});
        {
            ctx.lockQueue(self.queue_i);
            defer ctx.unlockQueue(self.queue_i);

            try self.queue.submit(gpa, dev, &self.fence, &.{.{
                .commands = &.{.{ .command_buffer = &self.cmd_buf }},
                .wait = &.{},
                .signal = &.{},
            }});
        }
        try ngl.Fence.wait(gpa, dev, std.time.ns_per_s, &.{&self.fence});

        self.clear_col = dest_color;
    }

    fn validate(self: @This(), final_color: [4]f32) !void {
        const clear_col = @Vector(4, u8){
            @intFromFloat(@round(255 * self.clear_col.?[0])),
            @intFromFloat(@round(255 * self.clear_col.?[1])),
            @intFromFloat(@round(255 * self.clear_col.?[2])),
            @intFromFloat(@round(255 * self.clear_col.?[3])),
        };
        const final_col = @Vector(4, u8){
            @intFromFloat(@round(255 * final_color[0])),
            @intFromFloat(@round(255 * final_color[1])),
            @intFromFloat(@round(255 * final_color[2])),
            @intFromFloat(@round(255 * final_color[3])),
        };
        const deviation = @Vector(4, u8){ 1, 1, 1, 1 };

        for (0..height) |y| {
            for (0..width / 2) |x| {
                const i = (y * width + x) * 4;
                const j = i + width / 2 * 4;
                const col: @Vector(4, u8) = self.stg_data[i..][0..4].*;
                const col_2: @Vector(4, u8) = self.stg_data[j..][0..4].*;

                try testing.expect(@reduce(.And, col <= clear_col +| deviation) and
                    @reduce(.And, col >= clear_col -| deviation));

                try testing.expect(@reduce(.And, col_2 <= final_col +| deviation) and
                    @reduce(.And, col_2 >= final_col -| deviation));
            }
        }
    }

    fn deinit(self: *@This()) void {
        const dev = &context().device;
        if (self.pl) |*pl| pl.deinit(gpa, dev);
        self.pl_layt.deinit(gpa, dev);
        self.fb.deinit(gpa, dev);
        self.rp.deinit(gpa, dev);
        dev.free(gpa, &self.stg_mem);
        self.stg_buf.deinit(gpa, dev);
        dev.free(gpa, &self.vert_mem);
        self.vert_buf.deinit(gpa, dev);
        self.col_view.deinit(gpa, dev);
        dev.free(gpa, &self.col_mem);
        self.col_img.deinit(gpa, dev);
        self.fence.deinit(gpa, dev);
        self.cmd_pool.deinit(gpa, dev);
    }
};

// #version 460 core
//
// layout(location = 0) in vec3 position;
//
// void main() {
//     gl_Position = vec4(position, 1.0);
// }
const vert_spv align(4) = [636]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x3,  0x0, 0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xc,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xe,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xe,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x10, 0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0x6,  0x0,  0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f,
    0x20, 0x0, 0x4,  0x0, 0x19, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x13, 0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0x19, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x18, 0x0, 0x0,  0x0, 0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(push_constant) uniform Pc {
//     vec4 color;
// } pc;
//
// layout(location = 0) out vec4 color_0;
//
// void main() {
//     color_0 = pc.color;
// }
const frag_spv align(4) = [404]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x6,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xa,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x23, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x3,  0x0,  0xa,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x9,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};
