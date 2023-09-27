const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Pipeline = struct {
    impl: *Impl.Pipeline,
    type: Type,

    pub const Type = enum {
        graphics,
        compute,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitPipeline(allocator, device.impl, self.impl, self.type);
        self.* = undefined;
    }
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    compute,

    pub const Flags = ngl.Flags(ShaderStage);
};

pub const PipelineCache = struct {
    impl: *Impl.PipelineCache,

    pub const Desc = struct {
        initial_data: ?[]const u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initPipelineCache(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitPipelineCache(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
