const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;

pub const Buffer = struct {
    handle: c.VkBuffer,

    pub inline fn cast(impl: *Impl.Buffer) *Buffer {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.Buffer.Desc,
    ) Error!*Impl.Buffer {
        const dev = Device.cast(device);

        var ptr = try allocator.create(Buffer);
        errdefer allocator.destroy(ptr);

        const usage = blk: {
            var usage: c.VkBufferUsageFlags = 0;
            if (desc.usage.uniform_buffer) usage |= c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
            //if (desc.usage.uniform_texel_buffer) usage |= c.VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT;
            if (desc.usage.storage_buffer) usage |= c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
            //if (desc.usage.storage_texel_buffer) usage |= c.VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT;
            if (desc.usage.index_buffer) usage |= c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
            if (desc.usage.vertex_buffer) usage |= c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
            if (desc.usage.indirect_buffer) usage |= c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
            if (desc.usage.transfer_source) usage |= c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            if (desc.usage.transfer_dest) usage |= c.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            break :blk usage;
        };

        var buf: c.VkBuffer = undefined;
        try conv.check(dev.vkCreateBuffer(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = @as(c.VkDeviceSize, desc.size),
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        }, null, &buf));

        ptr.* = .{ .handle = buf };
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        buffer: *Impl.Buffer,
    ) void {
        const dev = Device.cast(device);
        const buf = cast(buffer);
        dev.vkDestroyBuffer(buf.handle, null);
        allocator.destroy(buf);
    }
};
