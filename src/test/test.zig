const std = @import("std");
const testing = std.testing;
pub const gpa = testing.allocator;

const ngl = @import("../ngl.zig");

pub const Context = struct {
    instance: ngl.Instance,
    device: ngl.Device,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) ngl.Error!Self {
        var inst = try ngl.Instance.init(allocator, .{});
        errdefer inst.deinit(allocator);
        var descs = try inst.listDevices(allocator);
        defer allocator.free(descs);
        var desc_i: usize = 0;
        for (0..descs.len) |i| {
            if (descs[i].type == .discrete_gpu) {
                desc_i = i;
                break;
            }
            if (descs[i].type == .integrated_gpu) desc_i = i;
        }
        return .{
            .instance = inst,
            .device = try ngl.Device.init(allocator, &inst, descs[desc_i]),
        };
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
            const allocator = std.heap.page_allocator;
            ctx = Context.initDefault(allocator) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}

pub var queue_locks = [_]std.Thread.Mutex{.{}} ** ngl.Queue.max;

// This can be set to `null` to suppress test output
pub const writer: ?std.fs.File.Writer = std.io.getStdErr().writer();

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
    _ = @import("fmt.zig");
    _ = @import("cmd_pool.zig");
    _ = @import("cmd_buf.zig");
    _ = @import("queue.zig");
    _ = @import("fill_buf.zig");
    _ = @import("copy_buf.zig");
    _ = @import("copy_buf_img.zig");
    _ = @import("disp.zig");
    _ = @import("draw.zig");
    _ = @import("depth.zig");
    _ = @import("sten.zig");
    _ = @import("pass_input.zig");
    _ = @import("sf.zig");
}
