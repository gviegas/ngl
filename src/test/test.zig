const std = @import("std");
const testing = std.testing;
pub const allocator = testing.allocator;

const ngl = @import("../ngl.zig");

test {
    // TODO
    context().deinit(allocator);
}

pub fn context() *ngl.Context {
    const Static = struct {
        var ctx: ngl.Context = undefined;
        var once = std.once(init);

        fn init() void {
            ctx = ngl.Context.initDefault(allocator) catch |err| @panic(@errorName(err));
        }
    };

    Static.once.call();
    return &Static.ctx;
}
