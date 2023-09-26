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

pub const DescriptorPool = struct {
    impl: *Impl.DescriptorPool,

    pub const PoolSize = @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = blk: {
                const StructField = std.builtin.Type.StructField;
                var fields: []const StructField = &[_]StructField{};
                for (@typeInfo(DescriptorType).Enum.fields) |f|
                    fields = fields ++ &[1]StructField{.{
                        .name = f.name,
                        .type = u32,
                        .default_value = &@as(u32, 0),
                        .is_comptime = false,
                        .alignment = @alignOf(u32),
                    }};
                break :blk fields;
            },
            .decls = &.{},
            .is_tuple = false,
        },
    });

    pub const Desc = struct {
        max_sets: u32,
        pool_size: PoolSize,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initDescriptorPool(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitDescriptorPool(allocator, device.impl, self.impl);
    }
};
