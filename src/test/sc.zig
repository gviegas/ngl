const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const platform = @import("sf.zig").platform;

test "SwapChain.init/deinit" {
    const ctx = context();
    const plat = try platform();

    const fmts = try plat.surface.getFormats(gpa, &ctx.instance, ctx.device_desc);
    defer gpa.free(fmts);
    // TODO: Need to fix this somehow
    if (fmts.len == 0) {
        std.log.warn("No exposed format for SwapChain creation!", .{});
        return error.SkipZigTest;
    }

    const capab = try plat.surface.getCapabilities(&ctx.instance, ctx.device_desc, .fifo);
    const comp_alpha = inline for (@typeInfo(ngl.Surface.CompositeAlpha.Flags).Struct.fields) |f| {
        if (@field(capab.supported_composite_alpha, f.name))
            break @field(ngl.Surface.CompositeAlpha, f.name);
    } else unreachable;

    var sc = try ngl.SwapChain.init(gpa, &ctx.device, .{
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
        .old_swap_chain = null,
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

    var sc_2 = try ngl.SwapChain.init(gpa, &ctx.device, .{
        .surface = &plat.surface,
        .min_count = capab.min_count,
        .format = fmts[fmts.len - 1].format,
        .color_space = fmts[fmts.len - 1].color_space,
        .width = @TypeOf(plat.*).width,
        .height = @TypeOf(plat.*).height,
        .layers = 1,
        .usage = .{ .color_attachment = true },
        .pre_transform = capab.current_transform,
        .composite_alpha = comp_alpha,
        .present_mode = .fifo,
        .clipped = true,
        .old_swap_chain = &sc,
    });
    defer sc_2.deinit(gpa, &ctx.device);

    const imgs_2 = try sc_2.getImages(gpa, &ctx.device);
    defer gpa.free(imgs_2);
    try testing.expect(imgs_2.len == imgs.len);

    sc.deinit(gpa, &ctx.device);
}
