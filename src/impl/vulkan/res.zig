const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Device = @import("init.zig").Device;
const Memory = @import("init.zig").Memory;

// TODO: Don't allocate this type on the heap
pub const Buffer = struct {
    handle: c.VkBuffer,

    pub inline fn cast(impl: Impl.Buffer) *Buffer {
        return impl.ptr(Buffer);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Buffer.Desc,
    ) Error!Impl.Buffer {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Buffer);
        errdefer allocator.destroy(ptr);

        const usage = blk: {
            var usage: c.VkBufferUsageFlags = 0;
            if (desc.usage.uniform_texel_buffer) usage |= c.VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT;
            if (desc.usage.storage_texel_buffer) usage |= c.VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT;
            if (desc.usage.uniform_buffer) usage |= c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
            if (desc.usage.storage_buffer) usage |= c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
            if (desc.usage.index_buffer) usage |= c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
            if (desc.usage.vertex_buffer) usage |= c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
            if (desc.usage.indirect_buffer) usage |= c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
            if (desc.usage.transfer_source) usage |= c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            if (desc.usage.transfer_dest) usage |= c.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            break :blk usage;
        };

        var buf: c.VkBuffer = undefined;
        try check(dev.vkCreateBuffer(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = desc.size,
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        }, null, &buf));

        ptr.* = .{ .handle = buf };
        return .{ .val = @intFromPtr(ptr) };
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
            .mem_type_bits = mem_req.memoryTypeBits,
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
        allocator: std.mem.Allocator,
        device: Impl.Device,
        buffer: Impl.Buffer,
    ) void {
        const dev = Device.cast(device);
        const buf = cast(buffer);
        dev.vkDestroyBuffer(buf.handle, null);
        allocator.destroy(buf);
    }
};

// TODO: Don't allocate this type on the heap
pub const BufferView = struct {
    handle: c.VkBufferView,

    pub inline fn cast(impl: Impl.BufferView) *BufferView {
        return impl.ptr(BufferView);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.BufferView.Desc,
    ) Error!Impl.BufferView {
        const dev = Device.cast(device);
        const buf = Buffer.cast(desc.buffer.impl);

        var ptr = try allocator.create(BufferView);
        errdefer allocator.destroy(ptr);

        var buf_view: c.VkBufferView = undefined;
        try check(dev.vkCreateBufferView(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .buffer = buf.handle,
            .format = try conv.toVkFormat(desc.format),
            .offset = desc.offset,
            .range = desc.range orelse c.VK_WHOLE_SIZE,
        }, null, &buf_view));

        ptr.* = .{ .handle = buf_view };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        buffer_view: Impl.BufferView,
    ) void {
        const dev = Device.cast(device);
        const buf_view = cast(buffer_view);
        dev.vkDestroyBufferView(buf_view.handle, null);
        allocator.destroy(buf_view);
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
            var usage: c.VkImageUsageFlags = 0;
            if (desc.usage.sampled_image) usage |= c.VK_IMAGE_USAGE_SAMPLED_BIT;
            if (desc.usage.storage_image) usage |= c.VK_IMAGE_USAGE_STORAGE_BIT;
            if (desc.usage.color_attachment) usage |= c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
            if (desc.usage.depth_stencil_attachment) usage |= c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
            if (desc.usage.transient_attachment) usage |= c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
            if (desc.usage.input_attachment) usage |= c.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
            if (desc.usage.transfer_source) usage |= c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
            if (desc.usage.transfer_dest) usage |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
            break :blk usage;
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
            .mem_type_bits = mem_req.memoryTypeBits,
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
