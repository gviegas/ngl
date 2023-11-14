const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;
const Memory = @import("init.zig").Memory;

pub fn getFormatFeatures(
    _: *anyopaque,
    device: Impl.Device,
    format: ngl.Format,
) ngl.Format.FeatureSet {
    const dev = Device.cast(device);

    var props: c.VkFormatProperties = undefined;
    dev.instance.vkGetPhysicalDeviceFormatProperties(
        dev.physical_device,
        conv.toVkFormat(format) catch return .{
            .linear_tiling = .{},
            .optimal_tiling = .{},
            .buffer = .{},
        },
        &props,
    );

    // TODO: There's no valid usage defined for these flags, so in theory
    // an implementation could do something confusing like setting only
    // `VK_FORMAT_FEATURE_STORAGE_IMAGE_ATOMIC_BIT` and assume that
    // `VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT` is inferred

    const convFlagsImg = struct {
        fn f(flags: c.VkFormatFeatureFlags) ngl.Format.Features {
            var feats = ngl.Format.Features{};
            if (flags != 0) {
                feats.sampled_image =
                    flags & c.VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT != 0;
                feats.sampled_image_filter_linear =
                    flags & c.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT != 0;
                feats.storage_image =
                    flags & c.VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT != 0;
                feats.storage_image_atomic =
                    flags & c.VK_FORMAT_FEATURE_STORAGE_IMAGE_ATOMIC_BIT != 0;
                feats.color_attachment =
                    flags & c.VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT != 0;
                feats.color_attachment_blend =
                    flags & c.VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT != 0;
                feats.depth_stencil_attachment =
                    flags & c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT != 0;
            }
            return feats;
        }
    }.f;

    const convFlagsBuf = struct {
        fn f(flags: c.VkFormatFeatureFlags) ngl.Format.Features {
            var feats = ngl.Format.Features{};
            if (flags != 0) {
                feats.uniform_texel_buffer =
                    flags & c.VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT != 0;
                feats.storage_texel_buffer =
                    flags & c.VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT != 0;
                feats.storage_texel_buffer_atomic =
                    flags & c.VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_ATOMIC_BIT != 0;
                feats.vertex_buffer =
                    flags & c.VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT != 0;
            }
            return feats;
        }
    }.f;

    const lin = convFlagsImg(props.linearTilingFeatures);
    return .{
        .linear_tiling = lin,
        .optimal_tiling = if (props.linearTilingFeatures == props.optimalTilingFeatures)
            lin
        else
            convFlagsImg(props.optimalTilingFeatures),
        .buffer = convFlagsBuf(props.bufferFeatures),
    };
}

pub const Buffer = packed struct {
    handle: c.VkBuffer,

    pub inline fn cast(impl: Impl.Buffer) Buffer {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Buffer.Desc,
    ) Error!Impl.Buffer {
        var buf: c.VkBuffer = undefined;
        try check(Device.cast(device).vkCreateBuffer(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = desc.size,
            .usage = conv.toVkBufferUsageFlags(desc.usage),
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        }, null, &buf));

        return .{ .val = @bitCast(Buffer{ .handle = buf }) };
    }

    pub fn getMemoryRequirements(
        _: *anyopaque,
        device: Impl.Device,
        buffer: Impl.Buffer,
    ) ngl.Memory.Requirements {
        var mem_req: c.VkMemoryRequirements = undefined;
        Device.cast(device).vkGetBufferMemoryRequirements(cast(buffer).handle, &mem_req);
        return .{
            .size = mem_req.size,
            .alignment = mem_req.alignment,
            .type_bits = mem_req.memoryTypeBits,
        };
    }

    pub fn bindMemory(
        _: *anyopaque,
        device: Impl.Device,
        buffer: Impl.Buffer,
        memory: Impl.Memory,
        memory_offset: u64,
    ) Error!void {
        try check(Device.cast(device).vkBindBufferMemory(
            cast(buffer).handle,
            Memory.cast(memory).handle,
            memory_offset,
        ));
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        buffer: Impl.Buffer,
    ) void {
        Device.cast(device).vkDestroyBuffer(cast(buffer).handle, null);
    }
};

pub const BufferView = packed struct {
    handle: c.VkBufferView,

    pub inline fn cast(impl: Impl.BufferView) BufferView {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.BufferView.Desc,
    ) Error!Impl.BufferView {
        var buf_view: c.VkBufferView = undefined;
        try check(Device.cast(device).vkCreateBufferView(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .buffer = Buffer.cast(desc.buffer.impl).handle,
            .format = try conv.toVkFormat(desc.format),
            .offset = desc.offset,
            .range = desc.range orelse c.VK_WHOLE_SIZE,
        }, null, &buf_view));

        return .{ .val = @bitCast(BufferView{ .handle = buf_view }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        buffer_view: Impl.BufferView,
    ) void {
        Device.cast(device).vkDestroyBufferView(cast(buffer_view).handle, null);
    }
};

// TODO: Don't allocate this type on the heap
pub const Image = struct {
    handle: c.VkImage,

    pub inline fn cast(impl: Impl.Image) *Image {
        return impl.ptr(Image);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Image.Desc,
    ) Error!Impl.Image {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Image);
        errdefer allocator.destroy(ptr);

        const @"type": c.VkImageType = switch (desc.type) {
            .@"1d" => c.VK_IMAGE_TYPE_1D,
            .@"2d" => c.VK_IMAGE_TYPE_2D,
            .@"3d" => c.VK_IMAGE_TYPE_3D,
        };
        const extent: c.VkExtent3D = .{
            .width = desc.width,
            .height = desc.height,
            .depth = if (desc.type == .@"3d") desc.depth_or_layers else 1,
        };
        const layers = if (desc.type == .@"3d") 1 else desc.depth_or_layers;
        const tiling: c.VkImageTiling = switch (desc.tiling) {
            .linear => c.VK_IMAGE_TILING_LINEAR,
            .optimal => c.VK_IMAGE_TILING_OPTIMAL,
        };
        const usage = blk: {
            const usage = conv.toVkImageUsageFlags(desc.usage);
            // Usage must not be zero
            break :blk if (usage != 0) usage else return Error.InvalidArgument;
        };
        const flags = blk: {
            var flags: c.VkImageCreateFlags = 0;
            if (desc.misc.view_formats) |fmts| {
                for (fmts) |f| {
                    if (f == desc.format) continue;
                    flags |= c.VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT;
                    break;
                }
            }
            if (desc.misc.cube_compatible) flags |= c.VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
            break :blk flags;
        };

        var image: c.VkImage = undefined;
        try check(dev.vkCreateImage(&.{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = flags,
            .imageType = @"type",
            .format = try conv.toVkFormat(desc.format),
            .extent = extent,
            .mipLevels = desc.levels,
            .arrayLayers = layers,
            .samples = conv.toVkSampleCount(desc.samples),
            .tiling = tiling,
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = conv.toVkImageLayout(desc.initial_layout),
        }, null, &image));

        ptr.* = .{ .handle = image };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn getMemoryRequirements(
        _: *anyopaque,
        device: Impl.Device,
        image: Impl.Image,
    ) ngl.Memory.Requirements {
        var mem_req: c.VkMemoryRequirements = undefined;
        Device.cast(device).vkGetImageMemoryRequirements(cast(image).handle, &mem_req);
        return .{
            .size = mem_req.size,
            .alignment = mem_req.alignment,
            .type_bits = mem_req.memoryTypeBits,
        };
    }

    pub fn bindMemory(
        _: *anyopaque,
        device: Impl.Device,
        image: Impl.Image,
        memory: Impl.Memory,
        memory_offset: u64,
    ) Error!void {
        try check(Device.cast(device).vkBindImageMemory(
            cast(image).handle,
            Memory.cast(memory).handle,
            memory_offset,
        ));
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        image: Impl.Image,
    ) void {
        const dev = Device.cast(device);
        const img = cast(image);
        dev.vkDestroyImage(img.handle, null);
        allocator.destroy(img);
    }
};

// TODO: Don't allocate this type on the heap
pub const ImageView = struct {
    handle: c.VkImageView,

    pub inline fn cast(impl: Impl.ImageView) *ImageView {
        return impl.ptr(ImageView);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.ImageView.Desc,
    ) Error!Impl.ImageView {
        const dev = Device.cast(device);
        const image = Image.cast(desc.image.impl);

        var ptr = try allocator.create(ImageView);
        errdefer allocator.destroy(ptr);

        const @"type": c.VkImageViewType = switch (desc.type) {
            .@"1d" => c.VK_IMAGE_VIEW_TYPE_1D,
            .@"2d" => c.VK_IMAGE_VIEW_TYPE_2D,
            .@"3d" => c.VK_IMAGE_VIEW_TYPE_3D,
            .cube => c.VK_IMAGE_VIEW_TYPE_CUBE,
            .@"1d_array" => c.VK_IMAGE_VIEW_TYPE_1D_ARRAY,
            .@"2d_array" => c.VK_IMAGE_VIEW_TYPE_2D_ARRAY,
            .cube_array => c.VK_IMAGE_VIEW_TYPE_CUBE_ARRAY,
        };
        // TODO
        const swizzle: c.VkComponentMapping = .{
            .r = c.VK_COMPONENT_SWIZZLE_R,
            .g = c.VK_COMPONENT_SWIZZLE_G,
            .b = c.VK_COMPONENT_SWIZZLE_B,
            .a = c.VK_COMPONENT_SWIZZLE_A,
        };
        const range: c.VkImageSubresourceRange = .{
            .aspectMask = conv.toVkImageAspectFlags(desc.range.aspect_mask),
            .baseMipLevel = desc.range.base_level,
            .levelCount = desc.range.levels orelse c.VK_REMAINING_MIP_LEVELS,
            .baseArrayLayer = desc.range.base_layer,
            .layerCount = desc.range.layers orelse c.VK_REMAINING_ARRAY_LAYERS,
        };

        var img_view: c.VkImageView = undefined;
        try check(dev.vkCreateImageView(&.{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image.handle,
            .viewType = @"type",
            .format = try conv.toVkFormat(desc.format),
            .components = swizzle,
            .subresourceRange = range,
        }, null, &img_view));

        ptr.* = .{ .handle = img_view };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        image_view: Impl.ImageView,
    ) void {
        const dev = Device.cast(device);
        const img_view = cast(image_view);
        dev.vkDestroyImageView(img_view.handle, null);
        allocator.destroy(img_view);
    }
};

// TODO: Don't allocate this type on the heap
pub const Sampler = struct {
    handle: c.VkSampler,

    pub inline fn cast(impl: Impl.Sampler) *Sampler {
        return impl.ptr(Sampler);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Sampler.Desc,
    ) Error!Impl.Sampler {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Sampler);
        errdefer allocator.destroy(ptr);

        var cmp_enable: c.VkBool32 = undefined;
        var compare: c.VkCompareOp = undefined;
        if (desc.compare) |cmp| {
            cmp_enable = c.VK_TRUE;
            compare = conv.toVkCompareOp(cmp);
        } else {
            cmp_enable = c.VK_FALSE;
            compare = c.VK_COMPARE_OP_NEVER;
        }

        var splr: c.VkSampler = undefined;
        try check(dev.vkCreateSampler(&.{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .magFilter = conv.toVkFilter(desc.mag),
            .minFilter = conv.toVkFilter(desc.min),
            .mipmapMode = conv.toVkSamplerMipmapMode(desc.mipmap),
            .addressModeU = conv.toVkSamplerAddressMode(desc.u_address),
            .addressModeV = conv.toVkSamplerAddressMode(desc.v_address),
            .addressModeW = conv.toVkSamplerAddressMode(desc.w_address),
            .mipLodBias = 0,
            .anisotropyEnable = c.VK_FALSE, // TODO: Need to enable the feature
            .maxAnisotropy = 1, // TODO: Need to clamp as specified in limits
            .compareEnable = cmp_enable,
            .compareOp = compare,
            .minLod = desc.min_lod,
            .maxLod = if (desc.max_lod) |x| x else c.VK_LOD_CLAMP_NONE,
            .borderColor = conv.toVkBorderColor(desc.border_color orelse .transparent_black_float),
            .unnormalizedCoordinates = if (desc.normalized_coordinates) c.VK_FALSE else c.VK_TRUE,
        }, null, &splr));

        ptr.* = .{ .handle = splr };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        sampler: Impl.Sampler,
    ) void {
        const dev = Device.cast(device);
        const splr = cast(sampler);
        dev.vkDestroySampler(splr.handle, null);
        allocator.destroy(splr);
    }
};
