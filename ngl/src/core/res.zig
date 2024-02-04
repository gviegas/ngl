const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Memory = ngl.Memory;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Format = enum {
    unknown,

    r8_unorm,
    r8_srgb,
    r8_snorm,
    r8_uint,
    r8_sint,
    a8_unorm,
    r4g4_unorm,

    r16_unorm,
    r16_snorm,
    r16_uint,
    r16_sint,
    r16_sfloat,
    rg8_unorm,
    rg8_srgb,
    rg8_snorm,
    rg8_uint,
    rg8_sint,
    rgba4_unorm,
    bgra4_unorm,
    argb4_unorm,
    abgr4_unorm,
    r5g6b5_unorm,
    b5g6r5_unorm,
    rgb5a1_unorm,
    bgr5a1_unorm,
    a1rgb5_unorm,
    a1bgr5_unorm,

    rgb8_unorm,
    rgb8_srgb,
    rgb8_snorm,
    rgb8_uint,
    rgb8_sint,
    bgr8_unorm,
    bgr8_srgb,
    bgr8_snorm,
    bgr8_uint,
    bgr8_sint,

    r32_uint,
    r32_sint,
    r32_sfloat,
    rg16_unorm,
    rg16_snorm,
    rg16_uint,
    rg16_sint,
    rg16_sfloat,
    rgba8_unorm,
    rgba8_srgb,
    rgba8_snorm,
    rgba8_uint,
    rgba8_sint,
    bgra8_unorm,
    bgra8_srgb,
    bgra8_snorm,
    bgra8_uint,
    bgra8_sint,
    rgb10a2_unorm,
    rgb10a2_uint,
    a2rgb10_unorm,
    a2rgb10_uint,
    a2bgr10_unorm,
    a2bgr10_uint,
    bgr10a2_unorm,
    rg11b10_sfloat,
    b10gr11_ufloat,
    rgb9e5_sfloat,
    e5bgr9_ufloat,

    rgb16_unorm,
    rgb16_snorm,
    rgb16_uint,
    rgb16_sint,
    rgb16_sfloat,

    r64_uint,
    r64_sint,
    r64_sfloat,
    rg32_uint,
    rg32_sint,
    rg32_sfloat,
    rgba16_unorm,
    rgba16_snorm,
    rgba16_uint,
    rgba16_sint,
    rgba16_sfloat,

    rgb32_uint,
    rgb32_sint,
    rgb32_sfloat,

    rg64_uint,
    rg64_sint,
    rg64_sfloat,
    rgba32_uint,
    rgba32_sint,
    rgba32_sfloat,

    rgb64_uint,
    rgb64_sint,
    rgb64_sfloat,

    rgba64_uint,
    rgba64_sint,
    rgba64_sfloat,

    d16_unorm,
    x8_d24_unorm,
    d32_sfloat,
    s8_uint,
    d16_unorm_s8_uint,
    d24_unorm_s8_uint,
    d32_sfloat_s8_uint,

    bc1_rgb_unorm,
    bc1_rgb_srgb,
    bc1_rgba_unorm,
    bc1_rgba_srgb,
    bc2_unorm,
    bc2_srgb,
    bc3_unorm,
    bc3_srgb,
    bc4_unorm,
    bc4_snorm,
    bc5_unorm,
    bc5_snorm,
    bc6h_ufloat,
    bc6h_sfloat,
    bc7_unorm,
    bc7_srgb,

    etc2_rgb8_unorm,
    etc2_rgb8_srgb,
    etc2_rgb8a1_unorm,
    etc2_rgb8a1_srgb,
    etc2_rgba8_unorm,
    etc2_rgba8_srgb,
    eac_r11_unorm,
    eac_r11_snorm,
    eac_rg11_unorm,
    eac_rg11_snorm,

    astc_4x4_unorm,
    astc_4x4_srgb,
    astc_5x4_unorm,
    astc_5x4_srgb,
    astc_5x5_unorm,
    astc_5x5_srgb,
    astc_6x5_unorm,
    astc_6x5_srgb,
    astc_6x6_unorm,
    astc_6x6_srgb,
    astc_8x5_unorm,
    astc_8x5_srgb,
    astc_8x6_unorm,
    astc_8x6_srgb,
    astc_8x8_unorm,
    astc_8x8_srgb,
    astc_10x5_unorm,
    astc_10x5_srgb,
    astc_10x6_unorm,
    astc_10x6_srgb,
    astc_10x8_unorm,
    astc_10x8_srgb,
    astc_10x10_unorm,
    astc_10x10_srgb,
    astc_12x10_unorm,
    astc_12x10_srgb,
    astc_12x12_unorm,
    astc_12x12_srgb,

    pub const Features = packed struct {
        sampled_image: bool = false,
        sampled_image_filter_linear: bool = false,
        storage_image: bool = false,
        storage_image_atomic: bool = false,
        color_attachment: bool = false,
        color_attachment_blend: bool = false,
        depth_stencil_attachment: bool = false,
        uniform_texel_buffer: bool = false,
        storage_texel_buffer: bool = false,
        storage_texel_buffer_atomic: bool = false,
        vertex_buffer: bool = false,
    };

    pub const FeatureSet = struct {
        linear_tiling: Features,
        optimal_tiling: Features,
        buffer: Features,
    };

    const Self = @This();

    pub fn getFeatures(self: Self, device: *Device) FeatureSet {
        return Impl.get().getFormatFeatures(device.impl, self);
    }

    /// Required format support.
    /// The image features pertain only to optimal tiling.
    pub const min_features = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = blk: {
            const StructField = std.builtin.Type.StructField;
            var fields: []const StructField = &[_]StructField{};
            for (@typeInfo(Self).Enum.fields) |f|
                fields = fields ++ &[_]StructField{.{
                    .name = f.name,
                    .type = Features,
                    .default_value = &Features{},
                    .is_comptime = false,
                    .alignment = @alignOf(Features),
                }};
            break :blk fields;
        },
        .decls = &.{},
        .is_tuple = false,
    } }){
        // Color 8 bpp -------------------------------------
        .r8_unorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .r8_snorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .r8_uint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .r8_sint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        // Color 16 bpp ------------------------------------
        .r16_unorm = .{ .vertex_buffer = true },
        .r16_snorm = .{ .vertex_buffer = true },
        .r16_uint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .r16_sint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .r16_sfloat = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg8_unorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg8_snorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg8_uint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg8_sint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        // Color 32 bpp ------------------------------------
        .r32_uint = .{
            .sampled_image = true,
            .storage_image = true,
            .storage_image_atomic = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .storage_texel_buffer_atomic = true,
            .vertex_buffer = true,
        },
        .r32_sint = .{
            .sampled_image = true,
            .storage_image = true,
            .storage_image_atomic = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .storage_texel_buffer_atomic = true,
            .vertex_buffer = true,
        },
        .r32_sfloat = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg16_unorm = .{ .vertex_buffer = true },
        .rg16_snorm = .{ .vertex_buffer = true },
        .rg16_uint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg16_sint = .{
            .sampled_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg16_sfloat = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba8_unorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .storage_image = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba8_snorm = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .storage_image = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba8_uint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba8_sint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        // Color 64 bpp ------------------------------------
        .rg32_uint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg32_sint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rg32_sfloat = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba16_unorm = .{ .vertex_buffer = true },
        .rgba16_snorm = .{ .vertex_buffer = true },
        .rgba16_uint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba16_sint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba16_sfloat = .{
            .sampled_image = true,
            .sampled_image_filter_linear = true,
            .storage_image = true,
            .color_attachment = true,
            .color_attachment_blend = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        // Color 96 bpp ------------------------------------
        .rgb32_uint = .{ .vertex_buffer = true },
        .rgb32_sint = .{ .vertex_buffer = true },
        .rgb32_sfloat = .{ .vertex_buffer = true },
        // Color 128 bpp -----------------------------------
        .rgba32_uint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba32_sint = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        .rgba32_sfloat = .{
            .sampled_image = true,
            .storage_image = true,
            .color_attachment = true,
            .uniform_texel_buffer = true,
            .storage_texel_buffer = true,
            .vertex_buffer = true,
        },
        // Depth/stencil -----------------------------------
        // NOTE: Which formats are allowed as stencil attachment can't be
        // known in advance - one must use `getFeatures` to query support
        // at runtime (at least one format will support it)
        .d16_unorm = .{ .sampled_image = true, .depth_stencil_attachment = true },
    };

    const Info = union(enum) {
        color: struct {
            non_float: bool = false,
            srgb: bool = false,
            r_bits: u7 = 0,
            g_bits: u7 = 0,
            b_bits: u7 = 0,
            a_bits: u7 = 0,
        },
        depth: struct { bits: u7 },
        stencil: struct { bits: u7 },
        combined: struct { depth_bits: u7, stencil_bits: u7 },
        compressed: struct { srgb: bool = false, bits: u8 },
    };

    fn getInfo(self: Self) Info {
        return switch (self) {
            .unknown => undefined,

            .r8_unorm => .{ .color = .{
                .r_bits = 8,
            } },
            .r8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
            } },
            .r8_snorm => .{ .color = .{
                .r_bits = 8,
            } },
            .r8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
            } },
            .r8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
            } },
            .a8_unorm => .{ .color = .{
                .a_bits = 8,
            } },
            .r4g4_unorm => .{ .color = .{
                .r_bits = 4,
                .g_bits = 4,
            } },

            .r16_unorm => .{ .color = .{
                .r_bits = 16,
            } },
            .r16_snorm => .{ .color = .{
                .r_bits = 16,
            } },
            .r16_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
            } },
            .r16_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
            } },
            .r16_sfloat => .{ .color = .{
                .r_bits = 16,
            } },
            .rg8_unorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
            } },
            .rg8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
                .g_bits = 8,
            } },
            .rg8_snorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
            } },
            .rg8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
            } },
            .rg8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
            } },
            .rgba4_unorm => .{ .color = .{
                .r_bits = 4,
                .g_bits = 4,
                .b_bits = 4,
                .a_bits = 4,
            } },
            .bgra4_unorm => .{ .color = .{
                .r_bits = 4,
                .g_bits = 4,
                .b_bits = 4,
                .a_bits = 4,
            } },
            .argb4_unorm => .{ .color = .{
                .r_bits = 4,
                .g_bits = 4,
                .b_bits = 4,
                .a_bits = 4,
            } },
            .abgr4_unorm => .{ .color = .{
                .r_bits = 4,
                .g_bits = 4,
                .b_bits = 4,
                .a_bits = 4,
            } },
            .r5g6b5_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 6,
                .b_bits = 5,
            } },
            .b5g6r5_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 6,
                .b_bits = 5,
            } },
            .rgb5a1_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 5,
                .b_bits = 5,
                .a_bits = 1,
            } },
            .bgr5a1_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 5,
                .b_bits = 5,
                .a_bits = 1,
            } },
            .a1rgb5_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 5,
                .b_bits = 5,
                .a_bits = 1,
            } },
            .a1bgr5_unorm => .{ .color = .{
                .r_bits = 5,
                .g_bits = 5,
                .b_bits = 5,
                .a_bits = 1,
            } },

            .rgb8_unorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .rgb8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .rgb8_snorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .rgb8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .rgb8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .bgr8_unorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .bgr8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .bgr8_snorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .bgr8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },
            .bgr8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
            } },

            .r32_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
            } },
            .r32_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
            } },
            .r32_sfloat => .{ .color = .{
                .r_bits = 32,
            } },
            .rg16_unorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
            } },
            .rg16_snorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
            } },
            .rg16_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
            } },
            .rg16_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
            } },
            .rg16_sfloat => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
            } },
            .rgba8_unorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .rgba8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .rgba8_snorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .rgba8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .rgba8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .bgra8_unorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .bgra8_srgb => .{ .color = .{
                .srgb = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .bgra8_snorm => .{ .color = .{
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .bgra8_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .bgra8_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 8,
                .g_bits = 8,
                .b_bits = 8,
                .a_bits = 8,
            } },
            .rgb10a2_unorm => .{ .color = .{
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .rgb10a2_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .a2rgb10_unorm => .{ .color = .{
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .a2rgb10_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .a2bgr10_unorm => .{ .color = .{
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .a2bgr10_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .bgr10a2_unorm => .{ .color = .{
                .r_bits = 10,
                .g_bits = 10,
                .b_bits = 10,
                .a_bits = 2,
            } },
            .rg11b10_sfloat => .{ .color = .{
                .r_bits = 11,
                .g_bits = 11,
                .b_bits = 10,
            } },
            .b10gr11_ufloat => .{ .color = .{
                .r_bits = 11,
                .g_bits = 11,
                .b_bits = 10,
            } },
            .rgb9e5_sfloat => .{ .color = .{
                .r_bits = 9,
                .g_bits = 9,
                .b_bits = 9,
            } },
            .e5bgr9_ufloat => .{ .color = .{
                .r_bits = 9,
                .g_bits = 9,
                .b_bits = 9,
            } },

            .rgb16_unorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
            } },
            .rgb16_snorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
            } },
            .rgb16_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
            } },
            .rgb16_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
            } },
            .rgb16_sfloat => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
            } },

            .r64_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
            } },
            .r64_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
            } },
            .r64_sfloat => .{ .color = .{
                .r_bits = 64,
            } },
            .rg32_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
            } },
            .rg32_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
            } },
            .rg32_sfloat => .{ .color = .{
                .r_bits = 32,
                .g_bits = 32,
            } },
            .rgba16_unorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
                .a_bits = 16,
            } },
            .rgba16_snorm => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
                .a_bits = 16,
            } },
            .rgba16_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
                .a_bits = 16,
            } },
            .rgba16_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
                .a_bits = 16,
            } },
            .rgba16_sfloat => .{ .color = .{
                .r_bits = 16,
                .g_bits = 16,
                .b_bits = 16,
                .a_bits = 16,
            } },

            .rgb32_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
            } },
            .rgb32_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
            } },
            .rgb32_sfloat => .{ .color = .{
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
            } },

            .rg64_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
            } },
            .rg64_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
            } },
            .rg64_sfloat => .{ .color = .{
                .r_bits = 64,
                .g_bits = 64,
            } },
            .rgba32_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
                .a_bits = 32,
            } },
            .rgba32_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
                .a_bits = 32,
            } },
            .rgba32_sfloat => .{ .color = .{
                .r_bits = 32,
                .g_bits = 32,
                .b_bits = 32,
                .a_bits = 32,
            } },

            .rgb64_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
            } },
            .rgb64_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
            } },
            .rgb64_sfloat => .{ .color = .{
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
            } },

            .rgba64_uint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
                .a_bits = 64,
            } },
            .rgba64_sint => .{ .color = .{
                .non_float = true,
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
                .a_bits = 64,
            } },
            .rgba64_sfloat => .{ .color = .{
                .r_bits = 64,
                .g_bits = 64,
                .b_bits = 64,
                .a_bits = 64,
            } },

            .d16_unorm => .{ .depth = .{
                .bits = 16,
            } },
            .x8_d24_unorm => .{ .depth = .{
                .bits = 24,
            } },
            .d32_sfloat => .{ .depth = .{
                .bits = 32,
            } },
            .s8_uint => .{ .stencil = .{
                .bits = 8,
            } },
            .d16_unorm_s8_uint => .{ .combined = .{
                .depth_bits = 16,
                .stencil_bits = 8,
            } },
            .d24_unorm_s8_uint => .{ .combined = .{
                .depth_bits = 24,
                .stencil_bits = 8,
            } },
            .d32_sfloat_s8_uint => .{ .combined = .{
                .depth_bits = 32,
                .stencil_bits = 8,
            } },

            .bc1_rgb_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .bc1_rgb_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 64,
            } },
            .bc1_rgba_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .bc1_rgba_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 64,
            } },
            .bc2_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .bc2_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .bc3_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .bc3_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .bc4_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .bc4_snorm => .{ .compressed = .{
                .bits = 64,
            } },
            .bc5_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .bc5_snorm => .{ .compressed = .{
                .bits = 128,
            } },
            .bc6h_ufloat => .{ .compressed = .{
                .bits = 128,
            } },
            .bc6h_sfloat => .{ .compressed = .{
                .bits = 128,
            } },
            .bc7_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .bc7_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },

            .etc2_rgb8_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .etc2_rgb8_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 64,
            } },
            .etc2_rgb8a1_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .etc2_rgb8a1_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 64,
            } },
            .etc2_rgba8_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .etc2_rgba8_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .eac_r11_unorm => .{ .compressed = .{
                .bits = 64,
            } },
            .eac_r11_snorm => .{ .compressed = .{
                .bits = 64,
            } },
            .eac_rg11_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .eac_rg11_snorm => .{ .compressed = .{
                .bits = 128,
            } },

            .astc_4x4_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_4x4_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_5x4_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_5x4_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_5x5_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_5x5_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_6x5_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_6x5_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_6x6_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_6x6_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_8x5_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_8x5_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_8x6_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_8x6_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_8x8_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_8x8_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_10x5_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_10x5_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_10x6_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_10x6_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_10x8_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_10x8_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_10x10_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_10x10_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_12x10_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_12x10_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
            .astc_12x12_unorm => .{ .compressed = .{
                .bits = 128,
            } },
            .astc_12x12_srgb => .{ .compressed = .{
                .srgb = true,
                .bits = 128,
            } },
        };
    }

    /// If `self` is `unknown`, then the returned mask will have
    /// no flags set.
    pub fn getAspectMask(self: Self) Image.Aspect.Flags {
        var mask = Image.Aspect.Flags{};
        if (self != .unknown)
            switch (self.getInfo()) {
                .color, .compressed => mask.color = true,
                .depth => mask.depth = true,
                .stencil => mask.stencil = true,
                .combined => {
                    mask.depth = true;
                    mask.stencil = true;
                },
            };
        return mask;
    }

    /// Whether it's `uint`/`sint`.
    /// For non-color formats it returns `false`.
    pub fn isNonFloatColor(self: Self) bool {
        if (self == .unknown)
            return false;
        return switch (self.getInfo()) {
            .color => |x| x.non_float,
            else => false,
        };
    }

    /// Whether it's `srgb` (implicit `unorm`).
    pub fn isSrgb(self: Self) bool {
        if (self == .unknown)
            return false;
        return switch (self.getInfo()) {
            .color => |x| x.srgb,
            .compressed => |x| x.srgb,
            else => false,
        };
    }
};

pub const Buffer = struct {
    impl: Impl.Buffer,

    pub const Usage = packed struct {
        uniform_texel_buffer: bool = false,
        storage_texel_buffer: bool = false,
        uniform_buffer: bool = false,
        storage_buffer: bool = false,
        index_buffer: bool = false,
        vertex_buffer: bool = false,
        indirect_buffer: bool = false,
        transfer_source: bool = false,
        transfer_dest: bool = false,
    };

    pub const Desc = struct {
        size: u64,
        usage: Usage,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initBuffer(allocator, device.impl, desc) };
    }

    pub fn getMemoryRequirements(self: *Self, device: *Device) Memory.Requirements {
        return Impl.get().getMemoryRequirementsBuffer(device.impl, self.impl);
    }

    pub fn bind(self: *Self, device: *Device, memory: *Memory, memory_offset: u64) Error!void {
        try Impl.get().bindBuffer(device.impl, self.impl, memory.impl, memory_offset);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitBuffer(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const BufferView = struct {
    impl: Impl.BufferView,

    pub const Desc = struct {
        buffer: *Buffer,
        format: Format,
        offset: u64,
        range: ?u64,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initBufferView(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitBufferView(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const SampleCount = enum {
    @"1",
    @"2",
    @"4",
    @"8",
    @"16",
    @"32",
    @"64",

    pub const Flags = ngl.Flags(SampleCount);
};

pub const Image = struct {
    impl: Impl.Image,

    pub const Type = enum {
        @"1d",
        @"2d",
        @"3d",
    };

    pub const Tiling = enum {
        linear,
        optimal,
    };

    pub const Usage = packed struct {
        sampled_image: bool = false,
        storage_image: bool = false,
        color_attachment: bool = false,
        depth_stencil_attachment: bool = false,
        transient_attachment: bool = false,
        input_attachment: bool = false,
        transfer_source: bool = false,
        transfer_dest: bool = false,
    };

    pub const Misc = struct {
        view_formats: ?[]const Format = null,
        cube_compatible: bool = false,
    };

    pub const Layout = enum {
        unknown,
        preinitialized,
        general,
        color_attachment_optimal,
        depth_stencil_attachment_optimal,
        depth_stencil_read_only_optimal,
        shader_read_only_optimal,
        transfer_source_optimal,
        transfer_dest_optimal,
        // `Feature.presentation`.
        present_source,
    };

    pub const Desc = struct {
        type: Type,
        format: Format,
        width: u32,
        height: u32,
        depth_or_layers: u32,
        levels: u32,
        samples: SampleCount,
        tiling: Tiling,
        usage: Usage,
        misc: Misc,
        initial_layout: Layout,
    };

    pub const Capabilities = struct {
        max_width: u32,
        max_height: u32,
        max_depth_or_layers: u32,
        max_levels: u32,
        sample_counts: SampleCount.Flags,
    };

    pub const Aspect = enum {
        color,
        depth,
        stencil,

        pub const Flags = ngl.Flags(Aspect);
    };

    pub const Range = struct {
        aspect_mask: Aspect.Flags,
        base_level: u32,
        levels: ?u32,
        base_layer: u32,
        layers: ?u32,
    };

    pub const DataLayout = struct {
        offset: u64,
        size: u64,
        /// Number of bytes between adjacent rows.
        row_pitch: u64,
        /// Number of bytes between adjacent slices.
        /// This value is undefined for images created with
        /// `Desc.depth_or_layers` equal to `1`.
        slice_pitch: u64,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initImage(allocator, device.impl, desc) };
    }

    /// It'll return `Error.NotSupported` to indicate that creating
    /// an image with the given parameters isn't possible.
    pub fn getCapabilities(
        device: *Device,
        @"type": Type,
        format: Format,
        tiling: Tiling,
        usage: Usage,
        misc: Misc,
    ) Error!Capabilities {
        return Impl.get().getImageCapabilities(device.impl, @"type", format, tiling, usage, misc);
    }

    pub fn getDataLayout(
        self: *Self,
        device: *Device,
        @"type": Type,
        aspect: Aspect,
        level: u32,
        layer: u32,
    ) DataLayout {
        return Impl.get().getImageDataLayout(device.impl, self.impl, @"type", aspect, level, layer);
    }

    pub fn getMemoryRequirements(self: *Self, device: *Device) Memory.Requirements {
        return Impl.get().getMemoryRequirementsImage(device.impl, self.impl);
    }

    pub fn bind(self: *Self, device: *Device, memory: *Memory, memory_offset: u64) Error!void {
        try Impl.get().bindImage(device.impl, self.impl, memory.impl, memory_offset);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitImage(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const ImageView = struct {
    impl: Impl.ImageView,

    pub const Type = enum {
        @"1d",
        @"2d",
        @"3d",
        cube,
        @"1d_array",
        @"2d_array",
        /// `Feature.core.image.cube_array`.
        cube_array,
    };

    pub const Desc = struct {
        image: *Image,
        type: Type,
        format: Format,
        range: Image.Range,
        // TODO: Swizzle
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initImageView(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitImageView(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const CompareOp = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const Sampler = struct {
    impl: Impl.Sampler,

    pub const AddressMode = enum {
        clamp_to_edge,
        clamp_to_border,
        repeat,
        mirror_repeat,
        /// `Feature.core.sampler.address_mode_clamp_to_edge`.
        mirror_clamp_to_edge,
    };

    pub const BorderColor = enum {
        transparent_black_float,
        transparent_black_int,
        opaque_black_float,
        opaque_black_int,
        opaque_white_float,
        opaque_white_int,
    };

    pub const Filter = enum {
        nearest,
        linear,
    };

    pub const MipmapMode = enum {
        nearest,
        linear,
    };

    pub const Desc = struct {
        normalized_coordinates: bool,
        u_address: AddressMode,
        v_address: AddressMode,
        w_address: AddressMode,
        border_color: ?BorderColor,
        mag: Filter,
        min: Filter,
        mipmap: MipmapMode,
        min_lod: f32,
        max_lod: ?f32,
        max_anisotropy: ?u5,
        compare: ?CompareOp,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSampler(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitSampler(allocator, device.impl, self.impl);
    }
};
