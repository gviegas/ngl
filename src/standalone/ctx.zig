const std = @import("std");

const ngl = @import("../ngl.zig");

pub const Context = struct {
    instance_desc: ngl.Instance.Desc,
    instance: ngl.Instance,
    device_desc: ngl.Device.Desc,
    device: ngl.Device,
    mutexes: [ngl.Queue.max]std.Thread.Mutex,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) ngl.Error!Self {
        var inst = try ngl.Instance.init(allocator, .{});
        errdefer inst.deinit(allocator);
        const descs = try inst.listDevices(allocator);
        defer allocator.free(descs);
        // TODO: Prioritize devices that support presentation
        var desc_i: usize = 0;
        for (0..descs.len) |i| {
            if (descs[i].type == .discrete_gpu) {
                desc_i = i;
                break;
            }
            if (descs[i].type == .integrated_gpu) desc_i = i;
        }
        const dev = try ngl.Device.init(allocator, &inst, descs[desc_i]);
        const mus = blk: {
            var mus: [ngl.Queue.max]std.Thread.Mutex = undefined;
            for (0..dev.queue_n) |i| mus[i] = .{};
            break :blk mus;
        };
        return .{
            .instance_desc = .{},
            .instance = inst,
            .device_desc = descs[desc_i],
            .device = dev,
            .mutexes = mus,
        };
    }

    pub fn lockQueue(self: *Self, index: ngl.Queue.Index) void {
        std.debug.assert(index < self.device.queue_n);
        self.mutexes[index].lock();
    }

    pub fn unlockQueue(self: *Self, index: ngl.Queue.Index) void {
        std.debug.assert(index < self.device.queue_n);
        self.mutexes[index].unlock();
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.device.deinit(allocator);
        self.instance.deinit(allocator);
        self.* = undefined;
        // TODO: Shouldn't do this here
        @import("../impl/Impl.zig").get().deinit();
    }
};

pub fn context() *Context {
    const Static = struct {
        var ctx: Context = undefined;
        var once = std.once(init);

        fn init() void {
            // Let it leak
            const allocator = std.heap.c_allocator;
            ctx = Context.initDefault(allocator) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}
