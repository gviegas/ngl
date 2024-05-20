const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const c = @import("c");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const platform = @import("test.zig").platform;

test "Surface queries" {
    const ctx = context();
    const sf = &(try platform()).surface;

    for (ctx.gpu.queues, 0..) |queue_desc, i| {
        if (queue_desc == null) continue;
        const is_compatible = try sf.isCompatible(ctx.gpu, @as(ngl.Queue.Index, @intCast(i)));
        if (is_compatible) break;
    } else {
        // NOTE: This could happen but shouldn't.
        try testing.expect(false);
    }

    const pres_modes = try sf.getPresentModes(ctx.gpu);
    // FIFO support is mandatory.
    try testing.expect(pres_modes.fifo);

    // NOTE: Currently this may return no formats at all.
    const fmts = try sf.getFormats(gpa, ctx.gpu);
    defer gpa.free(fmts);
    for (fmts) |fmt|
        try testing.expect(fmt.format.getFeatures(&ctx.device).optimal_tiling.color_attachment);

    const capab = try sf.getCapabilities(ctx.gpu, .fifo);
    try testing.expect(capab.min_count > 0);
    // This differs from Vulkan.
    try testing.expect(capab.max_count >= capab.min_count);
    if (capab.current_width) |w| {
        if (capab.current_height) |h| {
            try testing.expect(w >= capab.min_width);
            try testing.expect(h >= capab.min_height);
            try testing.expect(w <= capab.max_width);
            try testing.expect(h <= capab.max_height);
        } else try testing.expect(false);
    } else try testing.expectEqual(capab.current_height, null);
    try testing.expect(capab.min_width <= capab.max_width);
    try testing.expect(capab.min_height <= capab.max_height);
    try testing.expect(capab.max_layers > 0);
    try testing.expect(!ngl.flag.empty(capab.supported_transforms));
    try testing.expect(!ngl.flag.empty(capab.supported_composite_alpha));
    try testing.expect(capab.supported_usage.color_attachment);
}
