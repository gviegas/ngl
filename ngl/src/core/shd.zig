const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const DescriptorSetLayout = ngl.DescriptorSetLayout;
const PushConstantRange = ngl.PushConstantRange;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Shader = struct {
    //impl: Impl.Shader,

    // TODO: Add other shader types.
    pub const Type = enum {
        vertex,
        fragment,
        compute,

        pub const Flags = ngl.Flags(Type);
    };

    pub const Specialization = struct {
        constants: []const Constant,
        data: []const u8,

        pub const Constant = struct {
            id: u32,
            offset: u32,
            size: u32,
        };
    };

    pub const Desc = struct {
        type: Type,
        next: Type.Flags,
        code: []align(4) const u8,
        name: [:0]const u8,
        set_layouts: []const *DescriptorSetLayout,
        push_constants: []const PushConstantRange,
        specialization: ?Specialization,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, descs: []const Desc) Error![]?Self {
        _ = allocator;
        _ = device;
        _ = descs;
        @panic("Not yet implemented");
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        _ = self;
        _ = allocator;
        _ = device;
        @panic("Not yet implemented");
    }
};
