const std = @import("std");

pub const Instance = @import("core/init.zig").Instance;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;
pub const Memory = @import("core/init.zig").Memory;
pub const CommandPool = @import("core/cmd.zig").CommandPool;

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

test {
    var ctx = try Context.initDefault(std.testing.allocator);
    defer ctx.deinit();

    var cmd_pool = try CommandPool.init(&ctx.device, .{ .queue = &ctx.device.queues[0] });
    defer cmd_pool.deinit(&ctx.device);
}
