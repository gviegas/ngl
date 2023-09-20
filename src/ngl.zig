const std = @import("std");

pub const Instance = @import("core/init.zig").Instance;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;
pub const Memory = @import("core/init.zig").Memory;
pub const CommandPool = @import("core/cmd.zig").CommandPool;
pub const CommandBuffer = @import("core/cmd.zig").CommandBuffer;
pub const PipelineStage = @import("core/sync.zig").PipelineStage;
pub const Access = @import("core/sync.zig").Access;
pub const Fence = @import("core/sync.zig").Fence;
pub const Semaphore = @import("core/sync.zig").Semaphore;
pub const Format = @import("core/res.zig").Format;
pub const Buffer = @import("core/res.zig").Buffer;
pub const BufferView = @import("core/res.zig").BufferView;
pub const SampleCount = @import("core/res.zig").SampleCount;
pub const Image = @import("core/res.zig").Image;
pub const ImageView = @import("core/res.zig").ImageView;

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
}
