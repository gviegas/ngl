const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");

pub const gpa = std.testing.allocator;
// Set `writer` to `null` to suppress test output.
pub const writer: ?std.fs.File.Writer = std.io.getStdErr().writer();
pub const log = std.log.scoped(.@"ngl|test");

test {
    _ = @import("flags.zig");
    _ = @import("gpu.zig");
    _ = @import("dev.zig");
    _ = @import("fence.zig");
    _ = @import("sem.zig");
    _ = @import("splr.zig");
    _ = @import("image.zig");
    _ = @import("buf.zig");
    _ = @import("layt.zig");
    _ = @import("desc_pool.zig");
    _ = @import("desc_set.zig");
    _ = @import("query_pool.zig");
    _ = @import("mem.zig");
    _ = @import("fmt.zig");
    _ = @import("cmd_pool.zig");
    _ = @import("cmd_buf.zig");
    // TODO: Share platform code w/ sample.
    //_ = @import("queue.zig");
    _ = @import("clear_buf.zig");
    _ = @import("copy_buf.zig");
    _ = @import("copy_buf_img.zig");
    _ = @import("lin_tiling.zig");
    _ = @import("disp.zig");
    _ = @import("disp_indir.zig");
    _ = @import("draw.zig");
    _ = @import("draw_indir.zig");
    _ = @import("depth.zig");
    _ = @import("sten.zig");
    _ = @import("blend.zig");
    _ = @import("spec.zig");
    _ = @import("occ_query.zig");
    _ = @import("tms_query.zig");
    _ = @import("exec_cmds.zig");
    _ = @import("subm_again.zig");
    _ = @import("subm_many.zig");
    // TODO: Share platform code w/ sample.
    //_ = @import("sf.zig");
    //_ = @import("sc.zig");
}

pub const Context = struct {
    gpu: ngl.Gpu,
    device: ngl.Device,
    mutexes: [ngl.Queue.max]std.Thread.Mutex,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) ngl.Error!Self {
        const gpus = try ngl.getGpus(allocator);
        defer allocator.free(gpus);
        // TODO: Improve selection.
        var idx: usize = 0;
        for (gpus, 0..) |gpu, i|
            switch (gpu.type) {
                .cpu, .other => continue,
                .integrated => idx = i,
                .discrete => {
                    idx = i;
                    break;
                },
            };
        const dev = try ngl.Device.init(allocator, gpus[idx]);
        return .{
            .gpu = gpus[idx],
            .device = dev,
            .mutexes = blk: {
                var mus: [ngl.Queue.max]std.Thread.Mutex = undefined;
                for (0..dev.queue_n) |i| mus[i] = .{};
                break :blk mus;
            },
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
