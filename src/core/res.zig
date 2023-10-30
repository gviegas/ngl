const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Memory = ngl.Memory;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Format = enum {
    unknown,

    r8_unorm,
    r8_srgb,
    r8_snorm,
    r8_uint,
    r8_sint,
    a8_unorm,
    r4g4_unorm,

    r16_unorm,
    r16_snorm,
    r16_uint,
    r16_sint,
    r16_sfloat,
    rg8_unorm,
    rg8_srgb,
    rg8_snorm,
    rg8_uint,
    rg8_sint,
    rgba4_unorm,
    bgra4_unorm,
    argb4_unorm,
    abgr4_unorm,
    r5g6b5_unorm,
    b5g6r5_unorm,
    rgb5a1_unorm,
    bgr5a1_unorm,
    a1rgb5_unorm,
    a1bgr5_unorm,

    rgb8_unorm,
    rgb8_srgb,
    rgb8_snorm,
    rgb8_uint,
    rgb8_sint,
    bgr8_unorm,
    bgr8_srgb,
    bgr8_snorm,
    bgr8_uint,
    bgr8_sint,

    r32_uint,
    r32_sint,
    r32_sfloat,
    rg16_unorm,
    rg16_snorm,
    rg16_uint,
    rg16_sint,
    rg16_sfloat,
    rgba8_unorm,
    rgba8_srgb,
    rgba8_snorm,
    rgba8_uint,
    rgba8_sint,
    bgra8_unorm,
    bgra8_srgb,
    bgra8_snorm,
    bgra8_uint,
    bgra8_sint,
    rgb10a2_unorm,
    rgb10a2_uint,
    a2rgb10_unorm,
    a2rgb10_uint,
    a2bgr10_unorm,
    a2bgr10_uint,
    bgr10a2_unorm,
    rg11b10_sfloat,
    b10gr11_ufloat,
    rgb9e5_sfloat,
    e5bgr9_ufloat,

    rgb16_unorm,
    rgb16_snorm,
    rgb16_uint,
    rgb16_sint,
    rgb16_sfloat,

    r64_uint,
    r64_sint,
    r64_sfloat,
    rg32_uint,
    rg32_sint,
    rg32_sfloat,
    rgba16_unorm,
    rgba16_snorm,
    rgba16_uint,
    rgba16_sint,
    rgba16_sfloat,

    rgb32_uint,
    rgb32_sint,
    rgb32_sfloat,

    rg64_uint,
    rg64_sint,
    rg64_sfloat,
    rgba32_uint,
    rgba32_sint,
    rgba32_sfloat,

    rgb64_uint,
    rgb64_sint,
    rgb64_sfloat,

    rgba64_uint,
    rgba64_sint,
    rgba64_sfloat,

    d16_unorm,
    x8_d24_unorm,
    d32_sfloat,
    s8_uint,
    d16_unorm_s8_uint,
    d24_unorm_s8_uint,
    d32_sfloat_s8_uint,

    // TODO: Compressed formats
};

pub const Buffer = struct {
    impl: Impl.Buffer,
    //memory: ?Impl.Memory,

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

    pub fn getMemoryRequirements(self: *Self, device: *Device) Memory.Requirements {
        return Impl.get().getMemoryRequirementsBuffer(device.impl, self.impl);
    }

    pub fn bindMemory(
        self: *Self,
        device: *Device,
        memory: *Memory,
        memory_offset: u64,
    ) Error!void {
        return Impl.get().bindMemoryBuffer(device.impl, self.impl, memory.impl, memory_offset);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitBuffer(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const BufferView = struct {
    impl: Impl.BufferView,

    pub const Desc = struct {
        buffer: *Buffer,
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

pub const SampleCount = enum {
    @"1",
    @"2",
    @"4",
    @"8",
    @"16",
    @"32",
    @"64",

    pub const Flags = ngl.Flags(SampleCount);
};

pub const Image = struct {
    impl: Impl.Image,
    //memory: ?Impl.Memory,

    pub const Range = struct {
        aspect_mask: Aspect.Flags,
        base_level: u32,
        levels: ?u32,
        base_layer: u32,
        layers: ?u32,
    };

    pub const Aspect = enum {
        color,
        depth,
        stencil,

        pub const Flags = ngl.Flags(Aspect);
    };

    pub const Layout = enum {
        undefined,
        preinitialized,
        general,
        color_attachment_optimal,
        depth_stencil_attachment_optimal,
        depth_stencil_read_only_optimal,
        shader_read_only_optimal,
        transfer_source_optimal,
        transfer_dest_optimal,
        // Extensions
        present_source__ext,
        shared_present__ext,
    };

    pub const Type = enum {
        @"1d",
        @"2d",
        @"3d",
    };

    pub const Tiling = enum {
        linear,
        optimal,
    };

    pub const Usage = packed struct {
        sampled_image: bool = false,
        storage_image: bool = false,
        color_attachment: bool = false,
        depth_stencil_attachment: bool = false,
        transient_attachment: bool = false,
        input_attachment: bool = false,
        // Be explicit about these
        transfer_source: bool,
        transfer_dest: bool,
    };

    pub const Misc = struct {
        view_formats: ?[]const Format = null,
        cube_compatible: bool = false,
    };

    pub const Desc = struct {
        type: Type,
        format: Format,
        width: u32,
        height: u32,
        depth_or_layers: u32,
        levels: u32,
        samples: SampleCount,
        tiling: Tiling,
        usage: Usage,
        misc: Misc,
        initial_layout: Layout,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initImage(allocator, device.impl, desc) };
    }

    pub fn getMemoryRequirements(self: *Self, device: *Device) Memory.Requirements {
        return Impl.get().getMemoryRequirementsImage(device.impl, self.impl);
    }

    pub fn bindMemory(
        self: *Self,
        device: *Device,
        memory: *Memory,
        memory_offset: u64,
    ) Error!void {
        return Impl.get().bindMemoryImage(device.impl, self.impl, memory.impl, memory_offset);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitImage(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const ImageView = struct {
    impl: Impl.ImageView,

    pub const Type = enum {
        @"1d",
        @"2d",
        @"3d",
        cube,
        @"1d_array",
        @"2d_array",
        cube_array, // Not supported everywhere
    };

    pub const Desc = struct {
        image: *Image,
        type: Type,
        format: Format,
        range: Image.Range,
        // TODO: Swizzle
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initImageView(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitImageView(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const CompareOp = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const Sampler = struct {
    impl: Impl.Sampler,

    pub const AddressMode = enum {
        clamp_to_edge,
        clamp_to_border,
        repeat,
        mirror_repeat,
        // Extensions
        mirror_clamp_to_edge__ext,
    };

    pub const BorderColor = enum {
        transparent_black_float,
        transparent_black_int,
        opaque_black_float,
        opaque_black_int,
        opaque_white_float,
        opaque_white_int,
    };

    pub const Filter = enum {
        nearest,
        linear,
    };

    pub const MipmapMode = enum {
        nearest,
        linear,
    };

    pub const Desc = struct {
        normalized_coordinates: bool,
        u_address: AddressMode,
        v_address: AddressMode,
        w_address: AddressMode,
        border_color: ?BorderColor,
        mag: Filter,
        min: Filter,
        mipmap: MipmapMode,
        min_lod: f32,
        max_lod: ?f32,
        max_anisotropy: ?u5,
        compare: ?CompareOp,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSampler(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitSampler(allocator, device.impl, self.impl);
    }
};
