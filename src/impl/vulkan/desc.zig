const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const log = @import("init.zig").log;
const Device = @import("init.zig").Device;
const Sampler = @import("res.zig").Sampler;

// TODO: Don't allocate this type on the heap
pub const DescriptorSetLayout = struct {
    handle: c.VkDescriptorSetLayout,

    pub inline fn cast(impl: Impl.DescriptorSetLayout) *DescriptorSetLayout {
        return impl.ptr(DescriptorSetLayout);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!Impl.DescriptorSetLayout {
        const dev = Device.cast(device);

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

        var ptr = try allocator.create(DescriptorSetLayout);
        errdefer allocator.destroy(ptr);

        var set_layout: c.VkDescriptorSetLayout = undefined;
        try conv.check(dev.vkCreateDescriptorSetLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = bind_n,
            .pBindings = if (binds) |x| x.ptr else null,
        }, null, &set_layout));

        ptr.* = .{ .handle = set_layout };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descriptor_set_layout: Impl.DescriptorSetLayout,
    ) void {
        const dev = Device.cast(device);
        const set_layout = cast(descriptor_set_layout);
        dev.vkDestroyDescriptorSetLayout(set_layout.handle, null);
        allocator.destroy(set_layout);
    }
};

// TODO: Don't allocate this type on the heap
pub const PipelineLayout = struct {
    handle: c.VkPipelineLayout,

    pub inline fn cast(impl: Impl.PipelineLayout) *PipelineLayout {
        return impl.ptr(PipelineLayout);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.PipelineLayout.Desc,
    ) Error!Impl.PipelineLayout {
        const dev = Device.cast(device);

        const set_layout_n: u32 = if (desc.descriptor_set_layouts) |x| @intCast(x.len) else 0;
        var set_layouts: ?[]c.VkDescriptorSetLayout = blk: {
            if (set_layout_n == 0) break :blk null;
            var handles = try allocator.alloc(c.VkDescriptorSetLayout, set_layout_n);
            for (handles, desc.descriptor_set_layouts.?) |*handle, set_layout|
                handle.* = DescriptorSetLayout.cast(set_layout.impl).handle;
            break :blk handles;
        };
        defer if (set_layouts) |x| allocator.free(x);

        const const_range_n: u32 = if (desc.push_constant_ranges) |x| @intCast(x.len) else 0;
        var const_ranges: ?[]c.VkPushConstantRange = blk: {
            if (const_range_n == 0) break :blk null;
            var const_ranges = try allocator.alloc(c.VkPushConstantRange, const_range_n);
            for (const_ranges, desc.push_constant_ranges.?) |*vk_const_range, const_range|
                vk_const_range.* = .{
                    .stageFlags = conv.toVkShaderStageFlags(const_range.stage_mask),
                    .offset = const_range.offset,
                    .size = const_range.size,
                };
            break :blk const_ranges;
        };
        defer if (const_ranges) |x| allocator.free(x);

        var ptr = try allocator.create(PipelineLayout);
        errdefer allocator.destroy(ptr);

        var pl_layout: c.VkPipelineLayout = undefined;
        try conv.check(dev.vkCreatePipelineLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = set_layout_n,
            .pSetLayouts = if (set_layouts) |x| x.ptr else null,
            .pushConstantRangeCount = const_range_n,
            .pPushConstantRanges = if (const_ranges) |x| x.ptr else null,
        }, null, &pl_layout));

        ptr.* = .{ .handle = pl_layout };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        pipeline_layout: Impl.PipelineLayout,
    ) void {
        const dev = Device.cast(device);
        const pl_layout = cast(pipeline_layout);
        dev.vkDestroyPipelineLayout(pl_layout.handle, null);
        allocator.destroy(pl_layout);
    }
};

// TODO: Don't allocate this type on the heap
pub const DescriptorPool = struct {
    handle: c.VkDescriptorPool,

    pub inline fn cast(impl: Impl.DescriptorPool) *DescriptorPool {
        return impl.ptr(DescriptorPool);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!Impl.DescriptorPool {
        const dev = Device.cast(device);

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

        var ptr = try allocator.create(DescriptorPool);
        errdefer allocator.destroy(ptr);

        var desc_pool: c.VkDescriptorPool = undefined;
        try conv.check(dev.vkCreateDescriptorPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .maxSets = desc.max_sets,
            .poolSizeCount = pool_size_n,
            .pPoolSizes = if (pool_size_n > 0) pool_sizes[0..].ptr else null,
        }, null, &desc_pool));

        ptr.* = .{ .handle = desc_pool };
        return .{ .val = @intFromPtr(ptr) };
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void {
        const dev = Device.cast(device);
        const desc_pool = cast(descriptor_pool);

        var set_layouts = try allocator.alloc(c.VkDescriptorSetLayout, desc.layouts.len);
        defer allocator.free(set_layouts);
        for (set_layouts, desc.layouts) |*handle, layout|
            handle.* = DescriptorSetLayout.cast(layout.impl).handle;

        var handles = try allocator.alloc(c.VkDescriptorSet, desc.layouts.len);
        defer allocator.free(handles);

        const alloc_info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = desc_pool.handle,
            .descriptorSetCount = @intCast(set_layouts.len),
            .pSetLayouts = set_layouts.ptr,
        };

        try conv.check(dev.vkAllocateDescriptorSets(&alloc_info, handles.ptr));

        for (descriptor_sets, handles) |*set, handle|
            set.impl = .{ .val = @bitCast(DescriptorSet{ .handle = handle }) };
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
    ) void {
        const dev = Device.cast(device);
        const desc_pool = cast(descriptor_pool);
        dev.vkDestroyDescriptorPool(desc_pool.handle, null);
        allocator.destroy(desc_pool);
    }
};

pub const DescriptorSet = packed struct {
    handle: c.VkDescriptorSet,

    pub inline fn cast(impl: Impl.DescriptorSet) DescriptorSet {
        return @bitCast(impl.val);
    }
};
