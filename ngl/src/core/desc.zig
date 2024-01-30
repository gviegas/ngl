const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Buffer = ngl.Buffer;
const BufferView = ngl.BufferView;
const Image = ngl.Image;
const ImageView = ngl.ImageView;
const Sampler = ngl.Sampler;
const ShaderStage = ngl.ShaderStage;
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
    impl: Impl.DescriptorSetLayout,

    pub const Binding = struct {
        binding: u32,
        type: DescriptorType,
        count: u32,
        stage_mask: ShaderStage.Flags,
        immutable_samplers: ?[]const *Sampler,
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
        self.* = undefined;
    }
};

pub const PushConstantRange = struct {
    offset: u16,
    size: u16,
    stage_mask: ShaderStage.Flags,
};

pub const PipelineLayout = struct {
    impl: Impl.PipelineLayout,

    pub const Desc = struct {
        descriptor_set_layouts: ?[]const *DescriptorSetLayout,
        push_constant_ranges: ?[]const PushConstantRange,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initPipelineLayout(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitPipelineLayout(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const DescriptorPool = struct {
    impl: Impl.DescriptorPool,

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

    /// Caller is responsible for freeing the returned slice.
    pub fn alloc(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: DescriptorSet.Desc,
    ) Error![]DescriptorSet {
        std.debug.assert(desc.layouts.len > 0);
        const desc_sets = try allocator.alloc(DescriptorSet, desc.layouts.len);
        errdefer allocator.free(desc_sets);
        // TODO: Update this when adding more fields to `DescriptorSet`
        if (@typeInfo(DescriptorSet).Struct.fields.len > 1) @compileError("Uninitialized field(s)");
        try Impl.get().allocDescriptorSets(allocator, device.impl, self.impl, desc, desc_sets);
        return desc_sets;
    }

    /// Invalidates all descriptor sets allocated from the pool.
    pub fn reset(self: *Self, device: *Device) Error!void {
        return Impl.get().resetDescriptorPool(device.impl, self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitDescriptorPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const DescriptorSet = struct {
    impl: Impl.DescriptorSet,

    pub const Desc = struct {
        // TODO: Layout plus count pairs
        layouts: []const *DescriptorSetLayout,
    };

    pub const Write = struct {
        descriptor_set: *Self,
        binding: u32,
        element: u32,
        contents: union(DescriptorType) {
            sampler: []const *Sampler,
            combined_image_sampler: []const ImageSamplerWrite,
            sampled_image: []const ImageWrite,
            storage_image: []const ImageWrite,
            uniform_texel_buffer: []const *BufferView,
            storage_texel_buffer: []const *BufferView,
            uniform_buffer: []const BufferWrite,
            storage_buffer: []const BufferWrite,
            input_attachment: []const ImageWrite,
        },

        pub const ImageSamplerWrite = struct {
            view: *ImageView,
            layout: Image.Layout,
            // Must be provided if not using immutable samplers
            sampler: ?*Sampler,
        };

        pub const ImageWrite = struct {
            view: *ImageView,
            layout: Image.Layout,
        };

        pub const BufferWrite = struct {
            buffer: *Buffer,
            offset: u64,
            range: u64,
        };
    };

    const Self = @This();

    pub fn write(allocator: std.mem.Allocator, device: *Device, writes: []const Write) Error!void {
        return Impl.get().writeDescriptorSets(allocator, device.impl, writes);
    }
};
