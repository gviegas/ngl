const std = @import("std");

pub const Instance = @import("core/init.zig").Instance;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;

pub const Error = error{
    NotReady,
    Timeout,
    InvalidArgument,
    TooManyObjects,
    Fragmentation,
    OutOfMemory,
    NotSupported,
    InitializationFailed,
    DeviceLost,
};

// TODO: Consider adding a `Context` type
pub fn initDefault(allocator: std.mem.Allocator) Error!struct { Instance, Device } {
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
    return .{ inst, try Device.init(allocator, &inst, descs[desc_i]) };
}

test {
    var ctx = try initDefault(std.testing.allocator);
    defer {
        ctx.@"1".deinit();
        ctx.@"0".deinit();
        @import("impl/Impl.zig").get().deinit();
    }
}
