const std = @import("std");
const assert = std.debug.assert;

const root = @import("root");

const ngl = @import("ngl");
const pfm = ngl.pfm;

gpu: ngl.Gpu,
device: ngl.Device,
queue_locks: [ngl.Queue.max]std.Thread.Mutex,
platform: pfm.Platform,

pub const Error = pfm.Platform.Error;

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Error!Self {
    const gpus = try ngl.getGpus(allocator);
    defer allocator.free(gpus);

    const gpu_i: usize = blk: {
        var gpu_i: ?usize = null;
        for (0..gpus.len) |i| {
            if (!gpus[i].feature_set.presentation)
                continue;

            for (gpus[i].queues) |q| {
                const has_graph = (q orelse continue).capabilities.graphics;
                if (has_graph)
                    break;
            } else continue;

            if (gpus[i].type == .discrete) {
                gpu_i = i;
                break;
            }

            if (gpus[i].type == .integrated or gpu_i == null)
                gpu_i = i;
        }
        break :blk gpu_i orelse return Error.NotSupported;
    };

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
    self.platform.deinit(allocator, &self.device);
    self.device.deinit(allocator);
    self.* = undefined;
}
