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
        errdefer inst.deinit();
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

    pub fn deinit(self: *Self) void {
        self.device.deinit();
        self.instance.deinit();
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

test {
    const allocator = std.testing.allocator;

    var ctx = try Context.initDefault(allocator);
    defer ctx.deinit();

    var cmd_pool = try CommandPool.init(allocator, &ctx.device, .{
        .queue = &ctx.device.queues[0],
    });
    defer cmd_pool.deinit(allocator, &ctx.device);

    var cmd_bufs = try cmd_pool.alloc(allocator, &ctx.device, .{
        .level = .primary,
        .count = 3,
    });
    defer cmd_pool.free(allocator, &ctx.device, cmd_bufs);

    _ = PipelineStage.Flags{ .compute_shader = true };
    _ = Access.Flags{ .shader_storage_write = true };

    var fence = try Fence.init(allocator, &ctx.device, .{});
    defer fence.deinit(allocator, &ctx.device);

    var sema = try Semaphore.init(allocator, &ctx.device, .{});
    defer sema.deinit(allocator, &ctx.device);

    var buf = try Buffer.init(allocator, &ctx.device, .{
        .size = 1 << 20,
        .usage = .{
            .storage_texel_buffer = true,
            .transfer_source = true,
            .transfer_dest = false,
        },
    });
    defer buf.deinit(allocator, &ctx.device);

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

    var set_layout = try DescriptorSetLayout.init(allocator, &ctx.device, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .sampler,
            .count = 1,
            .immutable_samplers = &.{&splr},
        },
        .{
            .binding = 1,
            .type = .combined_image_sampler,
            .count = 2,
            .immutable_samplers = &.{ &splr, &splr },
        },
        .{
            .binding = 2,
            .type = .storage_image,
            .count = 3,
            .immutable_samplers = null,
        },
    } });
    defer set_layout.deinit(allocator, &ctx.device);

    var pl_layout = try PipelineLayout.init(allocator, &ctx.device, .{
        .descriptor_set_layouts = &.{&set_layout},
        .push_constant_ranges = &.{.{ .offset = 0, .size = 64 }},
    });
    defer pl_layout.deinit(allocator, &ctx.device);

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
}
