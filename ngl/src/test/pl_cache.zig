const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "PipelineCache.init/deinit" {
    const dev = &context().device;

    var cache = try ngl.PipelineCache.init(gpa, dev, .{ .initial_data = null });
    defer cache.deinit(gpa, dev);

    // TODO: Cache management.
}
