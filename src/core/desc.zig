const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Sampler = ngl.Sampler;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const DescriptorType = enum {
    sampler,
    combined_image_sampler,
    sampled_image,
    storage_image,
    uniform_texel_buffer,
    storage_texel_buffer,
    uniform_buffer,
    storage_buffer,
    input_attachment,
};

pub const DescriptorSetLayout = struct {
    impl: *Impl.DescriptorSetLayout,

    // TODO: Allowed pipeline stages
    pub const Binding = struct {
        binding: u32,
        type: DescriptorType,
        count: u32,
        immutable_samplers: ?[]const *const Sampler,
    };

    pub const Desc = struct {
        bindings: ?[]const Binding,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initDescriptorSetLayout(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitDescriptorSetLayout(allocator, device.impl, self.impl);
    }
};

// TODO: Allowed pipeline stages
pub const PushConstantRange = struct {
    offset: u16,
    size: u16,
};

pub const PipelineLayout = struct {
    impl: *Impl.PipelineLayout,

    pub const Desc = struct {
        descriptor_set_layouts: ?[]const *const DescriptorSetLayout,
        push_constant_ranges: ?[]const PushConstantRange,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initPipelineLayout(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitPipelineLayout(allocator, device.impl, self.impl);
    }
};
