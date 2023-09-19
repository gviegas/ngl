const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Queue = ngl.Queue;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const CommandPool = struct {
    impl: *Impl.CommandPool,

    pub const Desc = struct {
        queue: *const Queue,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initCommandPool(allocator, device.impl, desc) };
    }

    pub fn alloc(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: CommandBuffer.Desc,
    ) Error![]CommandBuffer {
        std.debug.assert(desc.count > 0);
        var cmd_bufs = try allocator.alloc(CommandBuffer, desc.count);
        errdefer allocator.free(cmd_bufs);
        // TODO: Update this when adding more fields to `CommandBuffer`
        if (std.meta.fields(CommandBuffer).len > 1) @compileError(
            \\Impl only sets the impl field
            \\This function must initialize the others
        );
        try Impl.get().allocCommandBuffers(allocator, self.impl, device.impl, desc, cmd_bufs);
        return cmd_bufs;
    }

    pub fn free(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        command_buffers: []CommandBuffer,
    ) void {
        Impl.get().freeCommandBuffers(allocator, self.impl, device.impl, command_buffers);
        allocator.free(command_buffers);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitCommandPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const CommandBuffer = struct {
    impl: *Impl.CommandBuffer,

    pub const Level = enum {
        primary,
        secondary,
    };

    pub const Desc = struct {
        level: Level,
        count: u32,
    };

    pub const Self = @This();
};
