const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const c = @import("../c.zig");

/// Anything other than `VK_SUCCESS` produces an `Error`.
pub fn check(result: c.VkResult) Error!void {
    return switch (result) {
        c.VK_SUCCESS => {},

        c.VK_NOT_READY => Error.NotReady,

        c.VK_TIMEOUT => Error.Timeout,

        c.VK_ERROR_OUT_OF_HOST_MEMORY,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY,
        => Error.OutOfMemory,

        c.VK_ERROR_INITIALIZATION_FAILED => Error.InitializationFailed,

        c.VK_ERROR_DEVICE_LOST => Error.DeviceLost,

        c.VK_ERROR_TOO_MANY_OBJECTS => Error.TooManyObjects,

        c.VK_ERROR_FORMAT_NOT_SUPPORTED => Error.NotSupported,

        c.VK_ERROR_LAYER_NOT_PRESENT,
        c.VK_ERROR_EXTENSION_NOT_PRESENT,
        c.VK_ERROR_FEATURE_NOT_PRESENT,
        => Error.NotPresent,

        else => Error.Other,
    };
}

/// `Error.NotSupported` indicates that the format doesn't have an exactly
/// match in Vulkan.
pub fn toVkFormat(format: ngl.Format) Error!c.VkFormat {
    return switch (format) {
        .undefined => c.VK_FORMAT_UNDEFINED,

        .r8_unorm => c.VK_FORMAT_R8_UNORM,
        .r8_srgb => c.VK_FORMAT_R8_SRGB,
        .r8_snorm => c.VK_FORMAT_R8_SNORM,
        .r8_uint => c.VK_FORMAT_R8_UINT,
        .r8_sint => c.VK_FORMAT_R8_SINT,
        .a8_unorm => 1000470001, // c.VK_FORMAT_A8_UNORM_KHR,
        .r4g4_unorm => c.VK_FORMAT_R4G4_UNORM_PACK8,

        .r16_unorm => c.VK_FORMAT_R16_UNORM,
        .r16_snorm => c.VK_FORMAT_R16_SNORM,
        .r16_uint => c.VK_FORMAT_R16_UINT,
        .r16_sint => c.VK_FORMAT_R16_SINT,
        .r16_sfloat => c.VK_FORMAT_R16_SFLOAT,
        .rg8_unorm => c.VK_FORMAT_R8G8_UNORM,
        .rg8_srgb => c.VK_FORMAT_R8G8_SRGB,
        .rg8_snorm => c.VK_FORMAT_R8G8_SNORM,
        .rg8_uint => c.VK_FORMAT_R8G8_UINT,
        .rg8_sint => c.VK_FORMAT_R8G8_SINT,
        .rgba4_unorm => c.VK_FORMAT_R4G4B4A4_UNORM_PACK16,
        .bgra4_unorm => c.VK_FORMAT_B4G4R4A4_UNORM_PACK16,
        .argb4_unorm => c.VK_FORMAT_A4R4G4B4_UNORM_PACK16,
        .abgr4_unorm => c.VK_FORMAT_A4B4G4R4_UNORM_PACK16,
        .r5g6b5_unorm => c.VK_FORMAT_R5G6B5_UNORM_PACK16,
        .b5g6r5_unorm => c.VK_FORMAT_B5G6R5_UNORM_PACK16,
        .rgb5a1_unorm => c.VK_FORMAT_R5G5B5A1_UNORM_PACK16,
        .bgr5a1_unorm => c.VK_FORMAT_B5G5R5A1_UNORM_PACK16,
        .a1rgb5_unorm => c.VK_FORMAT_A1R5G5B5_UNORM_PACK16,
        .a1bgr5_unorm => 1000470000, // c.VK_FORMAT_A1B5G5R5_UNORM_PACK16_KHR,

        .rgb8_unorm => c.VK_FORMAT_R8G8B8_UNORM,
        .rgb8_srgb => c.VK_FORMAT_R8G8B8_SRGB,
        .rgb8_snorm => c.VK_FORMAT_R8G8B8_SNORM,
        .rgb8_uint => c.VK_FORMAT_R8G8B8_UINT,
        .rgb8_sint => c.VK_FORMAT_R8G8B8_SINT,
        .bgr8_unorm => c.VK_FORMAT_B8G8R8_UNORM,
        .bgr8_srgb => c.VK_FORMAT_B8G8R8_SRGB,
        .bgr8_snorm => c.VK_FORMAT_B8G8R8_SNORM,
        .bgr8_uint => c.VK_FORMAT_B8G8R8_UINT,
        .bgr8_sint => c.VK_FORMAT_B8G8R8_SINT,

        .r32_uint => c.VK_FORMAT_R32_UINT,
        .r32_sint => c.VK_FORMAT_R32_SINT,
        .r32_sfloat => c.VK_FORMAT_R32_SFLOAT,
        .rg16_unorm => c.VK_FORMAT_R16G16_UNORM,
        .rg16_snorm => c.VK_FORMAT_R16G16_SNORM,
        .rg16_uint => c.VK_FORMAT_R16G16_UINT,
        .rg16_sint => c.VK_FORMAT_R16G16_SINT,
        .rg16_sfloat => c.VK_FORMAT_R16G16_SFLOAT,
        .rgba8_unorm => c.VK_FORMAT_R8G8B8A8_UNORM,
        .rgba8_srgb => c.VK_FORMAT_R8G8B8A8_SRGB,
        .rgba8_snorm => c.VK_FORMAT_R8G8B8A8_SNORM,
        .rgba8_uint => c.VK_FORMAT_R8G8B8A8_UINT,
        .rgba8_sint => c.VK_FORMAT_R8G8B8A8_SINT,
        .bgra8_unorm => c.VK_FORMAT_B8G8R8A8_UNORM,
        .bgra8_srgb => c.VK_FORMAT_B8G8R8A8_SRGB,
        .bgra8_snorm => c.VK_FORMAT_B8G8R8A8_SNORM,
        .bgra8_uint => c.VK_FORMAT_B8G8R8A8_UINT,
        .bgra8_sint => c.VK_FORMAT_B8G8R8A8_SINT,
        .rgb10a2_unorm => Error.NotSupported, // XXX
        .rgb10a2_uint => Error.NotSupported, // XXX
        .a2rgb10_unorm => c.VK_FORMAT_A2R10G10B10_UNORM_PACK32,
        .a2rgb10_uint => c.VK_FORMAT_A2R10G10B10_UINT_PACK32,
        .a2bgr10_unorm => c.VK_FORMAT_A2B10G10R10_UNORM_PACK32,
        .a2bgr10_uint => c.VK_FORMAT_A2B10G10R10_UINT_PACK32,
        .bgr10a2_unorm => Error.NotSupported, // XXX
        .rg11b10_sfloat => Error.NotSupported, // XXX
        .b10gr11_ufloat => c.VK_FORMAT_B10G11R11_UFLOAT_PACK32,
        .rgb9e5_sfloat => Error.NotSupported, // XXX
        .e5bgr9_ufloat => c.VK_FORMAT_E5B9G9R9_UFLOAT_PACK32,

        .rgb16_unorm => c.VK_FORMAT_R16G16B16_UNORM,
        .rgb16_snorm => c.VK_FORMAT_R16G16B16_SNORM,
        .rgb16_uint => c.VK_FORMAT_R16G16B16_UINT,
        .rgb16_sint => c.VK_FORMAT_R16G16B16_SINT,
        .rgb16_sfloat => c.VK_FORMAT_R16G16B16_SFLOAT,

        .r64_uint => c.VK_FORMAT_R64_UINT,
        .r64_sint => c.VK_FORMAT_R64_SINT,
        .r64_sfloat => c.VK_FORMAT_R64_SFLOAT,
        .rg32_uint => c.VK_FORMAT_R32G32_UINT,
        .rg32_sint => c.VK_FORMAT_R32G32_SINT,
        .rg32_sfloat => c.VK_FORMAT_R32G32_SFLOAT,
        .rgba16_unorm => c.VK_FORMAT_R16G16B16A16_UNORM,
        .rgba16_snorm => c.VK_FORMAT_R16G16B16A16_SNORM,
        .rgba16_uint => c.VK_FORMAT_R16G16B16A16_UINT,
        .rgba16_sint => c.VK_FORMAT_R16G16B16A16_SINT,
        .rgba16_sfloat => c.VK_FORMAT_R16G16B16A16_SFLOAT,

        .rgb32_uint => c.VK_FORMAT_R32G32B32_UINT,
        .rgb32_sint => c.VK_FORMAT_R32G32B32_SINT,
        .rgb32_sfloat => c.VK_FORMAT_R32G32B32_SFLOAT,

        .rg64_uint => c.VK_FORMAT_R64G64_UINT,
        .rg64_sint => c.VK_FORMAT_R64G64_SINT,
        .rg64_sfloat => c.VK_FORMAT_R64G64_SFLOAT,
        .rgba32_uint => c.VK_FORMAT_R32G32B32A32_UINT,
        .rgba32_sint => c.VK_FORMAT_R32G32B32A32_SINT,
        .rgba32_sfloat => c.VK_FORMAT_R32G32B32A32_SFLOAT,

        .rgb64_uint => c.VK_FORMAT_R64G64B64_UINT,
        .rgb64_sint => c.VK_FORMAT_R64G64B64_SINT,
        .rgb64_sfloat => c.VK_FORMAT_R64G64B64_SFLOAT,

        .rgba64_uint => c.VK_FORMAT_R64G64B64A64_UINT,
        .rgba64_sint => c.VK_FORMAT_R64G64B64A64_SINT,
        .rgba64_sfloat => c.VK_FORMAT_R64G64B64A64_SFLOAT,

        .d16_unorm => c.VK_FORMAT_D16_UNORM,
        .x8_d24_unorm => c.VK_FORMAT_X8_D24_UNORM_PACK32,
        .d32_sfloat => c.VK_FORMAT_D32_SFLOAT,
        .s8_uint => c.VK_FORMAT_S8_UINT,
        .d16_unorm_s8_uint => c.VK_FORMAT_D16_UNORM_S8_UINT,
        .d24_unorm_s8_uint => c.VK_FORMAT_D24_UNORM_S8_UINT,
        .d32_sfloat_s8_uint => c.VK_FORMAT_D32_SFLOAT_S8_UINT,

        // TODO: Compressed formats
    };
}

pub fn toVkSampleCount(sample_count: ngl.SampleCount) c.VkSampleCountFlagBits {
    return switch (sample_count) {
        .@"1" => c.VK_SAMPLE_COUNT_1_BIT,
        .@"2" => c.VK_SAMPLE_COUNT_2_BIT,
        .@"4" => c.VK_SAMPLE_COUNT_4_BIT,
        .@"8" => c.VK_SAMPLE_COUNT_8_BIT,
        .@"16" => c.VK_SAMPLE_COUNT_16_BIT,
        .@"32" => c.VK_SAMPLE_COUNT_32_BIT,
        .@"64" => c.VK_SAMPLE_COUNT_64_BIT,
    };
}

pub fn toVkSampleCountFlags(sample_count_flags: ngl.SampleCount.Flags) c.VkSampleCountFlags {
    var flags: c.VkSampleCountFlags = 0;
    if (sample_count_flags.@"1") flags |= c.VK_SAMPLE_COUNT_1_BIT;
    if (sample_count_flags.@"2") flags |= c.VK_SAMPLE_COUNT_2_BIT;
    if (sample_count_flags.@"4") flags |= c.VK_SAMPLE_COUNT_4_BIT;
    if (sample_count_flags.@"8") flags |= c.VK_SAMPLE_COUNT_8_BIT;
    if (sample_count_flags.@"16") flags |= c.VK_SAMPLE_COUNT_16_BIT;
    if (sample_count_flags.@"32") flags |= c.VK_SAMPLE_COUNT_32_BIT;
    if (sample_count_flags.@"64") flags |= c.VK_SAMPLE_COUNT_64_BIT;
    return flags;
}
