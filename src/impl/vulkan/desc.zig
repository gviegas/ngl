const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const Device = @import("init.zig").Device;
const Buffer = @import("res.zig").Buffer;
const BufferView = @import("res.zig").BufferView;
const ImageView = @import("res.zig").ImageView;
const Sampler = @import("res.zig").Sampler;

pub const DescriptorSetLayout = packed struct {
    handle: c.VkDescriptorSetLayout,

    pub inline fn cast(impl: Impl.DescriptorSetLayout) DescriptorSetLayout {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!Impl.DescriptorSetLayout {
        const bind_n: u32 = if (desc.bindings) |x| @intCast(x.len) else 0;
        var binds: ?[]c.VkDescriptorSetLayoutBinding = undefined;
        var splrs: ?[]c.VkSampler = undefined;
        if (bind_n > 0) {
            binds = try allocator.alloc(c.VkDescriptorSetLayoutBinding, bind_n);
            errdefer allocator.free(binds.?);
            var splr_n: usize = 0;
            for (desc.bindings.?) |bind| {
                if (bind.immutable_samplers) |x| splr_n += x.len;
            }
            var splrs_ptr: [*]c.VkSampler = undefined;
            if (splr_n > 0) {
                splrs = try allocator.alloc(c.VkSampler, splr_n);
                splrs_ptr = splrs.?.ptr;
            } else splrs = null;
            for (binds.?, desc.bindings.?) |*vk_bind, bind| {
                vk_bind.* = .{
                    .binding = bind.binding,
                    .descriptorType = conv.toVkDescriptorType(bind.type),
                    .descriptorCount = bind.count,
                    .stageFlags = conv.toVkShaderStageFlags(bind.stage_mask),
                    .pImmutableSamplers = blk: {
                        const bind_splrs = bind.immutable_samplers orelse &.{};
                        if (bind_splrs.len == 0) break :blk null;
                        for (bind_splrs, 0..) |s, i| splrs_ptr[i] = Sampler.cast(s.impl).handle;
                        splrs_ptr += bind_splrs.len;
                        break :blk splrs_ptr - bind_splrs.len;
                    },
                };
            }
        } else {
            binds = null;
            splrs = null;
        }
        defer if (binds) |x| allocator.free(x);
        defer if (splrs) |x| allocator.free(x);

        var set_layout: c.VkDescriptorSetLayout = undefined;
        try check(Device.cast(device).vkCreateDescriptorSetLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = bind_n,
            .pBindings = if (binds) |x| x.ptr else null,
        }, null, &set_layout));

        return .{ .val = @bitCast(DescriptorSetLayout{ .handle = set_layout }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        descriptor_set_layout: Impl.DescriptorSetLayout,
    ) void {
        Device.cast(device).vkDestroyDescriptorSetLayout(cast(descriptor_set_layout).handle, null);
    }
};

pub const PipelineLayout = packed struct {
    handle: c.VkPipelineLayout,

    pub inline fn cast(impl: Impl.PipelineLayout) PipelineLayout {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.PipelineLayout.Desc,
    ) Error!Impl.PipelineLayout {
        const set_layout_n: u32 = if (desc.descriptor_set_layouts) |x| @intCast(x.len) else 0;
        const set_layouts: ?[]c.VkDescriptorSetLayout = blk: {
            if (set_layout_n == 0) break :blk null;
            const handles = try allocator.alloc(c.VkDescriptorSetLayout, set_layout_n);
            for (handles, desc.descriptor_set_layouts.?) |*handle, set_layout|
                handle.* = DescriptorSetLayout.cast(set_layout.impl).handle;
            break :blk handles;
        };
        defer if (set_layouts) |x| allocator.free(x);

        const const_range_n: u32 = if (desc.push_constant_ranges) |x| @intCast(x.len) else 0;
        const const_ranges: ?[]c.VkPushConstantRange = blk: {
            if (const_range_n == 0) break :blk null;
            const const_ranges = try allocator.alloc(c.VkPushConstantRange, const_range_n);
            for (const_ranges, desc.push_constant_ranges.?) |*vk_const_range, const_range|
                vk_const_range.* = .{
                    .stageFlags = conv.toVkShaderStageFlags(const_range.stage_mask),
                    .offset = const_range.offset,
                    .size = const_range.size,
                };
            break :blk const_ranges;
        };
        defer if (const_ranges) |x| allocator.free(x);

        var pl_layout: c.VkPipelineLayout = undefined;
        try check(Device.cast(device).vkCreatePipelineLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = set_layout_n,
            .pSetLayouts = if (set_layouts) |x| x.ptr else null,
            .pushConstantRangeCount = const_range_n,
            .pPushConstantRanges = if (const_ranges) |x| x.ptr else null,
        }, null, &pl_layout));

        return .{ .val = @bitCast(PipelineLayout{ .handle = pl_layout }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        pipeline_layout: Impl.PipelineLayout,
    ) void {
        Device.cast(device).vkDestroyPipelineLayout(cast(pipeline_layout).handle, null);
    }
};

pub const DescriptorPool = packed struct {
    handle: c.VkDescriptorPool,

    pub inline fn cast(impl: Impl.DescriptorPool) DescriptorPool {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!Impl.DescriptorPool {
        const max_type = @typeInfo(ngl.DescriptorType).Enum.fields.len;
        var pool_sizes: [max_type]c.VkDescriptorPoolSize = undefined;
        const pool_size_n = blk: {
            var n: u32 = 0;
            inline for (@typeInfo(ngl.DescriptorPool.PoolSize).Struct.fields) |f| {
                const size = @field(desc.pool_size, f.name);
                if (size > 0) {
                    pool_sizes[n] = .{
                        .type = conv.toVkDescriptorType(@field(ngl.DescriptorType, f.name)),
                        .descriptorCount = size,
                    };
                    n += 1;
                }
            }
            break :blk n;
        };

        var desc_pool: c.VkDescriptorPool = undefined;
        try check(Device.cast(device).vkCreateDescriptorPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .maxSets = desc.max_sets,
            .poolSizeCount = pool_size_n,
            .pPoolSizes = if (pool_size_n > 0) pool_sizes[0..].ptr else null,
        }, null, &desc_pool));

        return .{ .val = @bitCast(DescriptorPool{ .handle = desc_pool }) };
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void {
        const set_layouts = try allocator.alloc(c.VkDescriptorSetLayout, desc.layouts.len);
        defer allocator.free(set_layouts);
        for (set_layouts, desc.layouts) |*handle, layout|
            handle.* = DescriptorSetLayout.cast(layout.impl).handle;

        const handles = try allocator.alloc(c.VkDescriptorSet, desc.layouts.len);
        defer allocator.free(handles);

        const alloc_info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = cast(descriptor_pool).handle,
            .descriptorSetCount = @intCast(set_layouts.len),
            .pSetLayouts = set_layouts.ptr,
        };

        try check(Device.cast(device).vkAllocateDescriptorSets(&alloc_info, handles.ptr));

        for (descriptor_sets, handles) |*set, handle|
            set.impl = .{ .val = @bitCast(DescriptorSet{ .handle = handle }) };
    }

    pub fn reset(
        _: *anyopaque,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
    ) Error!void {
        // Unused in v1.3
        const flags: c.VkDescriptorPoolResetFlags = 0;
        return check(Device.cast(device).vkResetDescriptorPool(
            cast(descriptor_pool).handle,
            flags,
        ));
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
    ) void {
        Device.cast(device).vkDestroyDescriptorPool(cast(descriptor_pool).handle, null);
    }
};

pub const DescriptorSet = packed struct {
    handle: c.VkDescriptorSet,

    pub inline fn cast(impl: Impl.DescriptorSet) DescriptorSet {
        return @bitCast(impl.val);
    }

    pub fn write(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        writes: []const ngl.DescriptorSet.Write,
    ) Error!void {
        const desc_set_writes = try allocator.alloc(c.VkWriteDescriptorSet, writes.len);
        defer allocator.free(desc_set_writes);

        var img_infos: ?[]c.VkDescriptorImageInfo = undefined;
        var buf_infos: ?[]c.VkDescriptorBufferInfo = undefined;
        var buf_views: ?[]c.VkBufferView = undefined;
        {
            var img_info_n: usize = 0;
            var buf_info_n: usize = 0;
            var buf_view_n: usize = 0;
            for (writes) |w| {
                switch (w.contents) {
                    .sampler => |x| img_info_n += x.len,
                    .combined_image_sampler => |x| img_info_n += x.len,
                    .sampled_image,
                    .storage_image,
                    .input_attachment,
                    => |x| img_info_n += x.len,

                    .uniform_texel_buffer,
                    .storage_texel_buffer,
                    => |x| buf_view_n += x.len,

                    .uniform_buffer,
                    .storage_buffer,
                    => |x| buf_info_n += x.len,
                }
            }

            img_infos = if (img_info_n > 0) try allocator.alloc(
                c.VkDescriptorImageInfo,
                img_info_n,
            ) else null;
            errdefer if (img_infos) |x| allocator.free(x);

            buf_infos = if (buf_info_n > 0) try allocator.alloc(
                c.VkDescriptorBufferInfo,
                buf_info_n,
            ) else null;
            errdefer if (buf_infos) |x| allocator.free(x);

            buf_views = if (buf_view_n > 0) try allocator.alloc(
                c.VkBufferView,
                buf_view_n,
            ) else null;
        }
        defer if (img_infos) |x| allocator.free(x);
        defer if (buf_infos) |x| allocator.free(x);
        defer if (buf_views) |x| allocator.free(x);

        var img_infos_ptr = if (img_infos) |x| x.ptr else undefined;
        var buf_infos_ptr = if (buf_infos) |x| x.ptr else undefined;
        var buf_views_ptr = if (buf_views) |x| x.ptr else undefined;

        for (desc_set_writes, writes) |*dsw, w| {
            dsw.* = .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = cast(w.descriptor_set.impl).handle,
                .dstBinding = w.binding,
                .dstArrayElement = w.element,
                .descriptorCount = undefined, // Set below
                .descriptorType = conv.toVkDescriptorType(w.contents),
                .pImageInfo = undefined, // Set below
                .pBufferInfo = undefined, // Set below
                .pTexelBufferView = undefined, // Set below
            };

            switch (w.contents) {
                .sampler => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, splr|
                        info.* = .{
                            .sampler = Sampler.cast(splr.impl).handle,
                            .imageView = null_handle,
                            .imageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                        };
                    img_infos_ptr += x.len;
                },

                .combined_image_sampler => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, img_splr|
                        info.* = .{
                            .sampler = if (img_splr.sampler) |s|
                                Sampler.cast(s.impl).handle
                            else
                                null_handle,
                            .imageView = ImageView.cast(img_splr.view.impl).handle,
                            .imageLayout = conv.toVkImageLayout(img_splr.layout),
                        };
                    img_infos_ptr += x.len;
                },

                .sampled_image,
                .storage_image,
                .input_attachment,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, image|
                        info.* = .{
                            .sampler = null_handle,
                            .imageView = ImageView.cast(image.view.impl).handle,
                            .imageLayout = conv.toVkImageLayout(image.layout),
                        };
                    img_infos_ptr += x.len;
                },

                .uniform_texel_buffer,
                .storage_texel_buffer,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = null;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = buf_views_ptr;
                    for (buf_views_ptr, x) |*handle, view|
                        handle.* = BufferView.cast(view.impl).handle;
                    buf_views_ptr += x.len;
                },

                .uniform_buffer,
                .storage_buffer,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = null;
                    dsw.pBufferInfo = buf_infos_ptr;
                    dsw.pTexelBufferView = null;
                    for (buf_infos_ptr, x) |*info, buf|
                        info.* = .{
                            .buffer = Buffer.cast(buf.buffer.impl).handle,
                            .offset = buf.offset,
                            .range = buf.range,
                        };
                    buf_infos_ptr += x.len;
                },
            }
        }

        Device.cast(device).vkUpdateDescriptorSets(
            @intCast(desc_set_writes.len),
            desc_set_writes.ptr,
            0,
            null,
        );
    }
};
