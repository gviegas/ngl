const std = @import("std");
const testing = std.testing;
pub const gpa = testing.allocator;

const ngl = @import("../ngl.zig");

pub fn context() *ngl.Context {
    const Static = struct {
        var ctx: ngl.Context = undefined;
        var once = std.once(init);

        fn init() void {
            ctx = ngl.Context.initDefault(gpa) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}

test {
    _ = @import("inst.zig");
    _ = @import("dev.zig");
}
