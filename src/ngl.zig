const std = @import("std");

pub const Instance = @import("core/init.zig").Instance;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;
pub const Memory = @import("core/init.zig").Memory;
pub const CommandPool = @import("core/cmd.zig").CommandPool;
pub const CommandBuffer = @import("core/cmd.zig").CommandBuffer;
pub const PipelineStage = @import("core/sync.zig").PipelineStage;
pub const Access = @import("core/sync.zig").Access;
pub const SyncScope = @import("core/sync.zig").SyncScope;
pub const Fence = @import("core/sync.zig").Fence;
pub const Semaphore = @import("core/sync.zig").Semaphore;
pub const Format = @import("core/res.zig").Format;
pub const Buffer = @import("core/res.zig").Buffer;
pub const BufferView = @import("core/res.zig").BufferView;
pub const SampleCount = @import("core/res.zig").SampleCount;
pub const Image = @import("core/res.zig").Image;
pub const ImageView = @import("core/res.zig").ImageView;
pub const CompareOp = @import("core/res.zig").CompareOp;
pub const Sampler = @import("core/res.zig").Sampler;
pub const LoadOp = @import("core/pass.zig").LoadOp;
pub const StoreOp = @import("core/pass.zig").StoreOp;
pub const ResolveMode = @import("core/pass.zig").ResolveMode;
pub const RenderPass = @import("core/pass.zig").RenderPass;
pub const FrameBuffer = @import("core/pass.zig").FrameBuffer;
pub const DescriptorType = @import("core/desc.zig").DescriptorType;
pub const DescriptorSetLayout = @import("core/desc.zig").DescriptorSetLayout;
pub const PushConstantRange = @import("core/desc/zig").PushConstantRange;
pub const PipelineLayout = @import("core/desc.zig").PipelineLayout;
pub const DescriptorPool = @import("core/desc.zig").DescriptorPool;
pub const DescriptorSet = @import("core/desc.zig").DescriptorSet;
pub const Pipeline = @import("core/state.zig").Pipeline;
pub const ShaderStage = @import("core/state.zig").ShaderStage;
pub const VertexInput = @import("core/state.zig").VertexInput;
pub const Viewport = @import("core/state.zig").Viewport;
pub const Rasterization = @import("core/state.zig").Rasterization;
pub const DepthStencil = @import("core/state.zig").DepthStencil;
pub const ColorBlend = @import("core/state.zig").ColorBlend;
pub const GraphicsState = @import("core/state.zig").GraphicsState;
pub const ComputeState = @import("core/state.zig").ComputeState;
pub const PipelineCache = @import("core/state.zig").PipelineCache;

pub const Error = error{
    NotReady,
    Timeout,
    InvalidArgument,
    TooManyObjects,
    Fragmentation,
    OutOfMemory,
    NotSupported,
    NotPresent,
    InitializationFailed,
    DeviceLost,
    Other,
};

pub const Context = struct {
    instance: Instance,
    device: Device,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) Error!Self {
        var inst = try Instance.init(allocator, .{});
        errdefer inst.deinit(allocator);
        var descs = try inst.listDevices(allocator);
        defer allocator.free(descs);
        var desc_i: usize = 0;
        // TODO: Improve selection criteria
        for (0..descs.len) |i| {
            if (descs[i].type == .discrete_gpu) {
                desc_i = i;
                break;
            }
            if (descs[i].type == .integrated_gpu) desc_i = i;
        }
        return .{
            .instance = inst,
            .device = try Device.init(allocator, &inst, descs[desc_i]),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.device.deinit(allocator);
        self.instance.deinit(allocator);
        self.* = undefined;
        @import("impl/Impl.zig").get().deinit(); // XXX
    }
};

pub fn Flags(comptime E: type) type {
    const StructField = std.builtin.Type.StructField;
    var fields: []const StructField = &[_]StructField{};
    switch (@typeInfo(E)) {
        .Enum => |e| {
            for (e.fields) |f| {
                fields = fields ++ &[1]StructField{.{
                    .name = f.name,
                    .type = bool,
                    .default_value = @ptrCast(&false),
                    .is_comptime = false,
                    .alignment = 0,
                }};
            }
        },
        else => @compileError("E must be an enum type"),
    }
    return @Type(.{ .Struct = .{
        .layout = .Packed,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub inline fn noFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == 0;
}

pub inline fn allFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == ~@as(U, 0);
}

// ---------------------------------------------------------
// TODO: Do these tests elsewhere
// ---------------------------------------------------------

test {
    const allocator = std.testing.allocator;

    var ctx = try Context.initDefault(allocator);
    defer ctx.deinit(allocator);

    {
        const mem_size = 16384;
        var mem_mappable = try blk: {
            const idx: u5 = for (0..ctx.device.mem_type_n) |i| {
                if (ctx.device.mem_types[i].properties.host_visible) break @intCast(i);
            } else unreachable;
            break :blk ctx.device.alloc(allocator, .{ .size = mem_size, .mem_type_index = idx });
        };
        defer ctx.device.free(allocator, &mem_mappable);

        _ = try mem_mappable.map(&ctx.device, 0, null);

        try mem_mappable.flushMapped(
            allocator,
            &ctx.device,
            &.{ 0, 1024, 4096 },
            &.{ 512, 1024, 8192 },
        );
        try mem_mappable.flushMapped(
            allocator,
            &ctx.device,
            &.{1024},
            null,
        );
        try mem_mappable.invalidateMapped(
            allocator,
            &ctx.device,
            &.{ 4096, 0 },
            &.{ 1024, 2048 },
        );
        try mem_mappable.invalidateMapped(
            allocator,
            &ctx.device,
            &.{0},
            &.{16384},
        );

        mem_mappable.unmap(&ctx.device);
        _ = try mem_mappable.map(&ctx.device, 4096, 128);
        mem_mappable.unmap(&ctx.device);
        _ = try mem_mappable.map(&ctx.device, 256, mem_size - 256);
        // Can be freed while mapped
    }

    var cmd_pool = try CommandPool.init(allocator, &ctx.device, .{
        .queue = &ctx.device.queues[0],
    });
    defer cmd_pool.deinit(allocator, &ctx.device);

    try cmd_pool.reset(&ctx.device);

    var cmd_bufs = try cmd_pool.alloc(allocator, &ctx.device, .{
        .level = .primary,
        .count = 3,
    });
    defer allocator.free(cmd_bufs);
    cmd_pool.free(allocator, &ctx.device, &.{&cmd_bufs[2]});

    try cmd_pool.reset(&ctx.device);

    var fence = try Fence.init(allocator, &ctx.device, .{});
    defer fence.deinit(allocator, &ctx.device);
    {
        try std.testing.expectEqual(fence.getStatus(&ctx.device), .unsignaled);
        try Fence.reset(allocator, &ctx.device, &.{&fence});
        Fence.wait(allocator, &ctx.device, std.time.ns_per_ms, &.{&fence}) catch |err| {
            try std.testing.expectEqual(err, Error.Timeout);
        };
        try std.testing.expectEqual(fence.getStatus(&ctx.device), .unsignaled);

        var fence_2 = try Fence.init(allocator, &ctx.device, .{ .initial_status = .signaled });
        defer fence_2.deinit(allocator, &ctx.device);

        try std.testing.expectEqual(fence_2.getStatus(&ctx.device), .signaled);
        try Fence.wait(allocator, &ctx.device, std.time.ns_per_ms, &.{&fence_2});
        try std.testing.expectEqual(fence_2.getStatus(&ctx.device), .signaled);
        try Fence.reset(allocator, &ctx.device, &.{&fence_2});
        try std.testing.expectEqual(fence_2.getStatus(&ctx.device), .unsignaled);
    }

    var sema = try Semaphore.init(allocator, &ctx.device, .{});
    defer sema.deinit(allocator, &ctx.device);

    {
        var queue = &ctx.device.queues[0];
        try queue.submit(allocator, &ctx.device, null, &.{.{
            .commands = &.{},
            .wait = &.{},
            .signal = &.{},
        }});
    }

    var buf = try Buffer.init(allocator, &ctx.device, .{
        .size = 1 << 20,
        .usage = .{
            .storage_texel_buffer = true,
            .transfer_source = true,
            .transfer_dest = false,
        },
    });
    defer buf.deinit(allocator, &ctx.device);

    var mem_buf = try blk: {
        const mem_req = buf.getMemoryRequirements(&ctx.device);

        break :blk ctx.device.alloc(allocator, .{
            .size = mem_req.size,
            .mem_type_index = for (0..ctx.device.mem_type_n) |i| {
                if (mem_req.supportsMemoryType(@intCast(i))) break @intCast(i);
            } else unreachable,
        });
    };
    defer ctx.device.free(allocator, &mem_buf);

    try buf.bindMemory(&ctx.device, &mem_buf, 0);

    var buf_view = try BufferView.init(allocator, &ctx.device, .{
        .buffer = &buf,
        .format = .rgba8_unorm,
        .offset = 0,
        .range = null,
    });
    defer buf_view.deinit(allocator, &ctx.device);

    var image = try Image.init(allocator, &ctx.device, .{
        .type = .@"2d",
        .format = .rgba8_unorm,
        .width = 1024,
        .height = 1024,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = .@"1",
        .tiling = .optimal,
        .usage = .{
            .sampled_image = true,
            .transfer_source = false,
            .transfer_dest = true,
        },
        .misc = .{
            .view_formats = &[1]Format{.rgba8_srgb},
        },
        .initial_layout = .undefined,
    });
    defer image.deinit(allocator, &ctx.device);

    var mem_img = try blk: {
        const mem_req = image.getMemoryRequirements(&ctx.device);

        break :blk ctx.device.alloc(allocator, .{
            .size = mem_req.size,
            .mem_type_index = for (0..ctx.device.mem_type_n) |i| {
                if (mem_req.supportsMemoryType(@intCast(i))) break @intCast(i);
            } else unreachable,
        });
    };
    defer ctx.device.free(allocator, &mem_img);

    try image.bindMemory(&ctx.device, &mem_img, 0);

    var img_view = try ImageView.init(allocator, &ctx.device, .{
        .image = &image,
        .type = .@"2d",
        .format = .rgba8_srgb,
        .range = .{
            .aspect_mask = .{ .color = true },
            .base_level = 0,
            .levels = 1,
            .base_layer = 0,
            .layers = 1,
        },
    });
    defer img_view.deinit(allocator, &ctx.device);

    var splr = try Sampler.init(allocator, &ctx.device, .{
        .normalized_coordinates = true,
        .u_address = .clamp_to_edge,
        .v_address = .clamp_to_border,
        .w_address = .mirror_repeat,
        .border_color = .transparent_black_float,
        .mag = .linear,
        .min = .linear,
        .mipmap = .nearest,
        .min_lod = 0,
        .max_lod = null,
        .max_anisotropy = 16,
        .compare = null,
    });
    defer splr.deinit(allocator, &ctx.device);

    var rp = try RenderPass.init(allocator, &ctx.device, .{
        .attachments = &.{
            .{
                .format = .rgba8_srgb,
                .samples = .@"1",
                .load_op = .clear,
                .store_op = .store,
                .initial_layout = .undefined,
                .final_layout = .general,
                .resolve_mode = null,
                .combined = null,
                .may_alias = false,
            },
            //.{
            //    .format = .d24_unorm_s8_uint,
            //    .samples = .@"1",
            //    .load_op = .clear,
            //    .store_op = .dont_care,
            //    .initial_layout = .undefined,
            //    .final_layout = .undefined,
            //    .resolve_mode = null,
            //    .combined = .{
            //        .stencil_load_op = .clear,
            //        .stencil_store_op = .dont_care,
            //    },
            //    .may_alias = false,
            //},
        },
        .subpasses = &.{
            .{
                .input_attachments = null,
                .color_attachments = &.{
                    .{
                        .index = 0,
                        .layout = .color_attachment_optimal,
                        .aspect_mask = .{ .color = true },
                        .resolve = null,
                    },
                },
                //.depth_stencil_attachment = .{
                //    .index = 1,
                //    .layout = .depth_stencil_attachment_optimal,
                //    .aspect_mask = .{ .depth = true, .stencil = true },
                //    .resolve = null,
                //},
                .depth_stencil_attachment = null,
                .preserve_attachments = null,
            },
        },
        .dependencies = &.{
            .{
                .source_subpass = .external,
                .dest_subpass = .{ .index = 0 },
                .first_scope = .{
                    .stage_mask = .{ .color_attachment_output = true },
                    .access_mask = .{ .memory_read = true, .memory_write = true },
                },
                .second_scope = .{
                    .stage_mask = .{ .color_attachment_output = true },
                    .access_mask = .{ .memory_write = true },
                },
                .by_region = true,
            },
        },
    });
    defer rp.deinit(allocator, &ctx.device);

    var fb = try FrameBuffer.init(allocator, &ctx.device, .{
        .render_pass = &rp,
        .attachments = &.{&img_view},
        .width = 1024,
        .height = 1024,
        .layers = 1,
    });
    defer fb.deinit(allocator, &ctx.device);

    var set_layout = try DescriptorSetLayout.init(allocator, &ctx.device, .{ .bindings = &.{.{
        .binding = 0,
        .type = .uniform_buffer,
        .count = 1,
        .stage_mask = .{ .vertex = true },
        .immutable_samplers = null,
    }} });
    defer set_layout.deinit(allocator, &ctx.device);

    var set_layout_2 = try DescriptorSetLayout.init(allocator, &ctx.device, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .storage_image,
            .count = 1,
            .stage_mask = .{ .compute = true },
            .immutable_samplers = null,
        },
        .{
            .binding = 1,
            .type = .combined_image_sampler,
            .count = 2,
            .stage_mask = .{ .fragment = true, .vertex = true },
            .immutable_samplers = &.{ &splr, &splr },
        },
        .{
            .binding = 3,
            .type = .sampler,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = &.{&splr},
        },
        .{
            .binding = 2,
            .type = .uniform_buffer,
            .count = 3,
            .stage_mask = .{ .vertex = true },
            .immutable_samplers = null,
        },
    } });
    defer set_layout_2.deinit(allocator, &ctx.device);

    var pl_layout = try PipelineLayout.init(allocator, &ctx.device, .{
        .descriptor_set_layouts = &.{ &set_layout, &set_layout_2 },
        .push_constant_ranges = null,
    });
    defer pl_layout.deinit(allocator, &ctx.device);

    var pl_layout_2 = try PipelineLayout.init(allocator, &ctx.device, .{
        .descriptor_set_layouts = &.{&set_layout_2},
        .push_constant_ranges = &.{.{
            .offset = 0,
            .size = 64,
            .stage_mask = .{ .vertex = true, .fragment = true, .compute = true },
        }},
    });
    defer pl_layout_2.deinit(allocator, &ctx.device);

    var desc_pool = try DescriptorPool.init(allocator, &ctx.device, .{
        .max_sets = 60,
        .pool_size = .{
            .sampler = 12,
            .combined_image_sampler = 35,
            .sampled_image = 20,
            .storage_image = 1,
            .uniform_buffer = 75,
            .input_attachment = 4,
        },
    });
    defer desc_pool.deinit(allocator, &ctx.device);

    var desc_sets = try desc_pool.alloc(allocator, &ctx.device, .{ .layouts = &.{&set_layout} });
    defer desc_pool.free(allocator, &ctx.device, desc_sets);

    var pl_cache = try PipelineCache.init(allocator, &ctx.device, .{ .initial_data = null });
    defer pl_cache.deinit(allocator, &ctx.device);

    const graph = GraphicsState{
        .stages = &.{
            .{
                .stage = .vertex,
                .code = &test_vert_spv,
                .name = "main",
            },
            .{
                .stage = .fragment,
                .code = &test_frag_spv,
                .name = "main",
            },
        },
        .layout = &pl_layout,
        .vertex_input = &.{
            .bindings = &.{.{ .binding = 0, .stride = 12 + 16 }},
            .attributes = &.{
                .{
                    .location = 1,
                    .binding = 0,
                    .format = .rgba32_sfloat,
                    .offset = 12,
                },
                .{
                    .location = 0,
                    .binding = 0,
                    .format = .rgb32_sfloat,
                    .offset = 0,
                },
            },
            .topology = .triangle_list,
        },
        .viewport = &.{
            .x = 0,
            .y = 0,
            .width = 512,
            .height = 512,
            .near = 1,
            .far = 0,
        },
        .rasterization = &.{
            .polygon_mode = .fill,
            .cull_mode = .back,
            .clockwise = false,
            .samples = .@"1",
        },
        .depth_stencil = &.{
            .depth_compare = null,
            .depth_write = false,
            .stencil_front = null,
            .stencil_back = null,
        },
        .color_blend = &.{
            .attachments = &.{.{
                .color_source_factor = .source_alpha,
                .color_dest_factor = .one_minus_source_alpha,
                .color_blend_op = .add,
                .alpha_source_factor = .one,
                .alpha_dest_factor = .zero,
                .alpha_blend_op = .add,
            }},
        },
        .render_pass = &rp,
        .subpass = 0,
    };
    var graph_pl = try Pipeline.initGraphics(allocator, &ctx.device, .{
        .states = &.{graph},
        .cache = &pl_cache,
    });
    defer allocator.free(graph_pl);
    defer graph_pl[0].deinit(allocator, &ctx.device);

    const comp = ComputeState{
        .stage = .{
            .stage = .compute,
            .code = &test_comp_spv,
            .name = "main",
        },
        .layout = &pl_layout_2,
    };
    var comp_pl = try Pipeline.initCompute(allocator, &ctx.device, .{
        .states = &.{comp},
        .cache = &pl_cache,
    });
    defer allocator.free(comp_pl);
    defer comp_pl[0].deinit(allocator, &ctx.device);
}

const test_vert_spv align(4) = [1104]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x2d, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x9,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x2a, 0x0, 0x0,  0x0, 0x48, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x23, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x22, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x21, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x28, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0x28, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0x28, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0x28, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x47, 0x0,  0x3,  0x0,  0x28, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x13, 0x0, 0x2,  0x0, 0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x8,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x18, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x3,  0x0, 0xb,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0x14, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x17, 0x0,  0x0,  0x0,  0x0,  0x0,  0x80, 0x3f, 0x1e, 0x0,  0x3,  0x0,
    0x1d, 0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x1f, 0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x25, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x25, 0x0,  0x0,  0x0,
    0x26, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0x27, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x26, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x6,  0x0,  0x28, 0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x6,  0x0,  0x0,  0x0,  0x27, 0x0,  0x0,  0x0,  0x27, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0x29, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0x29, 0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0x8,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0xa,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x13, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x16, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x50, 0x0,  0x7,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x1b, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x17, 0x0,  0x0,  0x0,  0x91, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x12, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1c, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x22, 0x0, 0x0,  0x0, 0x21, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x24, 0x0, 0x0,  0x0, 0x1f, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x24, 0x0, 0x0,  0x0, 0x22, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x2c, 0x0, 0x0,  0x0, 0x2a, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x2c, 0x0, 0x0,  0x0, 0x2b, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};

const test_frag_spv align(4) = [404]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x3,  0x0,  0xa,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0, 0xb,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x2b, 0x0, 0x4,  0x0, 0xd,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0, 0xf,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x36, 0x0, 0x5,  0x0, 0x2,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0xf8, 0x0,  0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,
    0xf,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0, 0x7,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0, 0x9,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0xfd, 0x0,  0x1,  0x0,
    0x38, 0x0, 0x1,  0x0,
};

const test_comp_spv align(4) = [1272]u8{
    0x3,  0x2, 0x23, 0x7,  0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x3a, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0,  0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0,  0x5,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x10, 0x0,  0x6,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x2e, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x34, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x34, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x34, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x47, 0x0, 0x4,  0x0,  0x39, 0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x15, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xa,  0x0, 0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x2c, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x10, 0x0,  0x0,  0x0,
    0xf,  0x0, 0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0,  0x6,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x14, 0x0, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x1c, 0x0,  0x4,  0x0,  0x1f, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x80, 0x3f, 0x2c, 0x0,  0x7,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x2c, 0x0, 0x7,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x21, 0x0,  0x0,  0x0,  0x2c, 0x0,  0x5,  0x0,
    0x1f, 0x0, 0x0,  0x0,  0x24, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0,  0x26, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x15, 0x0, 0x4,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x17, 0x0, 0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x2a, 0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x4,  0x0,  0x2c, 0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x0,  0x0,
    0x3b, 0x0, 0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x19, 0x0, 0x9,  0x0,  0x32, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x33, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x32, 0x0, 0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x33, 0x0,  0x0,  0x0,  0x34, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,  0x38, 0x0,  0x0,  0x0,
    0x10, 0x0, 0x0,  0x0,  0x2c, 0x0,  0x6,  0x0,  0xa,  0x0,  0x0,  0x0,  0x39, 0x0,  0x0,  0x0,
    0x38, 0x0, 0x0,  0x0,  0x38, 0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,
    0x2,  0x0, 0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0xf8, 0x0, 0x2,  0x0,  0x5,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x1d, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x27, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x2c, 0x0,  0x0,  0x0,
    0x2d, 0x0, 0x0,  0x0,  0x7,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0,  0xc,  0x0,  0x0,  0x0,  0x4f, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0xd,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0xc7, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0,  0x10, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x12, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0,  0x14, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0,  0x15, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x17, 0x0, 0x0,  0x0,  0x9,  0x0,  0x0,  0x0,  0xf,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x18, 0x0,  0x0,  0x0,  0x17, 0x0,  0x0,  0x0,  0xc6, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x3e, 0x0, 0x3,  0x0,  0x13, 0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x6,  0x0, 0x0,  0x0,  0x25, 0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x27, 0x0, 0x0,  0x0,  0x24, 0x0,  0x0,  0x0,  0x41, 0x0,  0x5,  0x0,  0x1c, 0x0,  0x0,  0x0,
    0x28, 0x0, 0x0,  0x0,  0x27, 0x0,  0x0,  0x0,  0x25, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,
    0x1b, 0x0, 0x0,  0x0,  0x29, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,
    0x1d, 0x0, 0x0,  0x0,  0x29, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x2f, 0x0, 0x0,  0x0,  0x2e, 0x0,  0x0,  0x0,  0x4f, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x30, 0x0, 0x0,  0x0,  0x2f, 0x0,  0x0,  0x0,  0x2f, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0,  0x7c, 0x0,  0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x31, 0x0,  0x0,  0x0,
    0x30, 0x0, 0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x2d, 0x0,  0x0,  0x0,  0x31, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x32, 0x0,  0x0,  0x0,  0x35, 0x0,  0x0,  0x0,  0x34, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x2b, 0x0,  0x0,  0x0,  0x36, 0x0,  0x0,  0x0,  0x2d, 0x0,  0x0,  0x0,
    0x3d, 0x0, 0x4,  0x0,  0x1b, 0x0,  0x0,  0x0,  0x37, 0x0,  0x0,  0x0,  0x1d, 0x0,  0x0,  0x0,
    0x63, 0x0, 0x4,  0x0,  0x35, 0x0,  0x0,  0x0,  0x36, 0x0,  0x0,  0x0,  0x37, 0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};
