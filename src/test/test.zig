const std = @import("std");
const testing = std.testing;
pub const gpa = testing.allocator;

const ngl = @import("../ngl.zig");

pub fn context() *ngl.Context {
    const Static = struct {
        var ctx: ngl.Context = undefined;
        var once = std.once(init);

        fn init() void {
            // Let it leak
            const allocator = std.heap.page_allocator;
            ctx = ngl.Context.initDefault(allocator) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}

pub var queue_locks = [_]std.Thread.Mutex{.{}} ** ngl.Queue.max;

test {
    _ = @import("inst.zig");
    _ = @import("dev.zig");
    _ = @import("fence.zig");
    _ = @import("sema.zig");
    _ = @import("splr.zig");
    _ = @import("image.zig");
    _ = @import("buf.zig");
    _ = @import("layt.zig");
    _ = @import("desc_pool.zig");
    _ = @import("desc_set.zig");
    _ = @import("rp.zig");
    _ = @import("fb.zig");
    _ = @import("pl_cache.zig");
    _ = @import("pl.zig");
    _ = @import("mem.zig");
    _ = @import("cmd_pool.zig");
    _ = @import("cmd_buf.zig");
    _ = @import("queue.zig");
    _ = @import("fill_buf.zig");
}
