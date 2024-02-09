const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Semaphore.init/deinit" {
    const dev = &context().device;

    // Only vanilla (binary) semaphore is supported currently
    var sema = try ngl.Semaphore.init(gpa, dev, .{});
    sema.deinit(gpa, dev);
}
