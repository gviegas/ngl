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

pub fn toVkImageAspect(image_aspect: ngl.Image.Aspect) c.VkImageAspectFlagBits {
    return switch (image_aspect) {
        .color => c.VK_IMAGE_ASPECT_COLOR_BIT,
        .depth => c.VK_IMAGE_ASPECT_DEPTH_BIT,
        .stencil => c.VK_IMAGE_ASPECT_STENCIL_BIT,
    };
}

pub fn toVkImageAspectFlags(image_aspect_flags: ngl.Image.Aspect.Flags) c.VkImageAspectFlags {
    var flags: c.VkImageAspectFlags = 0;
    if (image_aspect_flags.color) flags |= c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (image_aspect_flags.depth) flags |= c.VK_IMAGE_ASPECT_DEPTH_BIT;
    if (image_aspect_flags.stencil) flags |= c.VK_IMAGE_ASPECT_STENCIL_BIT;
    return flags;
}

pub fn toVkImageLayout(image_layout: ngl.Image.Layout) c.VkImageLayout {
    return switch (image_layout) {
        .undefined => c.VK_IMAGE_LAYOUT_UNDEFINED,
        .preinitialized => c.VK_IMAGE_LAYOUT_PREINITIALIZED,
        .general => c.VK_IMAGE_LAYOUT_GENERAL,
        .color_attachment_optimal => c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .depth_stencil_attachment_optimal => c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .depth_stencil_read_only_optimal => c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        .shader_read_only_optimal => c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .transfer_source_optimal => c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .transfer_dest_optimal => c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        // TODO: Should check availability
        .present_source__ext => c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .shared_present__ext => c.VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR,
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
        // TODO: Should check availability
        .mirror_clamp_to_edge__ext => c.VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE,
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

// TODO: `toVkPipelineStage2`
pub fn toVkPipelineStage(pipeline_stage: ngl.PipelineStage) c.VkPipelineStageFlagBits {
    return switch (pipeline_stage) {
        .none => c.VK_PIPELINE_STAGE_NONE,
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
    };
}

// TODO: `toVkPipelineStageFlags2`
pub fn toVkPipelineStageFlags(
    pipeline_stage_flags: ngl.PipelineStage.Flags,
) c.VkPipelineStageFlags {
    if (pipeline_stage_flags.none or ngl.noFlagsSet(pipeline_stage_flags)) return 0; // c.VK_PIPELINE_STAGE_NONE
    if (pipeline_stage_flags.all_commands) return c.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;

    var flags: c.VkPipelineStageFlags = 0;

    if (pipeline_stage_flags.all_graphics) {
        flags |= c.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT;
        if (pipeline_stage_flags.compute_shader)
            flags |= c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
        if (pipeline_stage_flags.clear or pipeline_stage_flags.copy)
            flags |= c.VK_PIPELINE_STAGE_TRANSFER_BIT;
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
    if (access_flags.none or ngl.noFlagsSet(access_flags)) return 0; // c.VK_ACCESS_NONE

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
    if (resolve_mode_flags.average) flags |= c.VK_RESOLVE_MODE_AVERAGE_BIT;
    if (resolve_mode_flags.sample_zero) flags |= c.VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
    if (resolve_mode_flags.min) flags |= c.VK_RESOLVE_MODE_MIN_BIT;
    if (resolve_mode_flags.max) flags |= c.VK_RESOLVE_MODE_MAX_BIT;
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
