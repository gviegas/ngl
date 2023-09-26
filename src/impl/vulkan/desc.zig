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
