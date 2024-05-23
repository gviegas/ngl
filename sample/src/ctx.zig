const std = @import("std");
const assert = std.debug.assert;

const root = @import("root");

const ngl = @import("ngl");
const pfm = ngl.pfm;

pub const Context = struct {
    gpu: ngl.Gpu,
    device: ngl.Device,
    queue_locks: [ngl.Queue.max]std.Thread.Mutex,
    platform: pfm.Platform,

    pub const Error = pfm.Platform.Error;

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) Error!Self {
        const gpus = try ngl.getGpus(allocator);
        defer allocator.free(gpus);

        // TODO: Prioritize devices that support presentation.
        var gpu_i: usize = 0;
        for (0..gpus.len) |i| {
            if (gpus[i].type == .discrete) {
                gpu_i = i;
                break;
            }
            if (gpus[i].type == .integrated)
                gpu_i = i;
        }

        var dev = try ngl.Device.init(allocator, gpus[gpu_i]);
        errdefer dev.deinit(allocator);

        const locks = blk: {
            var locks: [ngl.Queue.max]std.Thread.Mutex = undefined;
            for (0..dev.queue_n) |i|
                locks[i] = .{};
            break :blk locks;
        };

        const plat = try pfm.Platform.init(allocator, gpus[gpu_i], &dev, root.platform_desc);

        return .{
            .gpu = gpus[gpu_i],
            .device = dev,
            .queue_locks = locks,
            .platform = plat,
        };
    }

    pub fn lockQueue(self: *Self, index: ngl.Queue.Index) void {
        assert(index < self.device.queue_n);
        self.queue_locks[index].lock();
    }

    pub fn unlockQueue(self: *Self, index: ngl.Queue.Index) void {
        assert(index < self.device.queue_n);
        self.queue_locks[index].unlock();
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.platform.deinit(allocator, self.gpu, &self.device);
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
            const ca = std.heap.c_allocator;
            ctx = Context.initDefault(ca) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}
