const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const c = @import("../c.zig");

/// Non-dispatchable handles should check against this constant.
pub const null_handle = switch (@typeInfo(@TypeOf(c.VK_NULL_HANDLE))) {
    .Optional => null,
    .Int => 0,
    else => @compileError("Should never happen"),
};

/// Returns either a valid non-dispatchable handle or `null`.
pub inline fn ndhOrNull(handle: anytype) switch (@typeInfo(@TypeOf(null_handle))) {
    .Null => @TypeOf(handle),
    .ComptimeInt => ?@TypeOf(handle),
    else => @compileError("Should never happen"),
} {
    return switch (@typeInfo(@TypeOf(null_handle))) {
        .Null => handle orelse null,
        .ComptimeInt => if (handle != 0) handle else null,
        else => @compileError("Should never happen"),
    };
}

/// Anything other than `VK_SUCCESS` produces an `Error`.
pub fn check(result: c.VkResult) Error!void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_NOT_READY => Error.NotReady,
        c.VK_TIMEOUT => Error.Timeout,

        c.VK_ERROR_OUT_OF_HOST_MEMORY,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY,
        c.VK_ERROR_OUT_OF_POOL_MEMORY, // v1.1
        => Error.OutOfMemory,

        c.VK_ERROR_INITIALIZATION_FAILED => Error.InitializationFailed,
        c.VK_ERROR_DEVICE_LOST => Error.DeviceLost,
        c.VK_ERROR_TOO_MANY_OBJECTS => Error.TooManyObjects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => Error.NotSupported,

        c.VK_ERROR_LAYER_NOT_PRESENT,
        c.VK_ERROR_EXTENSION_NOT_PRESENT,
        c.VK_ERROR_FEATURE_NOT_PRESENT,
        => Error.NotPresent,

        c.VK_ERROR_FRAGMENTED_POOL,
        c.VK_ERROR_FRAGMENTATION, // v1.2
        => Error.Fragmentation,

        // VK_KHR_surface
        c.VK_ERROR_SURFACE_LOST_KHR => Error.SurfaceLost,
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => Error.WindowInUse,

        // VK_KHR_swapchain
        c.VK_SUBOPTIMAL_KHR,
        c.VK_ERROR_OUT_OF_DATE_KHR,
        => Error.OutOfDate,

        else => Error.Other,
    };
}

// Conversions to Vulkan types -----------------------------

/// `Error.NotSupported` indicates that the API format doesn't have
/// an exactly match in Vulkan.
pub fn toVkFormat(format: ngl.Format) Error!c.VkFormat {
    return switch (format) {
        .unknown => c.VK_FORMAT_UNDEFINED,

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
    if (sample_count_flags.@"1")
        flags |= c.VK_SAMPLE_COUNT_1_BIT;
    if (sample_count_flags.@"2")
        flags |= c.VK_SAMPLE_COUNT_2_BIT;
    if (sample_count_flags.@"4")
        flags |= c.VK_SAMPLE_COUNT_4_BIT;
    if (sample_count_flags.@"8")
        flags |= c.VK_SAMPLE_COUNT_8_BIT;
    if (sample_count_flags.@"16")
        flags |= c.VK_SAMPLE_COUNT_16_BIT;
    if (sample_count_flags.@"32")
        flags |= c.VK_SAMPLE_COUNT_32_BIT;
    if (sample_count_flags.@"64")
        flags |= c.VK_SAMPLE_COUNT_64_BIT;
    return flags;
}

pub fn toVkImageAspect(image_aspect: ngl.Image.Aspect) c.VkImageAspectFlagBits {
    return switch (image_aspect) {
        .color => c.VK_IMAGE_ASPECT_COLOR_BIT,
        .depth => c.VK_IMAGE_ASPECT_DEPTH_BIT,
        .stencil => c.VK_IMAGE_ASPECT_STENCIL_BIT,
    };
}

pub fn toVkImageAspectFlags(image_aspect_flags: ngl.Image.Aspect.Flags) c.VkImageAspectFlags {
    var flags: c.VkImageAspectFlags = 0;
    if (image_aspect_flags.color)
        flags |= c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (image_aspect_flags.depth)
        flags |= c.VK_IMAGE_ASPECT_DEPTH_BIT;
    if (image_aspect_flags.stencil)
        flags |= c.VK_IMAGE_ASPECT_STENCIL_BIT;
    return flags;
}

pub fn toVkImageLayout(image_layout: ngl.Image.Layout) c.VkImageLayout {
    return switch (image_layout) {
        .unknown => c.VK_IMAGE_LAYOUT_UNDEFINED,
        .preinitialized => c.VK_IMAGE_LAYOUT_PREINITIALIZED,
        .general => c.VK_IMAGE_LAYOUT_GENERAL,
        .color_attachment_optimal => c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .depth_stencil_attachment_optimal => c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .depth_stencil_read_only_optimal => c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        .shader_read_only_optimal => c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .transfer_source_optimal => c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .transfer_dest_optimal => c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .present_source => c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
}

pub fn toVkCompareOp(compare_op: ngl.CompareOp) c.VkCompareOp {
    return switch (compare_op) {
        .never => c.VK_COMPARE_OP_NEVER,
        .less => c.VK_COMPARE_OP_LESS,
        .equal => c.VK_COMPARE_OP_EQUAL,
        .less_equal => c.VK_COMPARE_OP_LESS_OR_EQUAL,
        .greater => c.VK_COMPARE_OP_GREATER,
        .not_equal => c.VK_COMPARE_OP_NOT_EQUAL,
        .greater_equal => c.VK_COMPARE_OP_GREATER_OR_EQUAL,
        .always => c.VK_COMPARE_OP_ALWAYS,
    };
}

pub fn toVkSamplerAddressMode(
    sampler_address_mode: ngl.Sampler.AddressMode,
) c.VkSamplerAddressMode {
    return switch (sampler_address_mode) {
        .clamp_to_edge => c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .clamp_to_border => c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .repeat => c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .mirror_repeat => c.VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT,
        .mirror_clamp_to_edge => c.VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE,
    };
}

pub fn toVkBorderColor(sampler_border_color: ngl.Sampler.BorderColor) c.VkBorderColor {
    return switch (sampler_border_color) {
        .transparent_black_float => c.VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
        .transparent_black_int => c.VK_BORDER_COLOR_INT_TRANSPARENT_BLACK,
        .opaque_black_float => c.VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK,
        .opaque_black_int => c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .opaque_white_float => c.VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE,
        .opaque_white_int => c.VK_BORDER_COLOR_INT_OPAQUE_WHITE,
    };
}

pub fn toVkFilter(sampler_filter: ngl.Sampler.Filter) c.VkFilter {
    return switch (sampler_filter) {
        .nearest => c.VK_FILTER_NEAREST,
        .linear => c.VK_FILTER_LINEAR,
    };
}

pub fn toVkSamplerMipmapMode(sampler_mipmap_mode: ngl.Sampler.MipmapMode) c.VkSamplerMipmapMode {
    return switch (sampler_mipmap_mode) {
        .nearest => c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .linear => c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
    };
}

pub fn toVkBufferUsageFlags(buffer_usage: ngl.Buffer.Usage) c.VkBufferUsageFlags {
    var usage: c.VkBufferUsageFlags = 0;
    if (buffer_usage.uniform_texel_buffer)
        usage |= c.VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT;
    if (buffer_usage.storage_texel_buffer)
        usage |= c.VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT;
    if (buffer_usage.uniform_buffer)
        usage |= c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (buffer_usage.storage_buffer)
        usage |= c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (buffer_usage.index_buffer)
        usage |= c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (buffer_usage.vertex_buffer)
        usage |= c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (buffer_usage.indirect_buffer)
        usage |= c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    if (buffer_usage.transfer_source)
        usage |= c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (buffer_usage.transfer_dest)
        usage |= c.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    return usage;
}

pub fn toVkImageUsageFlags(image_usage: ngl.Image.Usage) c.VkImageUsageFlags {
    var usage: c.VkImageUsageFlags = 0;
    if (image_usage.sampled_image)
        usage |= c.VK_IMAGE_USAGE_SAMPLED_BIT;
    if (image_usage.storage_image)
        usage |= c.VK_IMAGE_USAGE_STORAGE_BIT;
    if (image_usage.color_attachment)
        usage |= c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (image_usage.depth_stencil_attachment)
        usage |= c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    if (image_usage.transient_attachment)
        usage |= c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
    if (image_usage.input_attachment)
        usage |= c.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
    if (image_usage.transfer_source)
        usage |= c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (image_usage.transfer_dest)
        usage |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    return usage;
}

// TODO: `toVkPipelineStage2`
pub fn toVkPipelineStage(
    comptime scope: enum { source, dest },
    pipeline_stage: ngl.PipelineStage,
) c.VkPipelineStageFlagBits {
    return switch (pipeline_stage) {
        // `VK_PIPELINE_STAGE_NONE` (i.e. 0) is generally not allowed
        // on vanilla commands unless synchronization2 is enabled,
        // so we resort to the top of pipe and bottom of pipe stages
        .none => switch (scope) {
            .source => c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .dest => c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        },

        .all_commands => c.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
        .all_graphics => c.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
        .draw_indirect => c.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,

        .index_input,
        .vertex_attribute_input,
        => c.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,

        .vertex_shader => c.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,
        .early_fragment_tests => c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .fragment_shader => c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        .late_fragment_tests => c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .color_attachment_output => c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .compute_shader => c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,

        .clear,
        .copy,
        => c.VK_PIPELINE_STAGE_TRANSFER_BIT,

        .host => c.VK_PIPELINE_STAGE_HOST_BIT,
    };
}

// TODO: `toVkPipelineStageFlags2`
pub fn toVkPipelineStageFlags(
    comptime scope: enum { source, dest },
    pipeline_stage_flags: ngl.PipelineStage.Flags,
) c.VkPipelineStageFlags {
    if (pipeline_stage_flags.none or ngl.noFlagsSet(pipeline_stage_flags))
        return switch (scope) {
            .source => c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .dest => c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        };

    var flags: c.VkPipelineStageFlags = 0;

    if (pipeline_stage_flags.all_commands) {
        flags |= c.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
        if (pipeline_stage_flags.host)
            flags |= c.VK_PIPELINE_STAGE_HOST_BIT;
        return flags;
    }

    if (pipeline_stage_flags.all_graphics) {
        flags |= c.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT;
        if (pipeline_stage_flags.compute_shader)
            flags |= c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
        if (pipeline_stage_flags.clear or pipeline_stage_flags.copy)
            flags |= c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        if (pipeline_stage_flags.host)
            flags |= c.VK_PIPELINE_STAGE_HOST_BIT;
        return flags;
    }

    if (pipeline_stage_flags.draw_indirect)
        flags |= c.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
    if (pipeline_stage_flags.index_input or pipeline_stage_flags.vertex_attribute_input)
        flags |= c.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT;
    if (pipeline_stage_flags.vertex_shader)
        flags |= c.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
    if (pipeline_stage_flags.early_fragment_tests)
        flags |= c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    if (pipeline_stage_flags.fragment_shader)
        flags |= c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    if (pipeline_stage_flags.late_fragment_tests)
        flags |= c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
    if (pipeline_stage_flags.color_attachment_output)
        flags |= c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    if (pipeline_stage_flags.compute_shader)
        flags |= c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    if (pipeline_stage_flags.clear or pipeline_stage_flags.copy)
        flags |= c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    if (pipeline_stage_flags.host)
        flags |= c.VK_PIPELINE_STAGE_HOST_BIT;
    return flags;
}

// TODO: toVkAccess2
pub fn toVkAccess(_: ngl.Access) c.VkAccessFlagBits {
    // Nothing in Vulkan 1.3 seems to use these values
    // by themselves, only as `VkAccessFlags`
    @compileError("What do you need this for?");
}

// TODO: toVkAccessFlags2
pub fn toVkAccessFlags(access_flags: ngl.Access.Flags) c.VkAccessFlags {
    if (access_flags.none or ngl.noFlagsSet(access_flags))
        return 0; // c.VK_ACCESS_NONE

    var flags: c.VkAccessFlags = 0;

    if (access_flags.memory_read) {
        flags |= c.VK_ACCESS_MEMORY_READ_BIT;
        if (access_flags.memory_write) {
            flags |= c.VK_ACCESS_MEMORY_WRITE_BIT;
        } else {
            if (access_flags.shader_storage_write)
                flags |= c.VK_ACCESS_SHADER_WRITE_BIT;
            if (access_flags.color_attachment_write)
                flags |= c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            if (access_flags.depth_stencil_attachment_write)
                flags |= c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
            if (access_flags.transfer_write)
                flags |= c.VK_ACCESS_TRANSFER_WRITE_BIT;
            if (access_flags.host_write)
                flags |= c.VK_ACCESS_HOST_WRITE_BIT;
        }
        return flags;
    }

    if (access_flags.memory_write) {
        flags |= c.VK_ACCESS_MEMORY_WRITE_BIT;
        if (access_flags.indirect_command_read)
            flags |= c.VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
        if (access_flags.index_read)
            flags |= c.VK_ACCESS_INDEX_READ_BIT;
        if (access_flags.vertex_attribute_read)
            flags |= c.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT;
        if (access_flags.uniform_read)
            flags |= c.VK_ACCESS_UNIFORM_READ_BIT;
        if (access_flags.input_attachment_read)
            flags |= c.VK_ACCESS_INPUT_ATTACHMENT_READ_BIT;
        if (access_flags.shader_sampled_read or access_flags.shader_storage_read)
            flags |= c.VK_ACCESS_SHADER_READ_BIT;
        if (access_flags.color_attachment_read)
            flags |= c.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT;
        if (access_flags.depth_stencil_attachment_read)
            flags |= c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
        if (access_flags.transfer_read)
            flags |= c.VK_ACCESS_TRANSFER_READ_BIT;
        if (access_flags.host_read)
            flags |= c.VK_ACCESS_HOST_READ_BIT;
        return flags;
    }

    if (access_flags.indirect_command_read)
        flags |= c.VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
    if (access_flags.index_read)
        flags |= c.VK_ACCESS_INDEX_READ_BIT;
    if (access_flags.vertex_attribute_read)
        flags |= c.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT;
    if (access_flags.uniform_read)
        flags |= c.VK_ACCESS_UNIFORM_READ_BIT;
    if (access_flags.input_attachment_read)
        flags |= c.VK_ACCESS_INPUT_ATTACHMENT_READ_BIT;
    if (access_flags.shader_sampled_read or access_flags.shader_storage_read)
        flags |= c.VK_ACCESS_SHADER_READ_BIT;
    if (access_flags.shader_storage_write)
        flags |= c.VK_ACCESS_SHADER_WRITE_BIT;
    if (access_flags.color_attachment_read)
        flags |= c.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT;
    if (access_flags.color_attachment_write)
        flags |= c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    if (access_flags.depth_stencil_attachment_read)
        flags |= c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
    if (access_flags.depth_stencil_attachment_write)
        flags |= c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    if (access_flags.transfer_read)
        flags |= c.VK_ACCESS_TRANSFER_READ_BIT;
    if (access_flags.transfer_write)
        flags |= c.VK_ACCESS_TRANSFER_WRITE_BIT;
    if (access_flags.host_read)
        flags |= c.VK_ACCESS_HOST_READ_BIT;
    if (access_flags.host_write)
        flags |= c.VK_ACCESS_HOST_WRITE_BIT;
    return flags;
}

pub fn toVkAttachmentLoadOp(load_op: ngl.LoadOp) c.VkAttachmentLoadOp {
    return switch (load_op) {
        .load => c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .clear => c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .dont_care => c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    };
}

pub fn toVkAttachmentStoreOp(store_op: ngl.StoreOp) c.VkAttachmentStoreOp {
    return switch (store_op) {
        .store => c.VK_ATTACHMENT_STORE_OP_STORE,
        .dont_care => c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
    };
}

/// v1.2
pub fn toVkResolveMode(resolve_mode: ngl.ResolveMode) c.VkResolveModeFlagBits {
    return switch (resolve_mode) {
        .average => c.VK_RESOLVE_MODE_AVERAGE_BIT,
        .sample_zero => c.VK_RESOLVE_MODE_SAMPLE_ZERO_BIT,
        .min => c.VK_RESOLVE_MODE_MIN_BIT,
        .max => c.VK_RESOLVE_MODE_MAX_BIT,
    };
}

/// v1.2
pub fn toVkResolveModeFlags(resolve_mode_flags: ngl.ResolveMode.Flags) c.VkResolveModeFlags {
    var flags: c.VkResolveModeFlags = 0;
    if (resolve_mode_flags.average)
        flags |= c.VK_RESOLVE_MODE_AVERAGE_BIT;
    if (resolve_mode_flags.sample_zero)
        flags |= c.VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
    if (resolve_mode_flags.min)
        flags |= c.VK_RESOLVE_MODE_MIN_BIT;
    if (resolve_mode_flags.max)
        flags |= c.VK_RESOLVE_MODE_MAX_BIT;
    return flags;
}

pub fn toVkDescriptorType(descriptor_type: ngl.DescriptorType) c.VkDescriptorType {
    return switch (descriptor_type) {
        .sampler => c.VK_DESCRIPTOR_TYPE_SAMPLER,
        .combined_image_sampler => c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .sampled_image => c.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
        .storage_image => c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .uniform_texel_buffer => c.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
        .storage_texel_buffer => c.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
        .uniform_buffer => c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .storage_buffer => c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .input_attachment => c.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
    };
}

pub fn toVkPipelineBindPoint(pipeline_type: ngl.Pipeline.Type) c.VkPipelineBindPoint {
    return switch (pipeline_type) {
        .graphics => c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .compute => c.VK_PIPELINE_BIND_POINT_COMPUTE,
    };
}

pub fn toVkShaderStage(shader_stage: ngl.ShaderStage) c.VkShaderStageFlagBits {
    return switch (shader_stage) {
        .vertex => c.VK_SHADER_STAGE_VERTEX_BIT,
        .fragment => c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .compute => c.VK_SHADER_STAGE_COMPUTE_BIT,
    };
}

pub fn toVkShaderStageFlags(shader_stage_flags: ngl.ShaderStage.Flags) c.VkShaderStageFlags {
    var flags: c.VkShaderStageFlags = 0;
    if (shader_stage_flags.vertex)
        flags |= c.VK_SHADER_STAGE_VERTEX_BIT;
    if (shader_stage_flags.fragment)
        flags |= c.VK_SHADER_STAGE_FRAGMENT_BIT;
    if (shader_stage_flags.compute)
        flags |= c.VK_SHADER_STAGE_COMPUTE_BIT;
    return flags;
}

pub fn toVkPrimitiveTopology(topology: ngl.Primitive.Topology) c.VkPrimitiveTopology {
    return switch (topology) {
        .point_list => c.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        .line_list => c.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
        .line_strip => c.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
        .triangle_list => c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .triangle_strip => c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
    };
}

pub fn toVkPolygonMode(polygon_mode: ngl.Rasterization.PolygonMode) c.VkPolygonMode {
    return switch (polygon_mode) {
        .fill => c.VK_POLYGON_MODE_FILL,
        .line => c.VK_POLYGON_MODE_LINE,
    };
}

/// Always used as flags type.
pub fn toVkCullModeFlags(cull_mode: ngl.Rasterization.CullMode) c.VkCullModeFlags {
    return switch (cull_mode) {
        .none => c.VK_CULL_MODE_NONE,
        .front => c.VK_CULL_MODE_FRONT_BIT,
        .back => c.VK_CULL_MODE_BACK_BIT,
    };
}

pub fn toVkStencilOp(stencil_op: ngl.DepthStencil.StencilOp) c.VkStencilOp {
    return switch (stencil_op) {
        .keep => c.VK_STENCIL_OP_KEEP,
        .zero => c.VK_STENCIL_OP_ZERO,
        .replace => c.VK_STENCIL_OP_REPLACE,
        .increment_clamp => c.VK_STENCIL_OP_INCREMENT_AND_CLAMP,
        .decrement_clamp => c.VK_STENCIL_OP_DECREMENT_AND_CLAMP,
        .invert => c.VK_STENCIL_OP_INVERT,
        .increment_wrap => c.VK_STENCIL_OP_INCREMENT_AND_WRAP,
        .decrement_wrap => c.VK_STENCIL_OP_DECREMENT_AND_WRAP,
    };
}

pub fn toVkBlendFactor(blend_factor: ngl.ColorBlend.BlendFactor) c.VkBlendFactor {
    return switch (blend_factor) {
        .zero => c.VK_BLEND_FACTOR_ZERO,
        .one => c.VK_BLEND_FACTOR_ONE,
        .source_color => c.VK_BLEND_FACTOR_SRC_COLOR,
        .one_minus_source_color => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
        .dest_color => c.VK_BLEND_FACTOR_DST_COLOR,
        .one_minus_dest_color => c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
        .source_alpha => c.VK_BLEND_FACTOR_SRC_ALPHA,
        .one_minus_source_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .dest_alpha => c.VK_BLEND_FACTOR_DST_ALPHA,
        .one_minus_dest_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
        .constant_color => c.VK_BLEND_FACTOR_CONSTANT_COLOR,
        .one_minus_constant_color => c.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR,
        .constant_alpha => c.VK_BLEND_FACTOR_CONSTANT_ALPHA,
        .one_minus_constant_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA,
        .source_alpha_saturate => c.VK_BLEND_FACTOR_SRC_ALPHA_SATURATE,
    };
}

pub fn toVkBlendOp(blend_op: ngl.ColorBlend.BlendOp) c.VkBlendOp {
    return switch (blend_op) {
        .add => c.VK_BLEND_OP_ADD,
        .subtract => c.VK_BLEND_OP_SUBTRACT,
        .reverse_subtract => c.VK_BLEND_OP_REVERSE_SUBTRACT,
        .min => c.VK_BLEND_OP_MIN,
        .max => c.VK_BLEND_OP_MAX,
    };
}

pub fn toVkIndexType(index_type: ngl.CommandBuffer.Cmd.IndexType) c.VkIndexType {
    return switch (index_type) {
        .u16 => c.VK_INDEX_TYPE_UINT16,
        .u32 => c.VK_INDEX_TYPE_UINT32,
    };
}

pub fn toVkStencilFaceFlags(stencil_face: ngl.CommandBuffer.Cmd.StencilFace) c.VkStencilFaceFlags {
    return switch (stencil_face) {
        .front => c.VK_STENCIL_FACE_FRONT_BIT,
        .back => c.VK_STENCIL_FACE_BACK_BIT,
        .front_and_back => c.VK_STENCIL_FACE_FRONT_AND_BACK,
    };
}

pub fn toVkSubpassContents(
    subpass_contents: ngl.CommandBuffer.Cmd.SubpassContents,
) c.VkSubpassContents {
    return switch (subpass_contents) {
        .inline_only => c.VK_SUBPASS_CONTENTS_INLINE,
        .secondary_command_buffers_only => c.VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS,
    };
}

pub fn toVkClearValue(clear_value: ngl.CommandBuffer.Cmd.ClearValue) c.VkClearValue {
    return switch (clear_value) {
        .color_f32 => |x| .{ .color = .{ .float32 = x } },
        .color_i32 => |x| .{ .color = .{ .int32 = x } },
        .color_u32 => |x| .{ .color = .{ .uint32 = x } },
        .depth_stencil => |x| .{ .depthStencil = .{ .depth = x.@"0", .stencil = x.@"1" } },
    };
}

pub fn toVkColorSpace(color_space: ngl.Surface.ColorSpace) c.VkColorSpaceKHR {
    return switch (color_space) {
        .srgb_non_linear => c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
    };
}

pub fn toVkPresentMode(present_mode: ngl.Surface.PresentMode) c.VkPresentModeKHR {
    return switch (present_mode) {
        .immediate => c.VK_PRESENT_MODE_IMMEDIATE_KHR,
        .mailbox => c.VK_PRESENT_MODE_MAILBOX_KHR,
        .fifo => c.VK_PRESENT_MODE_FIFO_KHR,
        .fifo_relaxed => c.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
    };
}

pub fn toVkCompositeAlpha(
    composite_alpha: ngl.Surface.CompositeAlpha,
) c.VkCompositeAlphaFlagBitsKHR {
    return switch (composite_alpha) {
        .@"opaque" => c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .pre_multiplied => c.VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        .post_multiplied => c.VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        .inherit => c.VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
}

pub fn toVkSurfaceTransform(transform: ngl.Surface.Transform) c.VkSurfaceTransformFlagBitsKHR {
    return switch (transform) {
        .identity => c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
        .rotate_90 => c.VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR,
        .rotate_180 => c.VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR,
        .rotate_270 => c.VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR,
        .horizontal_mirror => c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR,
        .horizontal_mirror_rotate_90 => c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR,
        .horizontal_mirror_rotate_180 => c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR,
        .horizontal_mirror_rotate_270 => c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR,
        .inherit => c.VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR,
    };
}

// Conversions from Vulkan types ---------------------------

/// `Error.NotSupported` indicates that the API doens't expose the given
/// Vulkan format.
pub fn fromVkFormat(vk_format: c.VkFormat) Error!ngl.Format {
    return switch (vk_format) {
        c.VK_FORMAT_UNDEFINED => .unknown,

        c.VK_FORMAT_R8_UNORM => .r8_unorm,
        c.VK_FORMAT_R8_SRGB => .r8_srgb,
        c.VK_FORMAT_R8_SNORM => .r8_snorm,
        c.VK_FORMAT_R8_UINT => .r8_uint,
        c.VK_FORMAT_R8_SINT => .r8_sint,
        1000470001 => .a8_unorm, // c.VK_FORMAT_A8_UNORM_KHR,
        c.VK_FORMAT_R4G4_UNORM_PACK8 => .r4g4_unorm,

        c.VK_FORMAT_R16_UNORM => .r16_unorm,
        c.VK_FORMAT_R16_SNORM => .r16_snorm,
        c.VK_FORMAT_R16_UINT => .r16_uint,
        c.VK_FORMAT_R16_SINT => .r16_sint,
        c.VK_FORMAT_R16_SFLOAT => .r16_sfloat,
        c.VK_FORMAT_R8G8_UNORM => .rg8_unorm,
        c.VK_FORMAT_R8G8_SRGB => .rg8_srgb,
        c.VK_FORMAT_R8G8_SNORM => .rg8_snorm,
        c.VK_FORMAT_R8G8_UINT => .rg8_uint,
        c.VK_FORMAT_R8G8_SINT => .rg8_sint,
        c.VK_FORMAT_R4G4B4A4_UNORM_PACK16 => .rgba4_unorm,
        c.VK_FORMAT_B4G4R4A4_UNORM_PACK16 => .bgra4_unorm,
        c.VK_FORMAT_A4R4G4B4_UNORM_PACK16 => .argb4_unorm,
        c.VK_FORMAT_A4B4G4R4_UNORM_PACK16 => .abgr4_unorm,
        c.VK_FORMAT_R5G6B5_UNORM_PACK16 => .r5g6b5_unorm,
        c.VK_FORMAT_B5G6R5_UNORM_PACK16 => .b5g6r5_unorm,
        c.VK_FORMAT_R5G5B5A1_UNORM_PACK16 => .rgb5a1_unorm,
        c.VK_FORMAT_B5G5R5A1_UNORM_PACK16 => .bgr5a1_unorm,
        c.VK_FORMAT_A1R5G5B5_UNORM_PACK16 => .a1rgb5_unorm,
        1000470000 => .a1bgr5_unorm, // c.VK_FORMAT_A1B5G5R5_UNORM_PACK16_KHR,

        c.VK_FORMAT_R8G8B8_UNORM => .rgb8_unorm,
        c.VK_FORMAT_R8G8B8_SRGB => .rgb8_srgb,
        c.VK_FORMAT_R8G8B8_SNORM => .rgb8_snorm,
        c.VK_FORMAT_R8G8B8_UINT => .rgb8_uint,
        c.VK_FORMAT_R8G8B8_SINT => .rgb8_sint,
        c.VK_FORMAT_B8G8R8_UNORM => .bgr8_unorm,
        c.VK_FORMAT_B8G8R8_SRGB => .bgr8_srgb,
        c.VK_FORMAT_B8G8R8_SNORM => .bgr8_snorm,
        c.VK_FORMAT_B8G8R8_UINT => .bgr8_uint,
        c.VK_FORMAT_B8G8R8_SINT => .bgr8_sint,

        c.VK_FORMAT_R32_UINT => .r32_uint,
        c.VK_FORMAT_R32_SINT => .r32_sint,
        c.VK_FORMAT_R32_SFLOAT => .r32_sfloat,
        c.VK_FORMAT_R16G16_UNORM => .rg16_unorm,
        c.VK_FORMAT_R16G16_SNORM => .rg16_snorm,
        c.VK_FORMAT_R16G16_UINT => .rg16_uint,
        c.VK_FORMAT_R16G16_SINT => .rg16_sint,
        c.VK_FORMAT_R16G16_SFLOAT => .rg16_sfloat,
        c.VK_FORMAT_R8G8B8A8_UNORM => .rgba8_unorm,
        c.VK_FORMAT_R8G8B8A8_SRGB => .rgba8_srgb,
        c.VK_FORMAT_R8G8B8A8_SNORM => .rgba8_snorm,
        c.VK_FORMAT_R8G8B8A8_UINT => .rgba8_uint,
        c.VK_FORMAT_R8G8B8A8_SINT => .rgba8_sint,
        c.VK_FORMAT_B8G8R8A8_UNORM => .bgra8_unorm,
        c.VK_FORMAT_B8G8R8A8_SRGB => .bgra8_srgb,
        c.VK_FORMAT_B8G8R8A8_SNORM => .bgra8_snorm,
        c.VK_FORMAT_B8G8R8A8_UINT => .bgra8_uint,
        c.VK_FORMAT_B8G8R8A8_SINT => .bgra8_sint,
        c.VK_FORMAT_A2R10G10B10_UNORM_PACK32 => .a2rgb10_unorm,
        c.VK_FORMAT_A2R10G10B10_UINT_PACK32 => .a2rgb10_uint,
        c.VK_FORMAT_A2B10G10R10_UNORM_PACK32 => .a2bgr10_unorm,
        c.VK_FORMAT_A2B10G10R10_UINT_PACK32 => .a2bgr10_uint,
        c.VK_FORMAT_B10G11R11_UFLOAT_PACK32 => .b10gr11_ufloat,
        c.VK_FORMAT_E5B9G9R9_UFLOAT_PACK32 => .e5bgr9_ufloat,

        c.VK_FORMAT_R16G16B16_UNORM => .rgb16_unorm,
        c.VK_FORMAT_R16G16B16_SNORM => .rgb16_snorm,
        c.VK_FORMAT_R16G16B16_UINT => .rgb16_uint,
        c.VK_FORMAT_R16G16B16_SINT => .rgb16_sint,
        c.VK_FORMAT_R16G16B16_SFLOAT => .rgb16_sfloat,

        c.VK_FORMAT_R64_UINT => .r64_uint,
        c.VK_FORMAT_R64_SINT => .r64_sint,
        c.VK_FORMAT_R64_SFLOAT => .r64_sfloat,
        c.VK_FORMAT_R32G32_UINT => .rg32_uint,
        c.VK_FORMAT_R32G32_SINT => .rg32_sint,
        c.VK_FORMAT_R32G32_SFLOAT => .rg32_sfloat,
        c.VK_FORMAT_R16G16B16A16_UNORM => .rgba16_unorm,
        c.VK_FORMAT_R16G16B16A16_SNORM => .rgba16_snorm,
        c.VK_FORMAT_R16G16B16A16_UINT => .rgba16_uint,
        c.VK_FORMAT_R16G16B16A16_SINT => .rgba16_sint,
        c.VK_FORMAT_R16G16B16A16_SFLOAT => .rgba16_sfloat,

        c.VK_FORMAT_R32G32B32_UINT => .rgb32_uint,
        c.VK_FORMAT_R32G32B32_SINT => .rgb32_sint,
        c.VK_FORMAT_R32G32B32_SFLOAT => .rgb32_sfloat,

        c.VK_FORMAT_R64G64_UINT => .rg64_uint,
        c.VK_FORMAT_R64G64_SINT => .rg64_sint,
        c.VK_FORMAT_R64G64_SFLOAT => .rg64_sfloat,
        c.VK_FORMAT_R32G32B32A32_UINT => .rgba32_uint,
        c.VK_FORMAT_R32G32B32A32_SINT => .rgba32_sint,
        c.VK_FORMAT_R32G32B32A32_SFLOAT => .rgba32_sfloat,

        c.VK_FORMAT_R64G64B64_UINT => .rgb64_uint,
        c.VK_FORMAT_R64G64B64_SINT => .rgb64_sint,
        c.VK_FORMAT_R64G64B64_SFLOAT => .rgb64_sfloat,

        c.VK_FORMAT_R64G64B64A64_UINT => .rgba64_uint,
        c.VK_FORMAT_R64G64B64A64_SINT => .rgba64_sint,
        c.VK_FORMAT_R64G64B64A64_SFLOAT => .rgba64_sfloat,

        c.VK_FORMAT_D16_UNORM => .d16_unorm,
        c.VK_FORMAT_X8_D24_UNORM_PACK32 => .x8_d24_unorm,
        c.VK_FORMAT_D32_SFLOAT => .d32_sfloat,
        c.VK_FORMAT_S8_UINT => .s8_uint,
        c.VK_FORMAT_D16_UNORM_S8_UINT => .d16_unorm_s8_uint,
        c.VK_FORMAT_D24_UNORM_S8_UINT => .d24_unorm_s8_uint,
        c.VK_FORMAT_D32_SFLOAT_S8_UINT => .d32_sfloat_s8_uint,

        // TODO: Compressed formats

        else => error.NotSupported,
    };
}

pub fn fromVkImageUsageFlags(vk_flags: c.VkImageUsageFlags) ngl.Image.Usage {
    var usage = ngl.Image.Usage{};
    if (vk_flags & c.VK_IMAGE_USAGE_SAMPLED_BIT != 0)
        usage.sampled_image = true;
    if (vk_flags & c.VK_IMAGE_USAGE_STORAGE_BIT != 0)
        usage.storage_image = true;
    if (vk_flags & c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT != 0)
        usage.color_attachment = true;
    if (vk_flags & c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT != 0)
        usage.depth_stencil_attachment = true;
    if (vk_flags & c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT != 0)
        usage.transient_attachment = true;
    if (vk_flags & c.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT != 0)
        usage.input_attachment = true;
    if (vk_flags & c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT != 0)
        usage.transfer_source = true;
    if (vk_flags & c.VK_IMAGE_USAGE_TRANSFER_DST_BIT != 0)
        usage.transfer_dest = true;
    return usage;
}

pub fn fromVkCompositeAlphaFlags(
    vk_flags: c.VkCompositeAlphaFlagsKHR,
) ngl.Surface.CompositeAlpha.Flags {
    var flags = ngl.Surface.CompositeAlpha.Flags{};
    if (vk_flags & c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR != 0)
        flags.@"opaque" = true;
    if (vk_flags & c.VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR != 0)
        flags.pre_multiplied = true;
    if (vk_flags & c.VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR != 0)
        flags.post_multiplied = true;
    if (vk_flags & c.VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR != 0)
        flags.inherit = true;
    return flags;
}

/// `Error.NotSupported` indicates that the API doesn't expose the given
/// Vulkan color space.
pub fn fromVkColorSpace(vk_color_space: c.VkColorSpaceKHR) Error!ngl.Surface.ColorSpace {
    if (@typeInfo(ngl.Surface.ColorSpace).Enum.fields.len > 1)
        @compileError("Update Vulkan conversion");
    return switch (vk_color_space) {
        c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR => .srgb_non_linear,
        else => return Error.NotSupported,
    };
}

pub fn fromVkSurfaceTransform(vk_transform: c.VkSurfaceTransformFlagBitsKHR) ngl.Surface.Transform {
    return switch (vk_transform) {
        c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR => .identity,
        c.VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR => .rotate_90,
        c.VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR => .rotate_180,
        c.VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR => .rotate_270,
        c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR => .horizontal_mirror,
        c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR => .horizontal_mirror_rotate_90,
        c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR => .horizontal_mirror_rotate_180,
        c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR => .horizontal_mirror_rotate_270,
        c.VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR => .inherit,
        else => .inherit,
    };
}

pub fn fromVkSurfaceTransformFlags(
    vk_flags: c.VkSurfaceTransformFlagsKHR,
) ngl.Surface.Transform.Flags {
    var flags = ngl.Surface.Transform.Flags{};
    if (vk_flags & c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR != 0)
        flags.identity = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR != 0)
        flags.rotate_90 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR != 0)
        flags.rotate_180 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR != 0)
        flags.rotate_270 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR != 0)
        flags.horizontal_mirror = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR != 0)
        flags.horizontal_mirror_rotate_90 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR != 0)
        flags.horizontal_mirror_rotate_180 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR != 0)
        flags.horizontal_mirror_rotate_270 = true;
    if (vk_flags & c.VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR != 0)
        flags.inherit = true;
    return flags;
}
