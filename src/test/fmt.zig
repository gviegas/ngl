const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const context = @import("test.zig").context;

test "Format.getFeatures" {
    const dev = &context().device;

    var feat_set: ngl.Format.FeatureSet = undefined;

    // This is allowed and should produce an empty set
    feat_set = ngl.Format.unknown.getFeatures(dev);
    try testing.expectEqual(feat_set, .{
        .linear_tiling = .{},
        .optimal_tiling = .{},
        .buffer = .{},
    });

    // XXX: This relies on how the Format enum is defined
    const fmts_col = blk: {
        const first = @intFromEnum(ngl.Format.r8_unorm);
        const last = @intFromEnum(ngl.Format.rgba64_sfloat);
        var fmts: [last - first + 1]ngl.Format = undefined;
        inline for (@typeInfo(ngl.Format).Enum.fields[first .. last + 1], 0..) |field, i|
            fmts[i] = @field(ngl.Format, field.name);
        break :blk fmts;
    };
    for (fmts_col) |fmt| {
        feat_set = fmt.getFeatures(dev);
        for ([2]ngl.Format.Features{ feat_set.linear_tiling, feat_set.optimal_tiling }) |feats|
            // Color formats aren't allowed as depth/stencil attachments
            try testing.expect(!feats.depth_stencil_attachment);
    }

    // XXX: This relies on how the Format enum is defined
    const fmts_ds = blk: {
        const first = @intFromEnum(ngl.Format.d16_unorm);
        const last = @intFromEnum(ngl.Format.d32_sfloat_s8_uint);
        var fmts: [last - first + 1]ngl.Format = undefined;
        inline for (@typeInfo(ngl.Format).Enum.fields[first .. last + 1], 0..) |field, i|
            fmts[i] = @field(ngl.Format, field.name);
        break :blk fmts;
    };
    for (fmts_ds) |fmt| {
        feat_set = fmt.getFeatures(dev);
        for ([2]ngl.Format.Features{ feat_set.linear_tiling, feat_set.optimal_tiling }) |feats|
            // Depth/stencil formats aren't allowed as color attachments
            try testing.expect(!feats.color_attachment and !feats.color_attachment_blend);
        // TODO: Consider disallowing more features since depth/stencil
        // formats have no layout guarantees
    }

    if (@typeInfo(ngl.Format).Enum.fields.len - 1 != fmts_col.len + fmts_ds.len)
        @compileError("Update test when changing Format enum");

    const U = @typeInfo(ngl.Format.Features).Struct.backing_integer.?;
    const feats_img: U = @bitCast(ngl.Format.Features{
        .sampled_image = true,
        .sampled_image_filter_linear = true,
        .storage_image = true,
        .storage_image_atomic = true,
        .color_attachment = true,
        .color_attachment_blend = true,
        .depth_stencil_attachment = true,
    });
    const feats_buf: U = @bitCast(ngl.Format.Features{
        .uniform_texel_buffer = true,
        .storage_texel_buffer = true,
        .storage_texel_buffer_atomic = true,
        .vertex_buffer = true,
    });
    inline for (@typeInfo(ngl.Format).Enum.fields) |field| {
        feat_set = @field(ngl.Format, field.name).getFeatures(dev);
        // Shouldn't mix image and buffer features
        try testing.expect(@as(U, @bitCast(feat_set.linear_tiling)) & feats_buf == 0);
        try testing.expect(@as(U, @bitCast(feat_set.optimal_tiling)) & feats_buf == 0);
        try testing.expect(@as(U, @bitCast(feat_set.buffer)) & feats_img == 0);
    }
}

test "required format support" {
    const dev = &context().device;

    var ok = true;

    inline for (@typeInfo(ngl.Format).Enum.fields) |field| {
        const U = @typeInfo(ngl.Format.Features).Struct.backing_integer.?;

        const feat_set = @field(ngl.Format, field.name).getFeatures(dev);
        const opt: U = @bitCast(feat_set.optimal_tiling);
        const buf: U = @bitCast(feat_set.buffer);
        const feats = opt | buf;

        const min: U = @bitCast(@field(ngl.Format.min_features, field.name));

        testing.expect(feats & min == min) catch {
            std.debug.print(
                "[!] Format.{s} doesn't support the minimum required features\n",
                .{field.name},
            );
            ok = false;
        };
    }

    for ([_]ngl.Format{
        //.s8_uint, // Must be a combined depth/stencil format
        .d16_unorm_s8_uint,
        .d24_unorm_s8_uint,
        .d32_sfloat_s8_uint,
    }) |fmt| {
        if (fmt.getFeatures(dev).optimal_tiling.depth_stencil_attachment)
            break;
    } else {
        std.debug.print("[!] No valid stencil format found\n", .{});
        ok = false;
    }

    try testing.expect(ok);
}
