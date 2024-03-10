const std = @import("std");

const ngl = @import("ngl");

pub const Context = struct {
    gpu: ngl.Gpu,
    device: ngl.Device,
    mutexes: [ngl.Queue.max]std.Thread.Mutex,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) ngl.Error!Self {
        const gpus = try ngl.getGpus(allocator);
        defer allocator.free(gpus);
        // TODO: Prioritize devices that support presentation.
        var gpu_i: usize = 0;
        for (0..gpus.len) |i| {
            if (gpus[i].type == .discrete) {
                gpu_i = i;
                break;
            }
            if (gpus[i].type == .integrated) gpu_i = i;
        }
        const dev = try ngl.Device.init(allocator, gpus[gpu_i]);
        const mus = blk: {
            var mus: [ngl.Queue.max]std.Thread.Mutex = undefined;
            for (0..dev.queue_n) |i| mus[i] = .{};
            break :blk mus;
        };
        return .{
            .gpu = gpus[gpu_i],
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
        self.* = undefined;
    }
};

pub fn context() *Context {
    const Static = struct {
        var ctx: Context = undefined;
        var once = std.once(init);

        fn init() void {
            // Let it leak.
            const allocator = std.heap.c_allocator;
            ctx = Context.initDefault(allocator) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}
