const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Semaphore.init/deinit" {
    const dev = &context().device;

    // Only vanilla (binary) semaphore is supported currently.
    var sem = try ngl.Semaphore.init(gpa, dev, .{});
    sem.deinit(gpa, dev);
}
