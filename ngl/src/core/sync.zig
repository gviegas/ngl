const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Stage = enum {
    none,
    all_commands,
    all_graphics,
    draw_indirect,
    index_input,
    vertex_attribute_input,
    vertex_shader,
    early_fragment_tests,
    fragment_shader,
    late_fragment_tests,
    color_attachment_output,
    compute_shader,
    clear,
    copy,
    host,

    pub const Flags = ngl.Flags(Stage);
};

pub const Access = enum {
    none,
    memory_read,
    memory_write,
    indirect_command_read,
    index_read,
    vertex_attribute_read,
    uniform_read,
    input_attachment_read,
    shader_sampled_read,
    shader_storage_read,
    shader_storage_write,
    color_attachment_read,
    color_attachment_write,
    depth_stencil_attachment_read,
    depth_stencil_attachment_write,
    transfer_read,
    transfer_write,
    host_read,
    host_write,

    pub const Flags = ngl.Flags(Access);
};

pub const Fence = struct {
    impl: Impl.Fence,

    pub const Status = enum {
        unsignaled,
        signaled,
    };

    pub const Desc = struct {
        status: Status,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initFence(allocator, device.impl, desc) };
    }

    pub fn reset(allocator: std.mem.Allocator, device: *Device, fences: []const *Self) Error!void {
        try Impl.get().resetFences(allocator, device.impl, fences);
    }

    pub fn wait(
        allocator: std.mem.Allocator,
        device: *Device,
        timeout: u64,
        fences: []const *Self,
    ) Error!void {
        try Impl.get().waitFences(allocator, device.impl, timeout, fences);
    }

    pub fn getStatus(self: *Self, device: *Device) Error!Status {
        return Impl.get().getFenceStatus(device.impl, self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitFence(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const Semaphore = struct {
    impl: Impl.Semaphore,

    pub const Desc = struct {};

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSemaphore(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitSemaphore(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
