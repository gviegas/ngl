const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const platform = @import("test.zig").platform;

// TODO: This trashes `platform()`'s swapchain!
test "Swapchain.init/deinit" {
    const ctx = context();
    const plat = try platform();

    var fence = try ngl.Fence.init(gpa, &ctx.device, .{ .status = .unsignaled });
    defer fence.deinit(gpa, &ctx.device);
    var fence_2 = try ngl.Fence.init(gpa, &ctx.device, .{ .status = .unsignaled });
    defer fence_2.deinit(gpa, &ctx.device);
    var sem = try ngl.Semaphore.init(gpa, &ctx.device, .{});
    defer sem.deinit(gpa, &ctx.device);
    var sem_2 = try ngl.Semaphore.init(gpa, &ctx.device, .{});
    defer sem_2.deinit(gpa, &ctx.device);

    const pres_modes: ngl.Surface.PresentMode.Flags =
        plat.surface.getPresentModes(ctx.gpu) catch .{};

    const fmts = try plat.surface.getFormats(gpa, ctx.gpu);
    defer gpa.free(fmts);
    // TODO: Need to fix this somehow.
    if (fmts.len == 0) {
        std.log.warn("No exposed format for Swapchain creation!", .{});
        return error.SkipZigTest;
    }

    const capab = try plat.surface.getCapabilities(ctx.gpu, .fifo);
    const comp_alpha = inline for (@typeInfo(ngl.Surface.CompositeAlpha.Flags).Struct.fields) |f| {
        if (@field(capab.supported_composite_alpha, f.name))
            break @field(ngl.Surface.CompositeAlpha, f.name);
    } else unreachable;

    var sc = try ngl.Swapchain.init(gpa, &ctx.device, .{
        .surface = &plat.surface,
        .min_count = capab.min_count,
        .format = fmts[0].format,
        .color_space = fmts[0].color_space,
        .width = @TypeOf(plat.*).width,
        .height = @TypeOf(plat.*).height,
        .layers = 1,
        .usage = .{ .color_attachment = true },
        .pre_transform = capab.current_transform,
        .composite_alpha = comp_alpha,
        .present_mode = .fifo,
        .clipped = true,
        .old_swapchain = &plat.swapchain, // TODO
    });
    errdefer sc.deinit(gpa, &ctx.device);

    const imgs = blk: {
        var imgs = try sc.getImages(gpa, &ctx.device);
        const n = imgs.len;
        gpa.free(imgs);
        imgs = try sc.getImages(gpa, &ctx.device);
        errdefer gpa.free(imgs);
        try testing.expectEqual(imgs.len, n);
        try testing.expect(n >= capab.min_count);
        break :blk imgs;
    };
    defer gpa.free(imgs);

    if (imgs.len > capab.min_count) {
        const idx = try sc.nextImage(&ctx.device, std.time.ns_per_ms, null, &fence);
        const idx_2 = try sc.nextImage(&ctx.device, std.time.ns_per_ms, &sem, null);
        try testing.expect(idx != idx_2);
        try testing.expect(idx < imgs.len);
        try testing.expect(idx_2 < imgs.len);
    } else if (imgs.len == 1) {
        const idx = try sc.nextImage(&ctx.device, std.time.ns_per_ms, &sem, &fence);
        try testing.expectEqual(idx, 0);
    } else {
        const idx = try sc.nextImage(&ctx.device, std.time.ns_per_ms, &sem, &fence);
        try testing.expect(idx < imgs.len);
    }

    var sc_2 = try ngl.Swapchain.init(gpa, &ctx.device, .{
        .surface = &plat.surface,
        .min_count = capab.min_count + @intFromBool(capab.min_count < capab.max_count),
        .format = fmts[fmts.len - 1].format,
        .color_space = fmts[fmts.len - 1].color_space,
        .width = @TypeOf(plat.*).width,
        .height = @TypeOf(plat.*).height,
        .layers = 1,
        .usage = .{ .color_attachment = true },
        .pre_transform = capab.current_transform,
        .composite_alpha = comp_alpha,
        .present_mode = if (pres_modes.immediate)
            .immediate
        else if (pres_modes.mailbox)
            .mailbox
        else if (pres_modes.fifo_relaxed)
            .fifo_relaxed
        else
            .fifo,
        .clipped = false,
        .old_swapchain = &sc,
    });
    defer sc_2.deinit(gpa, &ctx.device);

    const imgs_2 = try sc_2.getImages(gpa, &ctx.device);
    defer gpa.free(imgs_2);
    try testing.expect(imgs_2.len >= imgs.len);

    if (imgs_2.len > capab.min_count) {
        const idx = try sc_2.nextImage(&ctx.device, std.time.ns_per_ms, &sem_2, null);
        const idx_2 = try sc_2.nextImage(&ctx.device, std.time.ns_per_ms, null, &fence_2);
        try testing.expect(idx != idx_2);
        try testing.expect(idx < imgs_2.len);
        try testing.expect(idx_2 < imgs_2.len);
    } else if (imgs_2.len == 1) {
        const idx = try sc_2.nextImage(&ctx.device, std.time.ns_per_ms, &sem_2, &fence_2);
        try testing.expectEqual(idx, 0);
    } else {
        const idx = try sc_2.nextImage(&ctx.device, std.time.ns_per_ms, &sem_2, &fence_2);
        try testing.expect(idx < imgs_2.len);
    }

    sc.deinit(gpa, &ctx.device);
}
