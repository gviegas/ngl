const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const RenderPass = ngl.RenderPass;
const PipelineLayout = ngl.PipelineLayout;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Pipeline = struct {
    impl: *Impl.Pipeline,
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
            cache: ?*const PipelineCache,
        };
    }

    const Self = @This();

    pub fn initGraphics(
        allocator: std.mem.Allocator,
        device: *Device,
        desc: Desc(GraphicsState),
    ) Error![]Pipeline {
        var pipelines = try allocator.alloc(Pipeline, desc.states.len);
        errdefer allocator.free(pipelines);
        for (pipelines) |*pl| pl.type = .graphics;
        try Impl.get().initPipelinesGraphics(allocator, device.impl, desc, pipelines);
        return pipelines;
    }

    pub fn initCompute(
        allocator: std.mem.Allocator,
        device: *Device,
        desc: Desc(ComputeState),
    ) Error![]Pipeline {
        var pipelines = try allocator.alloc(Pipeline, desc.states.len);
        errdefer allocator.free(pipelines);
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

    pub const Desc = struct {
        stage: ShaderStage,
        code: []align(4) const u8,
        name: [:0]const u8,
        // TODO: Specialization constants
    };
};

pub const GraphicsState = struct {
    stages: []const ShaderStage.Desc,
    layout: *const PipelineLayout,
    vertex_input: ?VertexInput,
    input_assembly: ?InputAssembly,
    viewport: ?Viewport,
    rasterization: ?Rasterization,
    multisample: ?Multisample,
    depth_stencil: ?DepthStencil,
    color_blend: ?ColorBlend,
    // TODO: Dynamic state
    render_pass: ?*const RenderPass,
    subpass: ?RenderPass.Index,

    pub const VertexInput = struct {
        // TODO
    };

    pub const InputAssembly = struct {
        // TODO
    };

    pub const Viewport = struct {
        // TODO
    };

    pub const Rasterization = struct {
        // TODO
    };

    pub const Multisample = struct {
        // TODO
    };

    pub const DepthStencil = struct {
        // TODO
    };

    pub const ColorBlend = struct {
        // TODO
    };
};

pub const ComputeState = struct {
    stage: ShaderStage.Desc,
    layout: *const PipelineLayout,
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
