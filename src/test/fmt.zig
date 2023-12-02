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

var formats: [@typeInfo(ngl.Format).Enum.fields.len]ngl.Format = .{
    .unknown,

    .r8_unorm,
    .r8_srgb,
    .r8_snorm,
    .r8_uint,
    .r8_sint,
    .a8_unorm,
    .r4g4_unorm,

    .r16_unorm,
    .r16_snorm,
    .r16_uint,
    .r16_sint,
    .r16_sfloat,
    .rg8_unorm,
    .rg8_srgb,
    .rg8_snorm,
    .rg8_uint,
    .rg8_sint,
    .rgba4_unorm,
    .bgra4_unorm,
    .argb4_unorm,
    .abgr4_unorm,
    .r5g6b5_unorm,
    .b5g6r5_unorm,
    .rgb5a1_unorm,
    .bgr5a1_unorm,
    .a1rgb5_unorm,
    .a1bgr5_unorm,

    .rgb8_unorm,
    .rgb8_srgb,
    .rgb8_snorm,
    .rgb8_uint,
    .rgb8_sint,
    .bgr8_unorm,
    .bgr8_srgb,
    .bgr8_snorm,
    .bgr8_uint,
    .bgr8_sint,

    .r32_uint,
    .r32_sint,
    .r32_sfloat,
    .rg16_unorm,
    .rg16_snorm,
    .rg16_uint,
    .rg16_sint,
    .rg16_sfloat,
    .rgba8_unorm,
    .rgba8_srgb,
    .rgba8_snorm,
    .rgba8_uint,
    .rgba8_sint,
    .bgra8_unorm,
    .bgra8_srgb,
    .bgra8_snorm,
    .bgra8_uint,
    .bgra8_sint,
    .rgb10a2_unorm,
    .rgb10a2_uint,
    .a2rgb10_unorm,
    .a2rgb10_uint,
    .a2bgr10_unorm,
    .a2bgr10_uint,
    .bgr10a2_unorm,
    .rg11b10_sfloat,
    .b10gr11_ufloat,
    .rgb9e5_sfloat,
    .e5bgr9_ufloat,

    .rgb16_unorm,
    .rgb16_snorm,
    .rgb16_uint,
    .rgb16_sint,
    .rgb16_sfloat,

    .r64_uint,
    .r64_sint,
    .r64_sfloat,
    .rg32_uint,
    .rg32_sint,
    .rg32_sfloat,
    .rgba16_unorm,
    .rgba16_snorm,
    .rgba16_uint,
    .rgba16_sint,
    .rgba16_sfloat,

    .rgb32_uint,
    .rgb32_sint,
    .rgb32_sfloat,

    .rg64_uint,
    .rg64_sint,
    .rg64_sfloat,
    .rgba32_uint,
    .rgba32_sint,
    .rgba32_sfloat,

    .rgb64_uint,
    .rgb64_sint,
    .rgb64_sfloat,

    .rgba64_uint,
    .rgba64_sint,
    .rgba64_sfloat,

    .d16_unorm,
    .x8_d24_unorm,
    .d32_sfloat,
    .s8_uint,
    .d16_unorm_s8_uint,
    .d24_unorm_s8_uint,
    .d32_sfloat_s8_uint,
};

test "Format.getAspectMask" {
    for (formats) |fmt| {
        const asp_mask = fmt.getAspectMask();
        switch (fmt) {
            .unknown => try testing.expect(ngl.noFlagsSet(asp_mask)),

            .r8_unorm,
            .r8_srgb,
            .r8_snorm,
            .r8_uint,
            .r8_sint,
            .a8_unorm,
            .r4g4_unorm,
            .r16_unorm,
            .r16_snorm,
            .r16_uint,
            .r16_sint,
            .r16_sfloat,
            .rg8_unorm,
            .rg8_srgb,
            .rg8_snorm,
            .rg8_uint,
            .rg8_sint,
            .rgba4_unorm,
            .bgra4_unorm,
            .argb4_unorm,
            .abgr4_unorm,
            .r5g6b5_unorm,
            .b5g6r5_unorm,
            .rgb5a1_unorm,
            .bgr5a1_unorm,
            .a1rgb5_unorm,
            .a1bgr5_unorm,
            .rgb8_unorm,
            .rgb8_srgb,
            .rgb8_snorm,
            .rgb8_uint,
            .rgb8_sint,
            .bgr8_unorm,
            .bgr8_srgb,
            .bgr8_snorm,
            .bgr8_uint,
            .bgr8_sint,
            .r32_uint,
            .r32_sint,
            .r32_sfloat,
            .rg16_unorm,
            .rg16_snorm,
            .rg16_uint,
            .rg16_sint,
            .rg16_sfloat,
            .rgba8_unorm,
            .rgba8_srgb,
            .rgba8_snorm,
            .rgba8_uint,
            .rgba8_sint,
            .bgra8_unorm,
            .bgra8_srgb,
            .bgra8_snorm,
            .bgra8_uint,
            .bgra8_sint,
            .rgb10a2_unorm,
            .rgb10a2_uint,
            .a2rgb10_unorm,
            .a2rgb10_uint,
            .a2bgr10_unorm,
            .a2bgr10_uint,
            .bgr10a2_unorm,
            .rg11b10_sfloat,
            .b10gr11_ufloat,
            .rgb9e5_sfloat,
            .e5bgr9_ufloat,
            .rgb16_unorm,
            .rgb16_snorm,
            .rgb16_uint,
            .rgb16_sint,
            .rgb16_sfloat,
            .r64_uint,
            .r64_sint,
            .r64_sfloat,
            .rg32_uint,
            .rg32_sint,
            .rg32_sfloat,
            .rgba16_unorm,
            .rgba16_snorm,
            .rgba16_uint,
            .rgba16_sint,
            .rgba16_sfloat,
            .rgb32_uint,
            .rgb32_sint,
            .rgb32_sfloat,
            .rg64_uint,
            .rg64_sint,
            .rg64_sfloat,
            .rgba32_uint,
            .rgba32_sint,
            .rgba32_sfloat,
            .rgb64_uint,
            .rgb64_sint,
            .rgb64_sfloat,
            .rgba64_uint,
            .rgba64_sint,
            .rgba64_sfloat,
            => try testing.expectEqual(asp_mask, .{ .color = true }),

            .d16_unorm,
            .x8_d24_unorm,
            .d32_sfloat,
            => try testing.expectEqual(asp_mask, .{ .depth = true }),

            .s8_uint => try testing.expectEqual(asp_mask, .{ .stencil = true }),

            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
            => try testing.expectEqual(asp_mask, .{ .depth = true, .stencil = true }),
        }
    }

    try testing.expectEqual(
        comptime ngl.Format.d16_unorm.getAspectMask(),
        formats[@intFromEnum(ngl.Format.d16_unorm)].getAspectMask(),
    );
}

test "Format.isNonFloatColor" {
    for (formats) |fmt| switch (fmt) {
        .r8_uint,
        .r8_sint,
        .r16_uint,
        .r16_sint,
        .rg8_uint,
        .rg8_sint,
        .rgb8_uint,
        .rgb8_sint,
        .bgr8_uint,
        .bgr8_sint,
        .r32_uint,
        .r32_sint,
        .rg16_uint,
        .rg16_sint,
        .rgba8_uint,
        .rgba8_sint,
        .bgra8_uint,
        .bgra8_sint,
        .rgb10a2_uint,
        .a2rgb10_uint,
        .a2bgr10_uint,
        .rgb16_uint,
        .rgb16_sint,
        .r64_uint,
        .r64_sint,
        .rg32_uint,
        .rg32_sint,
        .rgba16_uint,
        .rgba16_sint,
        .rgb32_uint,
        .rgb32_sint,
        .rg64_uint,
        .rg64_sint,
        .rgba32_uint,
        .rgba32_sint,
        .rgb64_uint,
        .rgb64_sint,
        .rgba64_uint,
        .rgba64_sint,
        => try testing.expect(fmt.isNonFloatColor()),

        .unknown,
        .r8_unorm,
        .r8_srgb,
        .r8_snorm,
        .a8_unorm,
        .r4g4_unorm,
        .r16_unorm,
        .r16_snorm,
        .r16_sfloat,
        .rg8_unorm,
        .rg8_srgb,
        .rg8_snorm,
        .rgba4_unorm,
        .bgra4_unorm,
        .argb4_unorm,
        .abgr4_unorm,
        .r5g6b5_unorm,
        .b5g6r5_unorm,
        .rgb5a1_unorm,
        .bgr5a1_unorm,
        .a1rgb5_unorm,
        .a1bgr5_unorm,
        .rgb8_unorm,
        .rgb8_srgb,
        .rgb8_snorm,
        .bgr8_unorm,
        .bgr8_srgb,
        .bgr8_snorm,
        .r32_sfloat,
        .rg16_unorm,
        .rg16_snorm,
        .rg16_sfloat,
        .rgba8_unorm,
        .rgba8_srgb,
        .rgba8_snorm,
        .bgra8_unorm,
        .bgra8_srgb,
        .bgra8_snorm,
        .rgb10a2_unorm,
        .a2rgb10_unorm,
        .a2bgr10_unorm,
        .bgr10a2_unorm,
        .rg11b10_sfloat,
        .b10gr11_ufloat,
        .rgb9e5_sfloat,
        .e5bgr9_ufloat,
        .rgb16_unorm,
        .rgb16_snorm,
        .rgb16_sfloat,
        .r64_sfloat,
        .rg32_sfloat,
        .rgba16_unorm,
        .rgba16_snorm,
        .rgba16_sfloat,
        .rgb32_sfloat,
        .rg64_sfloat,
        .rgba32_sfloat,
        .rgb64_sfloat,
        .rgba64_sfloat,
        .d16_unorm,
        .x8_d24_unorm,
        .d32_sfloat,
        .s8_uint,
        .d16_unorm_s8_uint,
        .d24_unorm_s8_uint,
        .d32_sfloat_s8_uint,
        => try testing.expect(!fmt.isNonFloatColor()),
    };

    try testing.expect(comptime ngl.Format.r16_uint.isNonFloatColor());
}

test "Format.isSrgb" {
    for (formats) |fmt| switch (fmt) {
        .r8_srgb,
        .rg8_srgb,
        .rgb8_srgb,
        .bgr8_srgb,
        .rgba8_srgb,
        .bgra8_srgb,
        => try testing.expect(fmt.isSrgb()),

        .unknown,
        .r8_unorm,
        .r8_snorm,
        .r8_uint,
        .r8_sint,
        .a8_unorm,
        .r4g4_unorm,
        .r16_unorm,
        .r16_snorm,
        .r16_uint,
        .r16_sint,
        .r16_sfloat,
        .rg8_unorm,
        .rg8_snorm,
        .rg8_uint,
        .rg8_sint,
        .rgba4_unorm,
        .bgra4_unorm,
        .argb4_unorm,
        .abgr4_unorm,
        .r5g6b5_unorm,
        .b5g6r5_unorm,
        .rgb5a1_unorm,
        .bgr5a1_unorm,
        .a1rgb5_unorm,
        .a1bgr5_unorm,
        .rgb8_unorm,
        .rgb8_snorm,
        .rgb8_uint,
        .rgb8_sint,
        .bgr8_unorm,
        .bgr8_snorm,
        .bgr8_uint,
        .bgr8_sint,
        .r32_uint,
        .r32_sint,
        .r32_sfloat,
        .rg16_unorm,
        .rg16_snorm,
        .rg16_uint,
        .rg16_sint,
        .rg16_sfloat,
        .rgba8_unorm,
        .rgba8_snorm,
        .rgba8_uint,
        .rgba8_sint,
        .bgra8_unorm,
        .bgra8_snorm,
        .bgra8_uint,
        .bgra8_sint,
        .rgb10a2_unorm,
        .rgb10a2_uint,
        .a2rgb10_unorm,
        .a2rgb10_uint,
        .a2bgr10_unorm,
        .a2bgr10_uint,
        .bgr10a2_unorm,
        .rg11b10_sfloat,
        .b10gr11_ufloat,
        .rgb9e5_sfloat,
        .e5bgr9_ufloat,
        .rgb16_unorm,
        .rgb16_snorm,
        .rgb16_uint,
        .rgb16_sint,
        .rgb16_sfloat,
        .r64_uint,
        .r64_sint,
        .r64_sfloat,
        .rg32_uint,
        .rg32_sint,
        .rg32_sfloat,
        .rgba16_unorm,
        .rgba16_snorm,
        .rgba16_uint,
        .rgba16_sint,
        .rgba16_sfloat,
        .rgb32_uint,
        .rgb32_sint,
        .rgb32_sfloat,
        .rg64_uint,
        .rg64_sint,
        .rg64_sfloat,
        .rgba32_uint,
        .rgba32_sint,
        .rgba32_sfloat,
        .rgb64_uint,
        .rgb64_sint,
        .rgb64_sfloat,
        .rgba64_uint,
        .rgba64_sint,
        .rgba64_sfloat,
        .d16_unorm,
        .x8_d24_unorm,
        .d32_sfloat,
        .s8_uint,
        .d16_unorm_s8_uint,
        .d24_unorm_s8_uint,
        .d32_sfloat_s8_uint,
        => try testing.expect(!fmt.isSrgb()),
    };

    try testing.expect(comptime ngl.Format.rgba8_srgb.isSrgb());
}
