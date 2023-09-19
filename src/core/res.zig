const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const memory = ngl.Memory;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Format = enum {
    // TODO
    rgba8_unorm,
};

pub const Buffer = struct {
    impl: *Impl.Buffer,
    //memory: ?*Impl.Memory,

    pub const Usage = packed struct {
        uniform_texel_buffer: bool = false,
        storage_texel_buffer: bool = false,
        uniform_buffer: bool = false,
        storage_buffer: bool = false,
        index_buffer: bool = false,
        vertex_buffer: bool = false,
        indirect_buffer: bool = false,
        // Be explicit about these
        transfer_source: bool,
        transfer_dest: bool,
    };

    pub const Desc = struct {
        size: u64,
        usage: Usage,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initBuffer(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitBuffer(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const BufferView = struct {
    impl: *Impl.BufferView,

    pub const Desc = struct {
        buffer: *const Buffer,
        format: Format,
        offset: u64,
        range: ?u64,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initBufferView(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitBufferView(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
