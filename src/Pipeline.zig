const Device = @import("Device.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.Pipeline;
const PsLayout = @import("PsLayout.zig");
const ShaderCode = @import("ShaderCode.zig");

pub const CompareFn = @import("Sampler.zig").CompareFn;
pub const Format = @import("Texture.zig").Format;

device: *Device,
inner: Inner,
kind: Kind,

pub const Kind = enum {
    render,
    compute,
};

// TODO: Constants (?)
pub const ShaderFn = struct {
    code: *ShaderCode,
    entry_point: []const u8 = "main",
};

pub const DataType = enum {
    f32,
    f32x2,
    f32x3,
    f32x4,
    // TODO...
};

pub const StepMode = enum {
    vertex,
    instance,
};

pub const VbElement = struct {
    location: u32,
    data_type: DataType,
    offset: u64,
};

pub const VbLayout = struct {
    stride: u64,
    step_mode: StepMode,
    elements: []const VbElement,
};

pub const Topology = enum {
    point,
    line,
    line_strip,
    triangle,
    triangle_strip,
};

pub const CullMode = enum {
    none,
    front,
    back,
};

pub const FillMode = enum {
    fill,
    lines,
};

// TODO: Depth clamp (?)
pub const RasterState = struct {
    clockwise: bool = false,
    cull_mode: CullMode = .none,
    fill_mode: FillMode = .fill,
    depth_bias: ?struct {
        value: f32,
        slope: f32,
        clamp: f32,
    } = null,
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

pub const StencilTest = struct {
    fail: StencilOp = .keep,
    depth_fail: StencilOp = .keep,
    pass: StencilOp = .keep,
    read_mask: u32 = 0xff,
    write_mask: u32 = 0xff,
    compare: CompareFn = .always,
};

// TODO: Depth bounds (?)
pub const DsState = struct {
    depth_test: ?struct {
        write: bool = true,
        compare: CompareFn = .less,
    } = null,
    stencil_test: ?struct {
        front: StencilTest = .{},
        back: StencilTest = .{},
    } = null,
};

pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    inverse_src_color,
    src_alpha,
    inverse_src_alpha,
    dest_color,
    inverse_dest_color,
    dest_alpha,
    inverse_dest_alpha,
    src_alpha_saturated,
    blend_color,
    inverse_blend_color,
};

pub const BlendOp = enum {
    add,
    subtract,
    reverse_subtract,
    min,
    max,
};

pub const ColorBlend = struct {
    blend: ?struct {
        color_src: BlendFactor = .one,
        color_dest: BlendFactor = .zero,
        color_op: BlendOp = .add,
        alpha_src: BlendFactor = .one,
        alpha_dest: BlendFactor = .zero,
        alpha_op: BlendOp = .add,
    } = null,
    write: struct {
        r: bool = true,
        g: bool = true,
        b: bool = true,
        a: bool = true,
    },
};

pub const BlendState = struct {
    independent_blend: bool = false,
    color_blend: []const ColorBlend = &.{},
};

pub const RenderPs = struct {
    vs: ShaderFn,
    fs: ?ShaderFn,
    input: []const VbLayout,
    topology: Topology = .triangle,
    viewports: u32 = 1,
    samples: u32 = 1,
    raster: ?RasterState,
    ds: ?DsState,
    blend: ?BlendState,
    color_formats: []const Format,
    ds_format: ?Format,
};

pub const ComputePs = struct {
    cs: ShaderFn,
};

// TODO: It may be better to have separate types for each pipeline.
pub const Config = struct {
    layout: *PsLayout,
    // TODO: Cache, ...
    state: union(Kind) {
        render: *const RenderPs,
        compute: *const ComputePs,
    },
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*);
    self.* = undefined;
}

pub fn impl(self: Self) *const Impl {
    return self.device.impl;
}
