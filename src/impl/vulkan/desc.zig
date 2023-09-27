const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;
const Sampler = @import("res.zig").Sampler;

pub const DescriptorSetLayout = struct {
    handle: c.VkDescriptorSetLayout,

    pub inline fn cast(impl: *Impl.DescriptorSetLayout) *DescriptorSetLayout {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!*Impl.DescriptorSetLayout {
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
                    .stageFlags = c.VK_SHADER_STAGE_ALL, // TODO
                    .pImmutableSamplers = blk: {
                        const bind_splrs = bind.immutable_samplers orelse &.{};
                        if (bind_splrs.len == 0) break :blk null;
                        for (bind_splrs, 0..) |s, i|
                            splrs_ptr[i] = Sampler.cast(Impl.Sampler.cast(s)).handle;
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
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        descriptor_set_layout: *Impl.DescriptorSetLayout,
    ) void {
        const dev = Device.cast(device);
        const set_layout = cast(descriptor_set_layout);
        dev.vkDestroyDescriptorSetLayout(set_layout.handle, null);
        allocator.destroy(set_layout);
    }
};

pub const PipelineLayout = struct {
    handle: c.VkPipelineLayout,

    pub inline fn cast(impl: *Impl.PipelineLayout) *PipelineLayout {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.PipelineLayout.Desc,
    ) Error!*Impl.PipelineLayout {
        const dev = Device.cast(device);

        const set_layout_n: u32 = if (desc.descriptor_set_layouts) |x| @intCast(x.len) else 0;
        var set_layouts: ?[]c.VkDescriptorSetLayout = blk: {
            if (set_layout_n == 0) break :blk null;
            var handles = try allocator.alloc(c.VkDescriptorSetLayout, set_layout_n);
            for (handles, desc.descriptor_set_layouts.?) |*handle, set_layout|
                handle.* = DescriptorSetLayout.cast(Impl.DescriptorSetLayout.cast(
                    set_layout,
                )).handle;
            break :blk handles;
        };
        defer if (set_layouts) |x| allocator.free(x);

        const const_range_n: u32 = if (desc.push_constant_ranges) |x| @intCast(x.len) else 0;
        var const_ranges: ?[]c.VkPushConstantRange = blk: {
            if (const_range_n == 0) break :blk null;
            var const_ranges = try allocator.alloc(c.VkPushConstantRange, const_range_n);
            for (const_ranges, desc.push_constant_ranges.?) |*vk_const_range, const_range|
                vk_const_range.* = .{
                    .stageFlags = c.VK_SHADER_STAGE_ALL, // TODO
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
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline_layout: *Impl.PipelineLayout,
    ) void {
        const dev = Device.cast(device);
        const pl_layout = cast(pipeline_layout);
        dev.vkDestroyPipelineLayout(pl_layout.handle, null);
        allocator.destroy(pl_layout);
    }
};

pub const DescriptorPool = struct {
    handle: c.VkDescriptorPool,

    pub inline fn cast(impl: *Impl.DescriptorPool) *DescriptorPool {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!*Impl.DescriptorPool {
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
        return @ptrCast(ptr);
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        descriptor_pool: *Impl.DescriptorPool,
        device: *Impl.Device,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void {
        const desc_pool = cast(descriptor_pool);
        const dev = Device.cast(device);

        var set_layouts = try allocator.alloc(c.VkDescriptorSetLayout, desc.layouts.len);
        defer allocator.free(set_layouts);
        for (set_layouts, desc.layouts) |*handle, layout|
            handle.* = DescriptorSetLayout.cast(layout.impl).handle;

        var desc_sets = try allocator.alloc(c.VkDescriptorSet, desc.layouts.len);
        defer allocator.free(desc_sets);

        const alloc_info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = desc_pool.handle,
            .descriptorSetCount = @intCast(set_layouts.len),
            .pSetLayouts = set_layouts.ptr,
        };

        try conv.check(dev.vkAllocateDescriptorSets(&alloc_info, desc_sets.ptr));
        // TODO: This call may fail
        errdefer _ = dev.vkFreeDescriptorSets(
            desc_pool.handle,
            @intCast(desc_sets.len),
            desc_sets.ptr,
        );

        for (desc_sets, 0..) |set, i| {
            var ptr = allocator.create(DescriptorSet) catch |err| {
                for (0..i) |j| allocator.destroy(DescriptorSet.cast(descriptor_sets[j].impl));
                return err;
            };
            ptr.* = .{ .handle = set };
            descriptor_sets[i].impl = @ptrCast(ptr);
        }
    }

    pub fn free(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        descriptor_pool: *Impl.DescriptorPool,
        device: *Impl.Device,
        descriptor_sets: []const ngl.DescriptorSet,
    ) void {
        const desc_pool = cast(descriptor_pool);
        const dev = Device.cast(device);
        const n = descriptor_sets.len;

        var desc_sets = allocator.alloc(c.VkDescriptorSet, n) catch {
            for (descriptor_sets) |set| {
                var ptr = DescriptorSet.cast(set.impl);
                const h: *[1]c.VkDescriptorSet = &ptr.handle;
                // TODO: This call may fail
                _ = dev.vkFreeDescriptorSets(desc_pool.handle, 1, h);
                allocator.destroy(ptr);
            }
            return;
        };
        defer allocator.free(desc_sets);

        for (0..n) |i| {
            var ptr = DescriptorSet.cast(descriptor_sets[i].impl);
            desc_sets[i] = ptr.handle;
            allocator.destroy(ptr);
        }
        // TODO: This call may fail
        _ = dev.vkFreeDescriptorSets(desc_pool.handle, @intCast(n), desc_sets.ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        descriptor_pool: *Impl.DescriptorPool,
    ) void {
        const dev = Device.cast(device);
        const desc_pool = cast(descriptor_pool);
        dev.vkDestroyDescriptorPool(desc_pool.handle, null);
        allocator.destroy(desc_pool);
    }
};

pub const DescriptorSet = struct {
    handle: c.VkDescriptorSet,

    pub inline fn cast(impl: *Impl.DescriptorSet) *DescriptorSet {
        return @ptrCast(@alignCast(impl));
    }
};
