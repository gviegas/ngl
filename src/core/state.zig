const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Format = ngl.Format;
const SampleCount = ngl.SampleCount;
const CompareOp = ngl.CompareOp;
const RenderPass = ngl.RenderPass;
const PipelineLayout = ngl.PipelineLayout;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Pipeline = struct {
    impl: Impl.Pipeline,
    type: Type,

    pub const Type = enum {
        graphics,
        compute,
    };

    pub fn Desc(comptime T: type) type {
        if (T != GraphicsState and T != ComputeState)
            @compileError("T must be a pipeline state type");
        return struct {
            states: []const T,
            cache: ?*PipelineCache,
        };
    }

    const Self = @This();

    /// Caller is responsible for freeing the returned slice.
    pub fn initGraphics(
        allocator: std.mem.Allocator,
        device: *Device,
        desc: Desc(GraphicsState),
    ) Error![]Pipeline {
        const pipelines = try allocator.alloc(Pipeline, desc.states.len);
        errdefer allocator.free(pipelines);
        if (@typeInfo(Self).Struct.fields.len > 2) @compileError("Initialize the new field(s)");
        for (pipelines) |*pl| pl.type = .graphics;
        try Impl.get().initPipelinesGraphics(allocator, device.impl, desc, pipelines);
        return pipelines;
    }

    /// Caller is responsible for freeing the returned slice.
    pub fn initCompute(
        allocator: std.mem.Allocator,
        device: *Device,
        desc: Desc(ComputeState),
    ) Error![]Pipeline {
        const pipelines = try allocator.alloc(Pipeline, desc.states.len);
        errdefer allocator.free(pipelines);
        if (@typeInfo(Self).Struct.fields.len > 2) @compileError("Initialize the new field(s)");
        for (pipelines) |*pl| pl.type = .compute;
        try Impl.get().initPipelinesCompute(allocator, device.impl, desc, pipelines);
        return pipelines;
    }

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
        stage: ShaderStage,
        code: []align(4) const u8,
        name: [:0]const u8,
        specialization: ?Specialization = null,
    };
};

pub const Primitive = struct {
    bindings: []const Binding,
    attributes: []const Attribute,
    topology: Topology,
    restart: bool = false,

    pub const Binding = struct {
        binding: u32,
        stride: u32,
        step_rate: union(enum) {
            vertex,
            instance: u1, // This must be `1` currently
        },
    };

    pub const Attribute = struct {
        location: u32,
        binding: u32,
        format: Format,
        offset: u32,
    };

    pub const Topology = enum {
        point_list,
        line_list,
        line_strip,
        triangle_list,
        triangle_strip,
    };
};

pub const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    near: f32,
    far: f32,
    scissor: ?struct {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    } = null,
};

pub const Rasterization = struct {
    polygon_mode: PolygonMode,
    cull_mode: CullMode,
    clockwise: bool,
    /// `Feature.core.rasterization.depth_clamp`.
    depth_clamp: bool = false,
    depth_bias: ?struct {
        value: f32,
        slope: f32,
        /// `Feature.core.rasterization.depth_bias_clamp`.
        clamp: ?f32,
    } = null,
    samples: SampleCount,
    sample_mask: u64 = ~@as(u64, 0),
    alpha_to_coverage: bool = false,
    /// `Feature.core.rasterization.alpha_to_one`.
    alpha_to_one: bool = false,

    pub const PolygonMode = enum {
        fill,
        line,
    };

    pub const CullMode = enum {
        none,
        front,
        back,
    };
};

pub const DepthStencil = struct {
    depth_compare: ?CompareOp,
    depth_write: bool,
    stencil_front: ?StencilTest,
    stencil_back: ?StencilTest,

    pub const StencilTest = struct {
        fail_op: StencilOp,
        pass_op: StencilOp,
        depth_fail_op: StencilOp,
        compare: CompareOp,
        read_mask: u32,
        write_mask: u32,
        reference: ?u32,
    };

    pub const StencilOp = enum {
        keep,
        zero,
        replace,
        increment_clamp,
        decrement_clamp,
        invert,
        increment_wrap,
        decrement_wrap,
    };
};

pub const ColorBlend = struct {
    /// Must contain identical elements unless
    /// `Feature.core.color_blend.independent_blend`
    /// is supported.
    attachments: []const Attachment,
    constants: union(enum) {
        unused,
        dynamic,
        static: [4]f32,
    },

    pub const Attachment = struct {
        blend: ?BlendEquation,
        write: union(enum) {
            all,
            mask: packed struct {
                r: bool,
                g: bool,
                b: bool,
                a: bool,
            },
        },
    };

    pub const BlendEquation = struct {
        color_source_factor: BlendFactor,
        color_dest_factor: BlendFactor,
        color_op: BlendOp,
        alpha_source_factor: BlendFactor,
        alpha_dest_factor: BlendFactor,
        alpha_op: BlendOp,
    };

    pub const BlendFactor = enum {
        zero,
        one,
        source_color,
        one_minus_source_color,
        dest_color,
        one_minus_dest_color,
        source_alpha,
        one_minus_source_alpha,
        dest_alpha,
        one_minus_dest_alpha,
        constant_color,
        one_minus_constant_color,
        constant_alpha,
        one_minus_constant_alpha,
        source_alpha_saturate,
    };

    pub const BlendOp = enum {
        add,
        subtract,
        reverse_subtract,
        min,
        max,
    };
};

pub const GraphicsState = struct {
    stages: []const ShaderStage.Desc,
    layout: *PipelineLayout,
    primitive: ?*const Primitive,
    viewport: ?*const Viewport,
    rasterization: ?*const Rasterization,
    depth_stencil: ?*const DepthStencil,
    color_blend: ?*const ColorBlend,
    render_pass: ?*RenderPass,
    subpass: RenderPass.Index,
};

pub const ComputeState = struct {
    stage: ShaderStage.Desc,
    layout: *PipelineLayout,
};

pub const PipelineCache = struct {
    impl: Impl.PipelineCache,

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
