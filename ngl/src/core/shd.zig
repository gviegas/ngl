const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const DescriptorSetLayout = ngl.DescriptorSetLayout;
const PushConstantRange = ngl.PushConstantRange;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Shader = struct {
    impl: Impl.Shader,

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
        link: bool,
    };

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        device: *Device,
        descs: []const Desc,
    ) Error![]Error!Self {
        if (descs.len == 0) return &.{};
        const shaders = try allocator.alloc(Error!Self, descs.len);
        errdefer allocator.free(shaders);
        for (shaders) |*shader|
            shader.* = Error.Other;
        try Impl.get().initShader(allocator, device.impl, descs, shaders);
        return shaders;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitShader(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
