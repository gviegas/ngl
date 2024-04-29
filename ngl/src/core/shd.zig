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

pub const ShaderLayout = struct {
    impl: Impl.ShaderLayout,

    pub const Desc = struct {
        set_layouts: []const *DescriptorSetLayout,
        push_constants: []const PushConstantRange,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initShaderLayout(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitShaderLayout(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const DescriptorType = enum {
    sampler,
    combined_image_sampler,
    sampled_image,
    storage_image,
    uniform_texel_buffer,
    storage_texel_buffer,
    uniform_buffer,
    storage_buffer,
    // Not supported currently.
    //input_attachment,
};

pub const DescriptorSetLayout = struct {
    impl: Impl.DescriptorSetLayout,

    pub const Binding = struct {
        binding: u32,
        type: DescriptorType,
        count: u32,
        shader_mask: Shader.Type.Flags,
        immutable_samplers: []const *Sampler,
    };

    pub const Desc = struct {
        bindings: []const Binding,
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
    shader_mask: Shader.Type.Flags,
};

pub const DescriptorPool = struct {
    impl: Impl.DescriptorPool,

    pub const PoolSize = @Type(.{
        .Struct = .{
            .layout = .auto,
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
        try Impl.get().resetDescriptorPool(device.impl, self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitDescriptorPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const DescriptorSet = struct {
    impl: Impl.DescriptorSet,

    pub const Desc = struct {
        // TODO: Layout plus count pairs.
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
            //input_attachment: []const ImageWrite,
        },

        pub const ImageSamplerWrite = struct {
            view: *ImageView,
            layout: Image.Layout,
            // This field must be `null` iff immutable samplers
            // are used.
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
        try Impl.get().writeDescriptorSets(allocator, device.impl, writes);
    }
};
