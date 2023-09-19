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
        try conv.check(dev.vkCreateBuffer(&.{
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

pub const BufferView = struct {
    handle: c.VkBufferView,

    pub inline fn cast(impl: *Impl.BufferView) *BufferView {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.BufferView.Desc,
    ) Error!*Impl.BufferView {
        const dev = Device.cast(device);
        const buf = Buffer.cast(Impl.Buffer.cast(desc.buffer));

        var ptr = try allocator.create(BufferView);
        errdefer allocator.destroy(ptr);

        var buf_view: c.VkBufferView = undefined;
        try conv.check(dev.vkCreateBufferView(&.{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .buffer = buf.handle,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM, // TODO: Format conversion
            .offset = desc.offset,
            .range = desc.range orelse c.VK_WHOLE_SIZE,
        }, null, &buf_view));

        ptr.* = .{ .handle = buf_view };
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        buffer_view: *Impl.BufferView,
    ) void {
        const dev = Device.cast(device);
        const buf_view = cast(buffer_view);
        dev.vkDestroyBufferView(buf_view.handle, null);
        allocator.destroy(buf_view);
    }
};
