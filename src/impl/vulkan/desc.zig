const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;

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

        // TODO
        _ = desc;

        var ptr = try allocator.create(DescriptorSetLayout);
        errdefer allocator.destroy(ptr);

        var set_layout: c.VkDescriptorSetLayout = undefined;
        try conv.check(dev.vkCreateDescriptorSetLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = 0, // TODO
            .pBindings = null, // TODO
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
