const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const log = @import("test.zig").log;

test "getGpus" {
    const gpus = try ngl.getGpus(gpa);
    defer gpa.free(gpus);

    // It should have returned an error if no gpus
    // were found.
    try testing.expect(gpus.len > 0);

    if (gpus.len > 1)
        for (gpus[1..]) |gpu|
            // At least `impl` should differ.
            try testing.expect(!std.meta.eql(gpus[0], gpu));

    for (gpus) |gpu| {
        try testing.expect(!std.meta.eql(gpu.queues, [_]?ngl.Queue.Desc{null} ** ngl.Queue.max));
        try testing.expect(gpu.feature_set.core);
    }

    const gpus_2 = try ngl.getGpus(gpa);
    defer gpa.free(gpus_2);

    // While adapter addition/removal is unlikely to take place
    // between the two previous calls to `getGpus`, we have to
    // assume that it might happen.
    if (gpus_2.len == gpus.len) {
        // The `impl`s are also expected to match as we provide
        // no mechanism to deinitialize `GPU`s.
        // TODO: Too fragile. Revise this.
        const seem = try gpa.alloc(bool, gpus.len);
        defer gpa.free(seem);
        for (gpus) |x|
            for (gpus_2, 0..) |y, i| {
                if (!seem[i] and std.meta.eql(x, y)) {
                    seem[i] = true;
                    break;
                }
            } else log.warn(
                "In {s}: GPUs don't match between calls",
                .{@src().fn_name},
            );
    } else log.warn(
        "In {s}: It seems that a GPU have been added or removed",
        .{@src().fn_name},
    );
}
