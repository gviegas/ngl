const std = @import("std");

pub const log = std.log.scoped(.@"ngl|common");

const ngl = @import("../../ngl.zig");
const Cmd = ngl.Cmd;
const Error = ngl.Error;
const Impl = @import("../Impl.zig");

/// Every field of `K` must support default initialization.
fn getInitFn(comptime K: type) (fn () K) {
    return struct {
        fn init() K {
            var self: K = undefined;
            inline for (@typeInfo(K).Struct.fields) |field|
                @field(self, field.name) = .{};
            return self;
        }
    }.init;
}

/// Every field of `K` must either support default initialization
/// or have a `clear` method taking an optional allocator.
fn getClearFn(comptime K: type) (fn (*K, ?std.mem.Allocator) void) {
    return struct {
        fn clear(self: *K, allocator: ?std.mem.Allocator) void {
            inline for (@typeInfo(K).Struct.fields) |field| {
                if (@hasDecl(field.type, "clear"))
                    @field(self, field.name).clear(allocator)
                else
                    @field(self, field.name) = .{};
            }
        }
    }.clear;
}

/// Every field of `K` that cannot be shallow-copied must have
/// both `clone` and `clear` methods that accept any allocator.
fn getCloneFn(comptime K: type) (fn (K, std.mem.Allocator) Error!K) {
    return struct {
        fn clone(self: K, allocator: std.mem.Allocator) Error!K {
            const fields = @typeInfo(K).Struct.fields;
            var cloned: K = undefined;
            inline for (fields, 0..) |field, i| {
                errdefer {
                    inline for (0..i) |j|
                        if (@hasDecl(fields[j].type, "clone"))
                            @field(cloned, fields[j].name).clear(allocator);
                }
                @field(cloned, field.name) = if (@hasDecl(field.type, "clone"))
                    try @field(self, field.name).clone(allocator)
                else
                    @field(self, field.name);
            }
            return cloned;
        }
    }.clone;
}

/// Every field of `K` must have an `eql` method.
fn getEqlFn(comptime K: type) (fn (K, K) bool) {
    return struct {
        fn eql(self: K, other: K) bool {
            inline for (@typeInfo(K).Struct.fields) |field|
                if (!@field(self, field.name).eql(@field(other, field.name)))
                    return false;
            return true;
        }
    }.eql;
}

/// Every field of `K` must have a `hash` (update) method.
fn getHashFn(comptime K: type) (fn (K, hasher: anytype) void) {
    return struct {
        fn hash(self: K, hasher: anytype) void {
            inline for (@typeInfo(K).Struct.fields) |field|
                @field(self, field.name).hash(hasher);
        }
    }.hash;
}

/// The generated function will constrain the comparison to
/// the fields in `mask`, which must be a subset of `K.mask`.
fn getEqlSubsetFn(comptime K: type) (fn (K, comptime mask: @TypeOf(K.mask), K) bool) {
    return struct {
        fn eqlSubset(self: K, comptime mask: @TypeOf(K.mask), other: K) bool {
            comptime {
                const U = @typeInfo(@TypeOf(mask)).Struct.backing_integer.?;
                const m: U = @bitCast(K.mask);
                const n: U = @bitCast(mask);
                if (m & n != n) @compileError("Not a subset");
            }
            inline for (@typeInfo(K).Struct.fields) |field|
                if (@field(mask, field.name))
                    if (!@field(self, field.name).eql(@field(other, field.name)))
                        return false;
            return true;
        }
    }.eqlSubset;
}

/// The generated function will constrain the hash update to
/// the fields in `mask`, which must be a subset of `K.mask`.
fn getHashSubsetFn(comptime K: type) (fn (
    K,
    comptime mask: @TypeOf(K.mask),
    hasher: anytype,
) void) {
    return struct {
        fn hashSubset(self: K, comptime mask: @TypeOf(K.mask), hasher: anytype) void {
            comptime {
                const U = @typeInfo(@TypeOf(mask)).Struct.backing_integer.?;
                const m: U = @bitCast(K.mask);
                const n: U = @bitCast(mask);
                if (m & n != n) @compileError("Not a subset");
            }
            inline for (@typeInfo(K).Struct.fields) |field|
                if (@field(mask, field.name))
                    @field(self, field.name).hash(hasher);
        }
    }.hashSubset;
}

pub fn State(comptime state_mask: anytype) type {
    const M = @TypeOf(state_mask);

    const kind = switch (M) {
        StateMask(.primitive) => .primitive,
        else => @compileError("dyn.State's argument must be of type dyn.StateMask"),
    };

    const getType = struct {
        fn getType(comptime ident: anytype) type {
            const name = @tagName(ident);
            const has = @hasField(M, name) and @field(state_mask, name);
            return switch (ident) {
                .shaders => if (has) Shaders(kind) else None,
                .vertex_input => if (has) VertexInput else None,
                .primitive_topology => if (has) PrimitiveTopology else None,
                .viewport_count => if (has) ViewportCount else None,
                .viewports => if (has) Viewports else None,
                .scissor_rects => if (has) ScissorRects else None,
                .rasterization_enable => if (has) Enable(true) else None,
                .polygon_mode => if (has) PolygonMode else None,
                .cull_mode => if (has) CullMode else None,
                .front_face => if (has) FrontFace else None,
                .sample_count => if (has) SampleCount else None,
                .sample_mask => if (has) SampleMask else None,
                .depth_bias_enable => if (has) Enable(false) else None,
                .depth_bias => if (has) DepthBias else None,
                .depth_test_enable => if (has) Enable(false) else None,
                .depth_compare_op => if (has) DepthCompareOp else None,
                .depth_write_enable => if (has) Enable(false) else None,
                .stencil_test_enable => if (has) Enable(false) else None,
                .stencil_op => if (has) StencilOp else None,
                .stencil_read_mask => if (has) StencilMask else None,
                .stencil_write_mask => if (has) StencilMask else None,
                .stencil_reference => if (has) StencilReference else None,
                .color_blend_enable => if (has) ColorBlendEnable else None,
                .color_blend => if (has) ColorBlend else None,
                .color_write => if (has) ColorWrite else None,
                .blend_constants => if (has) BlendConstants else None,
                else => unreachable,
            };
        }
    }.getType;

    return struct {
        shaders: getType(.shaders),
        vertex_input: getType(.vertex_input),
        primitive_topology: getType(.primitive_topology),
        viewport_count: getType(.viewport_count),
        viewports: getType(.viewports),
        scissor_rects: getType(.scissor_rects),
        rasterization_enable: getType(.rasterization_enable),
        polygon_mode: getType(.polygon_mode),
        cull_mode: getType(.cull_mode),
        front_face: getType(.front_face),
        sample_count: getType(.sample_count),
        sample_mask: getType(.sample_mask),
        depth_bias_enable: getType(.depth_bias_enable),
        depth_bias: getType(.depth_bias),
        depth_test_enable: getType(.depth_test_enable),
        depth_compare_op: getType(.depth_compare_op),
        depth_write_enable: getType(.depth_write_enable),
        stencil_test_enable: getType(.stencil_test_enable),
        stencil_op: getType(.stencil_op),
        stencil_read_mask: getType(.stencil_read_mask),
        stencil_write_mask: getType(.stencil_write_mask),
        stencil_reference: getType(.stencil_reference),
        color_blend_enable: getType(.color_blend_enable),
        color_blend: getType(.color_blend),
        color_write: getType(.color_write),
        blend_constants: getType(.blend_constants),

        pub const mask = state_mask;

        pub const init = getInitFn(@This());
        pub const clear = getClearFn(@This());
        pub const clone = getCloneFn(@This());
        pub const eql = getEqlFn(@This());
        pub const hash = getHashFn(@This());
        pub const eqlSubset = getEqlSubsetFn(@This());
        pub const hashSubset = getHashSubsetFn(@This());
    };
}

pub fn StateMask(comptime kind: enum { primitive }) type {
    const common = [_][:0]const u8{
        // `Cmd.setShaders`.
        "shaders",
    };

    const common_render = [_][:0]const u8{
        // Number of viewports in `Cmd.setViewports`.
        // There's no equivalent for scissor rects
        // because the counts must match.
        "viewport_count",
        // `Cmd.setViewports`.
        "viewports",
        // `Cmd.setScissorRects`.
        "scissor_rects",
        // `Cmd.setRasterizationEnable`.
        "rasterization_enable",
        // `Cmd.setPolygonMode`.
        "polygon_mode",
        // `Cmd.setCullMode`.
        "cull_mode",
        // `Cmd.setFrontFace`.
        "front_face",
        // `Cmd.setSampleCount`.
        "sample_count",
        // `Cmd.setSampleMask`.
        "sample_mask",
        // `Cmd.setDepthBiasEnable`.
        "depth_bias_enable",
        // `Cmd.setDepthBias`.
        "depth_bias",
        // `Cmd.setDepthTestEnable`.
        "depth_test_enable",
        // `Cmd.setDepthCompareOp`.
        "depth_compare_op",
        // `Cmd.setDepthWriteEnable`.
        "depth_write_enable",
        // `Cmd.setStencilTestEnable`.
        "stencil_test_enable",
        // `Cmd.setStencilOp`.
        "stencil_op",
        // `Cmd.setStencilReadMask`.
        "stencil_read_mask",
        // `Cmd.setStencilWriteMask`.
        "stencil_write_mask",
        // `Cmd.setStencilReference`.
        "stencil_reference",
        // `Cmd.setColorBlendEnable`.
        "color_blend_enable",
        // `Cmd.setColorBlend`.
        "color_blend",
        // `Cmd.setColorWrite`.
        "color_write",
        // `Cmd.setBlendConstants`.
        "blend_constants",
    };

    const names = &common ++ switch (kind) {
        .primitive => &[_][:0]const u8{
            // `Cmd.setVertexInput`.
            "vertex_input",
            // `Cmd.setPrimitiveTopology`.
            "primitive_topology",
        } ++ &common_render,
    };

    const StructField = std.builtin.Type.StructField;
    var fields: []const StructField = &[_]StructField{};
    for (names) |name|
        fields = fields ++ &[_]StructField{.{
            .name = name,
            .type = bool,
            .default_value = @ptrCast(&false),
            .is_comptime = false,
            .alignment = 0,
        }};

    return @Type(.{ .Struct = .{
        .layout = .@"packed",
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn Rendering(comptime rendering_mask: RenderingMask) type {
    const getType = struct {
        fn getType(comptime ident: anytype) type {
            const has = @field(rendering_mask, @tagName(ident));
            return switch (ident) {
                .color_view => if (has) ColorView else None,
                .color_format => if (has) ColorFormat else None,
                .color_samples => if (has) ColorSamples else None,
                .color_layout => if (has) ColorLayout else None,
                .color_op => if (has) ColorOp else None,
                .color_clear_value => if (has) ColorClearValue else None,
                .color_resolve_view => if (has) ColorResolveView else None,
                .color_resolve_layout => if (has) ColorResolveLayout else None,
                .color_resolve_mode => if (has) ColorResolveMode else None,
                .depth_view => if (has) DsView(.depth) else None,
                .depth_format => if (has) DsFormat(.depth) else None,
                .depth_samples => if (has) DsSamples(.depth) else None,
                .depth_layout => if (has) DsLayout(.depth) else None,
                .depth_op => if (has) DsOp(.depth) else None,
                .depth_clear_value => if (has) DsClearValue(.depth) else None,
                .depth_resolve_view => if (has) DsResolveView(.depth) else None,
                .depth_resolve_layout => if (has) DsResolveLayout(.depth) else None,
                .depth_resolve_mode => if (has) DsResolveMode(.depth) else None,
                .stencil_view => if (has) DsView(.stencil) else None,
                .stencil_format => if (has) DsFormat(.stencil) else None,
                .stencil_samples => if (has) DsSamples(.stencil) else None,
                .stencil_layout => if (has) DsLayout(.stencil) else None,
                .stencil_op => if (has) DsOp(.stencil) else None,
                .stencil_clear_value => if (has) DsClearValue(.stencil) else None,
                .stencil_resolve_view => if (has) DsResolveView(.stencil) else None,
                .stencil_resolve_layout => if (has) DsResolveLayout(.stencil) else None,
                .stencil_resolve_mode => if (has) DsResolveMode(.stencil) else None,
                .render_area_offset => if (has) RenderAreaOffset else None,
                .render_area_size => if (has) RenderAreaSize else None,
                .layers => if (has) Layers else None,
                .view_mask => if (has) ViewMask else None,
                else => unreachable,
            };
        }
    }.getType;

    return struct {
        color_view: getType(.color_view),
        color_format: getType(.color_format),
        color_samples: getType(.color_samples),
        color_layout: getType(.color_layout),
        color_op: getType(.color_op),
        color_clear_value: getType(.color_clear_value),
        color_resolve_view: getType(.color_resolve_view),
        color_resolve_layout: getType(.color_resolve_layout),
        color_resolve_mode: getType(.color_resolve_mode),
        depth_view: getType(.depth_view),
        depth_format: getType(.depth_format),
        depth_samples: getType(.depth_samples),
        depth_layout: getType(.depth_layout),
        depth_op: getType(.depth_op),
        depth_clear_value: getType(.depth_clear_value),
        depth_resolve_view: getType(.depth_resolve_view),
        depth_resolve_layout: getType(.depth_resolve_layout),
        depth_resolve_mode: getType(.depth_resolve_mode),
        stencil_view: getType(.stencil_view),
        stencil_format: getType(.stencil_format),
        stencil_samples: getType(.stencil_samples),
        stencil_layout: getType(.stencil_layout),
        stencil_op: getType(.stencil_op),
        stencil_clear_value: getType(.stencil_clear_value),
        stencil_resolve_view: getType(.stencil_resolve_view),
        stencil_resolve_layout: getType(.stencil_resolve_layout),
        stencil_resolve_mode: getType(.stencil_resolve_mode),
        render_area_offset: getType(.render_area_offset),
        render_area_size: getType(.render_area_size),
        layers: getType(.layers),
        view_mask: getType(.view_mask),

        pub const mask = rendering_mask;

        pub const init = getInitFn(@This());
        pub const clear = getClearFn(@This());
        pub const clone = getCloneFn(@This());
        pub const eql = getEqlFn(@This());
        pub const hash = getHashFn(@This());
        pub const eqlSubset = getEqlSubsetFn(@This());
        pub const hashSubset = getHashSubsetFn(@This());

        /// Every field must have a `set` method that takes a
        /// `Cmd.Rendering` as parameter and returns nothing.
        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            inline for (@typeInfo(@This()).Struct.fields) |field|
                if (field.type != None)
                    @field(self, field.name).set(rendering);
        }
    };
}

pub const RenderingMask = packed struct {
    // `Cmd.Rendering.colors`.
    color_view: bool = false,
    color_format: bool = false,
    color_samples: bool = false,
    color_layout: bool = false,
    color_op: bool = false,
    color_clear_value: bool = false,
    color_resolve_view: bool = false,
    color_resolve_layout: bool = false,
    color_resolve_mode: bool = false,
    // `Cmd.Rendering.depth`.
    depth_view: bool = false,
    depth_format: bool = false,
    depth_samples: bool = false,
    depth_layout: bool = false,
    depth_op: bool = false,
    depth_clear_value: bool = false,
    depth_resolve_view: bool = false,
    depth_resolve_layout: bool = false,
    depth_resolve_mode: bool = false,
    // `Cmd.Rendering.stencil`.
    stencil_view: bool = false,
    stencil_format: bool = false,
    stencil_samples: bool = false,
    stencil_layout: bool = false,
    stencil_op: bool = false,
    stencil_clear_value: bool = false,
    stencil_resolve_view: bool = false,
    stencil_resolve_layout: bool = false,
    stencil_resolve_mode: bool = false,
    // `Cmd.Rendering.render_area`.
    render_area_offset: bool = false,
    render_area_size: bool = false,
    // `Cmd.Rendering.layers`.
    layers: bool = false,
    // `Cmd.Rendering.view_mask`.
    view_mask: bool = false,
};

fn getDefaultHashFn(comptime InnerK: type) (fn (InnerK, hasher: anytype) void) {
    return struct {
        fn hash(key: InnerK, hasher: anytype) void {
            std.hash.autoHash(hasher, key);
        }
    }.hash;
}

fn getDefaultEqlFn(comptime InnerK: type) (fn (InnerK, InnerK) bool) {
    return struct {
        fn eql(key: InnerK, other: InnerK) bool {
            return std.meta.eql(key, other);
        }
    }.eql;
}

fn approxEql(x: f32, y: f32) bool {
    // TODO: Tune this.
    const tolerance = std.math.floatEps(f32);
    return std.math.approxEqAbs(f32, x, y, tolerance);
}

const None = struct {
    pub fn hash(self: @This(), hasher: anytype) void {
        _ = self;
        _ = hasher;
    }

    pub fn eql(self: @This(), other: @This()) bool {
        _ = self;
        _ = other;
        return true;
    }
};

fn Shaders(comptime kind: enum { primitive }) type {
    return struct {
        shader: switch (kind) {
            .primitive => struct {
                vertex: Impl.Shader = .{ .val = 0 },
                fragment: Impl.Shader = .{ .val = 0 },
            },
        } = .{},

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(
            self: *@This(),
            types: []const ngl.Shader.Type,
            shaders: []const ?*ngl.Shader,
        ) void {
            const dfl = Impl.Shader{ .val = 0 };
            for (types, shaders) |@"type", shader| {
                switch (kind) {
                    .primitive => switch (@"type") {
                        .vertex => self.shader.vertex = if (shader) |x| x.impl else dfl,
                        .fragment => self.shader.fragment = if (shader) |x| x.impl else dfl,
                        else => {},
                    },
                }
            }
        }
    };
}

fn Enable(comptime default: bool) type {
    return struct {
        enable: bool = default,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), enable: bool) void {
            self.enable = enable;
        }
    };
}

const VertexInput = struct {
    bindings: std.ArrayListUnmanaged(Cmd.VertexInputBinding) = .{},
    attributes: std.ArrayListUnmanaged(Cmd.VertexInputAttribute) = .{},

    pub fn hash(self: @This(), hasher: anytype) void {
        for (self.bindings.items) |bind|
            std.hash.autoHash(hasher, bind);
        for (self.attributes.items) |attr|
            std.hash.autoHash(hasher, attr);
    }

    pub fn eql(self: @This(), other: @This()) bool {
        if (self.bindings.items.len != other.bindings.items.len or
            self.attributes.items.len != other.attributes.items.len)
        {
            return false;
        }
        for (self.bindings.items, other.bindings.items) |x, y|
            if (!std.meta.eql(x, y))
                return false;
        for (self.attributes.items, other.attributes.items) |x, y|
            if (!std.meta.eql(x, y))
                return false;
        return true;
    }

    pub fn set(
        self: *@This(),
        allocator: std.mem.Allocator,
        bindings: []const Cmd.VertexInputBinding,
        attributes: []const Cmd.VertexInputAttribute,
    ) Error!void {
        try self.bindings.ensureTotalCapacity(allocator, bindings.len);
        try self.attributes.ensureTotalCapacity(allocator, attributes.len);
        self.bindings.clearRetainingCapacity();
        self.attributes.clearRetainingCapacity();
        self.bindings.appendSliceAssumeCapacity(bindings);
        self.attributes.appendSliceAssumeCapacity(attributes);
    }

    pub fn clear(self: *@This(), allocator: ?std.mem.Allocator) void {
        if (allocator) |x| {
            self.bindings.clearAndFree(x);
            self.attributes.clearAndFree(x);
        } else {
            self.bindings.clearRetainingCapacity();
            self.attributes.clearRetainingCapacity();
        }
    }

    pub fn clone(self: @This(), allocator: std.mem.Allocator) Error!@This() {
        // We do this ourselves because `ArrayListUnmanaged` says
        // to use the same allocator.
        var binds = try @TypeOf(self.bindings).initCapacity(allocator, self.bindings.items.len);
        errdefer binds.deinit(allocator);
        var attrs = try @TypeOf(self.attributes).initCapacity(allocator, self.attributes.items.len);
        binds.appendSliceAssumeCapacity(self.bindings.items);
        attrs.appendSliceAssumeCapacity(self.attributes.items);
        return .{
            .bindings = binds,
            .attributes = attrs,
        };
    }
};

const PrimitiveTopology = struct {
    topology: Cmd.PrimitiveTopology = .triangle_list,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), topology: Cmd.PrimitiveTopology) void {
        self.topology = topology;
    }
};

const ViewportCount = struct {
    count: u32 = 0,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), viewports: []const Cmd.Viewport) void {
        self.count = @intCast(viewports.len);
    }
};

const Viewports = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const ScissorRects = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const PolygonMode = struct {
    polygon_mode: Cmd.PolygonMode = .fill,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), polygon_mode: Cmd.PolygonMode) void {
        self.polygon_mode = polygon_mode;
    }
};

const CullMode = struct {
    cull_mode: Cmd.CullMode = .back,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), cull_mode: Cmd.CullMode) void {
        self.cull_mode = cull_mode;
    }
};

const FrontFace = struct {
    front_face: Cmd.FrontFace = .clockwise,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), front_face: Cmd.FrontFace) void {
        self.front_face = front_face;
    }
};

const SampleCount = struct {
    sample_count: ngl.SampleCount = .@"1",

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), sample_count: ngl.SampleCount) void {
        self.sample_count = sample_count;
    }
};

const SampleMask = struct {
    sample_mask: u64 = ~@as(u64, 0),

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), sample_mask: u64) void {
        self.sample_mask = sample_mask;
    }
};

const DepthBias = struct {
    value: f32 = 0,
    slope: f32 = 0,
    clamp: f32 = 0,

    pub fn hash(self: @This(), hasher: anytype) void {
        _ = self;
        _ = hasher;
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return approxEql(self.value, other.value) and
            approxEql(self.slope, other.slope) and
            approxEql(self.clamp, other.clamp);
    }

    pub fn set(self: *@This(), value: f32, slope: f32, clamp: f32) void {
        self.value = value;
        self.slope = slope;
        self.clamp = clamp;
    }
};

const DepthCompareOp = struct {
    compare_op: ngl.CompareOp = .never,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), compare_op: ngl.CompareOp) void {
        self.compare_op = compare_op;
    }
};

const StencilOp = struct {
    front: Op = .{},
    back: Op = .{},

    pub const Op = struct {
        fail_op: Cmd.StencilOp = .keep,
        pass_op: Cmd.StencilOp = .keep,
        depth_fail_op: Cmd.StencilOp = .keep,
        compare_op: ngl.CompareOp = .never,
    };

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(
        self: *@This(),
        stencil_face: Cmd.StencilFace,
        fail_op: Cmd.StencilOp,
        pass_op: Cmd.StencilOp,
        depth_fail_op: Cmd.StencilOp,
        compare_op: ngl.CompareOp,
    ) void {
        const op = Op{
            .fail_op = fail_op,
            .pass_op = pass_op,
            .depth_fail_op = depth_fail_op,
            .compare_op = compare_op,
        };
        switch (stencil_face) {
            .front => self.front = op,
            .back => self.back = op,
            .front_and_back => {
                self.front = op;
                self.back = op;
            },
        }
    }
};

const StencilMask = struct {
    front: u32 = 0,
    back: u32 = 0,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), stencil_face: Cmd.StencilFace, mask: u32) void {
        switch (stencil_face) {
            .front => self.front = mask,
            .back => self.back = mask,
            .front_and_back => {
                self.front = mask;
                self.back = mask;
            },
        }
    }
};

const StencilReference = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const max_color_attachment = Cmd.max_color_attachment;

comptime {
    if (max_color_attachment > 16)
        @compileError("May want to use dynamic allocation in this case");
}

const ColorBlendEnable = struct {
    enable: [max_color_attachment]bool = [_]bool{false} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(
        self: *@This(),
        first_attachment: Cmd.ColorAttachmentIndex,
        enable: []const bool,
    ) void {
        @memcpy(
            self.enable[first_attachment .. first_attachment + enable.len],
            enable,
        );
    }
};

const ColorBlend = struct {
    blend: [max_color_attachment]Cmd.Blend = [_]Cmd.Blend{.{}} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(
        self: *@This(),
        first_attachment: Cmd.ColorAttachmentIndex,
        blend: []const Cmd.Blend,
    ) void {
        @memcpy(
            self.blend[first_attachment .. first_attachment + blend.len],
            blend,
        );
    }
};

const ColorWrite = struct {
    write_masks: [max_color_attachment]Cmd.ColorMask =
        [_]Cmd.ColorMask{.all} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(
        self: *@This(),
        first_attachment: Cmd.ColorAttachmentIndex,
        write_masks: []const Cmd.ColorMask,
    ) void {
        const dest = self.write_masks[first_attachment .. first_attachment + write_masks.len];
        @memcpy(dest, write_masks);
        for (dest) |*write_mask|
            switch (write_mask.*) {
                .all => {},
                .mask => |x| {
                    const U = @typeInfo(@TypeOf(x)).Struct.backing_integer.?;
                    if (@as(U, @bitCast(x)) == ~@as(U, 0))
                        write_mask.* = .all;
                },
            };
    }
};

const BlendConstants = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const ColorView = struct {
    views: [max_color_attachment]Impl.ImageView =
        [_]Impl.ImageView{.{ .val = 0 }} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.views[0..rendering.colors.len], rendering.colors) |*impl, attach|
            impl.* = attach.view.impl;
        @memset(self.views[rendering.colors.len..], .{ .val = 0 });
    }
};

const ColorFormat = struct {
    formats: [max_color_attachment]ngl.Format = [_]ngl.Format{.unknown} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.formats[0..rendering.colors.len], rendering.colors) |*format, attach|
            format.* = attach.view.format;
        @memset(self.formats[rendering.colors.len..], .unknown);
    }
};

const ColorSamples = struct {
    sample_counts: [max_color_attachment]ngl.SampleCount =
        [_]ngl.SampleCount{.@"1"} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.sample_counts[0..rendering.colors.len], rendering.colors) |*count, attach|
            count.* = attach.view.samples;
        @memset(self.sample_counts[rendering.colors.len..], .@"1");
    }
};

const ColorLayout = struct {
    layouts: [max_color_attachment]ngl.Image.Layout =
        [_]ngl.Image.Layout{.unknown} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.layouts[0..rendering.colors.len], rendering.colors) |*layout, attach|
            layout.* = attach.layout;
        @memset(self.layouts[rendering.colors.len..], .unknown);
    }
};

const ColorOp = struct {
    load: [max_color_attachment]Cmd.LoadOp = [_]Cmd.LoadOp{.dont_care} ** max_color_attachment,
    store: [max_color_attachment]Cmd.StoreOp = [_]Cmd.StoreOp{.dont_care} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        const n = rendering.colors.len;
        for (self.load[0..n], self.store[0..n], rendering.colors) |*load, *store, attach| {
            load.* = attach.load_op;
            store.* = attach.store_op;
        }
        @memset(self.load[n..], .dont_care);
        @memset(self.store[n..], .dont_care);
    }
};

const ColorClearValue = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const ColorResolveView = struct {
    views: [max_color_attachment]Impl.ImageView =
        [_]Impl.ImageView{.{ .val = 0 }} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.views[0..rendering.colors.len], rendering.colors) |*impl, attach|
            impl.* = if (attach.resolve) |x| x.view.impl else .{ .val = 0 };
        @memset(self.views[rendering.colors.len..], .{ .val = 0 });
    }
};

const ColorResolveLayout = struct {
    layouts: [max_color_attachment]ngl.Image.Layout =
        [_]ngl.Image.Layout{.unknown} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.layouts[0..rendering.colors.len], rendering.colors) |*layout, attach|
            layout.* = if (attach.resolve) |x| x.layout else .unknown;
        @memset(self.layouts[rendering.colors.len..], .unknown);
    }
};

const ColorResolveMode = struct {
    resolve_modes: [max_color_attachment]Cmd.ResolveMode =
        [_]Cmd.ResolveMode{.average} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.resolve_modes[0..rendering.colors.len], rendering.colors) |*mode, attach|
            mode.* = if (attach.resolve) |x| x.mode else .average;
        @memset(self.resolve_modes[rendering.colors.len..], .average);
    }
};

fn DsView(comptime aspect: enum { depth, stencil }) type {
    return struct {
        view: Impl.ImageView = .{ .val = 0 },

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            self.view = if (@field(rendering, @tagName(aspect))) |x| x.view.impl else .{ .val = 0 };
        }
    };
}

fn DsFormat(comptime aspect: enum { depth, stencil }) type {
    return struct {
        format: ngl.Format = .unknown,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            self.format = if (@field(rendering, @tagName(aspect))) |x| x.view.format else .unknown;
        }
    };
}

fn DsSamples(comptime aspect: enum { depth, stencil }) type {
    return struct {
        sample_count: ngl.SampleCount = .@"1",

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            self.sample_count =
                if (@field(rendering, @tagName(aspect))) |x| x.view.samples else .@"1";
        }
    };
}

fn DsLayout(comptime aspect: enum { depth, stencil }) type {
    return struct {
        layout: ngl.Image.Layout = .unknown,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            self.layout = if (@field(rendering, @tagName(aspect))) |x| x.layout else .unknown;
        }
    };
}

fn DsOp(comptime aspect: enum { depth, stencil }) type {
    return struct {
        load: Cmd.LoadOp = .dont_care,
        store: Cmd.StoreOp = .dont_care,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            if (@field(rendering, @tagName(aspect))) |x| {
                self.load = x.load_op;
                self.store = x.store_op;
            } else {
                self.load = .dont_care;
                self.store = .dont_care;
            }
        }
    };
}

fn DsClearValue(comptime _: enum { depth, stencil }) type {
    comptime {
        @compileError("Shouldn't be necessary");
    }
}

fn DsResolveView(comptime aspect: enum { depth, stencil }) type {
    return struct {
        view: Impl.ImageView = .{ .val = 0 },

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            if (@field(rendering, @tagName(aspect))) |x|
                if (x.resolve) |y| {
                    self.view = y.view.impl;
                    return;
                };
            self.view = .{ .val = 0 };
        }
    };
}

fn DsResolveLayout(comptime aspect: enum { depth, stencil }) type {
    return struct {
        layout: ngl.Image.Layout = .unknown,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            if (@field(rendering, @tagName(aspect))) |x|
                if (x.resolve) |y| {
                    self.layout = y.layout;
                    return;
                };
            self.layout = .unknown;
        }
    };
}

fn DsResolveMode(comptime aspect: enum { depth, stencil }) type {
    return struct {
        resolve_mode: Cmd.ResolveMode = .sample_zero,

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
            if (@field(rendering, @tagName(aspect))) |x|
                if (x.resolve) |y| {
                    self.resolve_mode = y.mode;
                    return;
                };
            self.resolve_mode = .sample_zero;
        }
    };
}

const RenderAreaOffset = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const RenderAreaSize = struct {
    width: u32 = 0,
    height: u32 = 0,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        self.width = rendering.render_area.width;
        self.height = rendering.render_area.height;
    }
};

const Layers = struct {
    layers: u32 = 0,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        self.layers = rendering.layers;
    }
};

const ViewMask = struct {
    view_mask: u32 = 0,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        self.view_mask = rendering.view_mask;
    }
};

const testing = std.testing;

fn hashT(value: anytype) u64 {
    switch (@TypeOf(@TypeOf(value).mask)) {
        StateMask(.primitive), RenderingMask => {},
        else => unreachable,
    }
    var hasher = std.hash.Wyhash.init(0);
    value.hash(&hasher);
    return hasher.final();
}

fn expectEql(key: anytype, hash: u64, other_key: @TypeOf(key)) !void {
    const other_hash = hashT(other_key);
    try testing.expect(hash == other_hash and hash != 0);
    try testing.expect(key.eql(other_key));
    try testing.expect(other_key.eql(key));
}

fn expectNotEql(key: anytype, hash: u64, other_key: @TypeOf(key)) !void {
    const other_hash = hashT(other_key);
    try testing.expect(hash != 0 and other_hash != 0);
    if (hash == other_hash) log.warn("Hash value clash", .{});
    try testing.expect(!key.eql(other_key));
    try testing.expect(!other_key.eql(key));
}

test State {
    const P = State(StateMask(.primitive){
        .shaders = true,
        .vertex_input = true,
        .primitive_topology = true,
        .viewport_count = true,
        .viewports = false,
        .scissor_rects = false,
        .rasterization_enable = true,
        .polygon_mode = true,
        .cull_mode = true,
        .front_face = true,
        .sample_count = true,
        .sample_mask = true,
        .depth_bias_enable = true,
        .depth_bias = true,
        .depth_test_enable = true,
        .depth_compare_op = true,
        .depth_write_enable = true,
        .stencil_test_enable = true,
        .stencil_op = true,
        .stencil_read_mask = true,
        .stencil_write_mask = true,
        .stencil_reference = false,
        .color_blend_enable = true,
        .color_blend = true,
        .color_write = true,
        .blend_constants = false,
    });
    if (@TypeOf(P.init().shaders) != Shaders(.primitive))
        @compileError("Bad dyn.State layout");
    inline for (@typeInfo(@TypeOf(P.mask)).Struct.fields) |field|
        if (@field(P.mask, field.name) and @TypeOf(@field(P.init(), field.name)) == None)
            @compileError("Bad dyn.State layout");

    // TODO: Consider disallowing this case.
    const X = State(StateMask(.primitive){});
    if (@sizeOf(X) != 0)
        @compileError("Bad dyn.State layout");

    inline for (.{ P, X }) |T| {
        const a = T.init();
        const b = T.init();
        try expectEql(a, hashT(a), b);
    }

    var shaders: [2]ngl.Shader = .{
        .{ .impl = .{ .val = 1 } },
        .{ .impl = .{ .val = 2 } },
    };
    inline for (
        .{P},
        .{.{
            &[_]ngl.Shader.Type{ .fragment, .vertex },
            &[_]*ngl.Shader{ &shaders[0], &shaders[1] },
        }},
    ) |T, params| {
        var a = T.init();
        var b = T.init();
        var hb = hashT(b);

        a.shaders.set(params[0], params[1]);
        try expectNotEql(b, hb, a);

        a.shaders = .{};
        try expectEql(b, hb, a);

        for (params[0], params[1]) |t, s| {
            a.shaders.set(&.{t}, &.{s});
            try expectNotEql(b, hb, a);
            b.shaders.set(&.{t}, &.{s});
            hb = hashT(b);
        }
        try expectEql(b, hb, a);

        a.shaders = .{};
        try expectNotEql(b, hb, a);
        var p0 = params[0].*;
        std.mem.reverse(ngl.Shader.Type, &p0);
        a.shaders.set(&p0, params[1]);
        try if (p0.len > 1) expectNotEql(b, hb, a) else expectEql(b, hb, a);
        var p1 = params[1].*;
        std.mem.reverse(*ngl.Shader, &p1);
        a.shaders.set(&p0, &p1);
        try expectEql(b, hb, a);
    }

    const s0 = P.init();
    const h0 = hashT(s0);
    var s1 = P.init();
    defer s1.clear(testing.allocator);
    var h1: u64 = undefined;
    var s2 = P.init();
    defer s2.clear(testing.allocator);

    try s1.vertex_input.set(testing.allocator, &.{.{
        .binding = 0,
        .stride = 12,
        .step_rate = .vertex,
    }}, &.{.{
        .location = 0,
        .binding = 0,
        .format = .rgb32_sfloat,
        .offset = 0,
    }});
    h1 = hashT(s1);
    try expectNotEql(s0, h0, s1);

    try s2.vertex_input.set(testing.allocator, s1.vertex_input.bindings.items, &.{});
    try expectNotEql(s0, h0, s2);
    try expectNotEql(s1, h1, s2);
    try s2.vertex_input.set(
        testing.allocator,
        s1.vertex_input.bindings.items,
        s1.vertex_input.attributes.items,
    );
    try expectNotEql(s0, h0, s2);
    try expectEql(s1, h1, s2);

    s2.vertex_input.bindings.items[0].binding +%= 1;
    try expectNotEql(s0, h0, s2);
    try expectNotEql(s1, h1, s2);
    s1.primitive_topology.set(.line_list);
    h1 = hashT(s1);
    s2.vertex_input.bindings.items[0].binding -%= 1;
    try expectNotEql(s1, h1, s2);
    s2.primitive_topology.set(.line_list);
    try expectEql(s1, h1, s2);

    s1.vertex_input.clear(testing.allocator);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.vertex_input.clear(testing.allocator);
    try expectEql(s1, h1, s2);

    s2.viewport_count.set(&.{.{
        .x = 0,
        .y = 0,
        .width = 1,
        .height = 1,
        .znear = 0,
        .zfar = 1,
    }});
    try expectNotEql(s1, h1, s2);
    s1.viewport_count.set(&.{.{
        .x = 256,
        .y = 256,
        .width = 256,
        .height = 256,
        .znear = 1,
        .zfar = 0,
    }});
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.rasterization_enable.set(false);
    try expectNotEql(s1, h1, s2);
    s1.rasterization_enable.set(false);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.polygon_mode.set(.line);
    try expectNotEql(s1, h1, s2);
    s1.polygon_mode.set(.line);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.cull_mode.set(.front);
    try expectNotEql(s1, h1, s2);
    s1.cull_mode.set(.front);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.front_face.set(.counter_clockwise);
    try expectNotEql(s1, h1, s2);
    s1.front_face.set(.counter_clockwise);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.sample_count.set(.@"4");
    try expectNotEql(s1, h1, s2);
    s1.sample_count.set(.@"4");
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.sample_mask.set(0b1111);
    try expectNotEql(s1, h1, s2);
    s1.sample_mask.set(0xf);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.depth_bias_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_bias_enable.set(true);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.depth_bias.set(0.01, 2, 0);
    try expectNotEql(s1, h1, s2); // Clash.
    s1.depth_bias.value = 0.01;
    s1.depth_bias.slope = 2;
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.depth_test_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_test_enable.set(true);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.depth_compare_op.set(.less_equal);
    try expectNotEql(s1, h1, s2);
    s1.depth_compare_op.set(.less_equal);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.depth_write_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_write_enable.set(true);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_test_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.stencil_test_enable.set(true);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .invert, .replace, .equal);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s2.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s2.stencil_op.set(.front_and_back, .decrement_clamp, .increment_clamp, .zero, .greater);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.back, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_read_mask.set(.back, 0x80);
    try expectNotEql(s1, h1, s2);
    s1.stencil_read_mask.set(.front, 0x80);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_read_mask.set(.front, 0x80);
    try expectNotEql(s1, h1, s2);
    s1.stencil_read_mask.set(.back, 0x80);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s2.stencil_read_mask.set(.front_and_back, 0x80);
    try expectEql(s1, h1, s2);
    s2.stencil_read_mask.set(.front_and_back, 0x1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_read_mask.set(.front, 0x80);
    try expectNotEql(s1, h1, s2);
    s2.stencil_read_mask.set(.back, 0x80);
    try expectEql(s1, h1, s2);

    s2.stencil_write_mask.set(.front, 0x7f);
    try expectNotEql(s1, h1, s2);
    s1.stencil_write_mask.set(.front, 0x7f);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s1.stencil_write_mask.set(.back, 0x7f);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_write_mask.set(.back, 0x7f);
    try expectEql(s1, h1, s2);
    s1.stencil_write_mask.set(.front_and_back, 0xfe);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_write_mask.set(.front_and_back, 0xfe);
    try expectEql(s1, h1, s2);

    s2.color_blend_enable.set(1, &.{});
    try expectEql(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{true});
    try expectNotEql(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{false});
    try expectEql(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{false});
    try expectEql(s1, h1, s2);
    s1.color_blend_enable.set(2, &.{true});
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_blend_enable.set(1, &.{true});
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{ true, true });
    try expectEql(s1, h1, s2);

    s2.color_blend.set(2, &.{});
    try expectEql(s1, h1, s2);
    s2.color_blend.set(2, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(1, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(1, &[_]Cmd.Blend{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }} ** 3);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.color_blend.set(1, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(3, &.{.{}});
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s1.color_blend.set(2, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .dest_color,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s2.color_blend = .{};
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(0, &[_]Cmd.Blend{.{}} ** max_color_attachment);
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    s2.color_write.set(0, &.{});
    try expectEql(s1, h1, s2);
    s2.color_write.set(1, &.{});
    try expectEql(s1, h1, s2);
    s2.color_write.set(1, &.{.all});
    try expectEql(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s1.color_write.set(1, &.{ .all, .{ .mask = .{ .r = true, .g = true, .b = true, .a = true } } });
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s1.color_write.set(2, &.{.all});
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);
    s2.color_write.set(2, &.{.{ .mask = .{ .r = true } }});
    try expectNotEql(s1, h1, s2);
    s2.color_write.set(1, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** (max_color_attachment - 1));
    try expectNotEql(s1, h1, s2);
    s1.color_write.set(0, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** max_color_attachment);
    h1 = hashT(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = hashT(s1);
    try expectEql(s1, h1, s2);

    var cloned = try s1.clone(testing.allocator);
    defer cloned.clear(testing.allocator);
    try expectEql(s1, h1, cloned);
    try cloned.vertex_input.set(testing.allocator, &.{.{
        .binding = 0,
        .stride = 16,
        .step_rate = .vertex,
    }}, &.{.{
        .location = 1,
        .binding = 0,
        .format = .rgba32_sfloat,
        .offset = 0,
    }});
    try expectNotEql(s1, h1, cloned);
    var cloned_2 = try cloned.clone(testing.allocator);
    defer cloned_2.clear(testing.allocator);
    try expectEql(cloned, hashT(cloned), cloned_2);
    cloned_2.vertex_input.clear(testing.allocator);
    try expectNotEql(cloned, hashT(cloned), cloned_2);
    comptime if (!@hasDecl(VertexInput, "clone")) unreachable;
    try testing.expectError(error.OutOfMemory, cloned.clone(testing.failing_allocator));

    comptime var m = P.mask;
    m.color_blend = false;
    s2.color_blend.set(1, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .dest_color,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    try expectNotEql(s1, h1, s2);
    try testing.expect(s1.eqlSubset(m, s2));
    try testing.expect(s2.eqlSubset(m, s1));
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        s1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } != h1);
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        s1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } == blk: {
        var hasher = std.hash.Wyhash.init(0);
        s2.hashSubset(m, &hasher);
        break :blk hasher.final();
    });
    if (false) {
        m.viewports = true;
        // error: Not a subset
    }
    m.color_blend = true;
    try testing.expect(!s1.eqlSubset(m, s2));
    try testing.expect(!s2.eqlSubset(m, s1));
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        s1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } == h1);
}

test Rendering {
    const U = @typeInfo(RenderingMask).Struct.backing_integer.?;

    const R = Rendering(.{
        .color_view = true,
        .color_format = true,
        .color_samples = true,
        .color_layout = true,
        .color_op = true,
        .color_clear_value = false,
        .color_resolve_view = true,
        .color_resolve_layout = true,
        .color_resolve_mode = true,
        .depth_view = true,
        .depth_format = true,
        .depth_samples = true,
        .depth_layout = true,
        .depth_op = true,
        .depth_clear_value = false,
        .depth_resolve_view = true,
        .depth_resolve_layout = true,
        .depth_resolve_mode = true,
        .stencil_view = true,
        .stencil_format = true,
        .stencil_samples = true,
        .stencil_layout = true,
        .stencil_op = true,
        .stencil_clear_value = false,
        .stencil_resolve_view = true,
        .stencil_resolve_layout = true,
        .stencil_resolve_mode = true,
        .render_area_offset = false,
        .render_area_size = true,
        .layers = true,
        .view_mask = true,
    });
    inline for (@typeInfo(R).Struct.fields) |field| {
        const has = @field(R.mask, field.name);
        if ((field.type == None and has) or (field.type != None and !has))
            @compileError("Bad dyn.Rendering layout");
    }

    // TODO: Consider disallowing this case.
    const X = Rendering(.{});
    if (@as(U, @bitCast(X.mask)) != @as(U, 0) or @sizeOf(X) != 0)
        @compileError("Bad dyn.Rendering layout");

    const r0 = R.init();
    const h0 = hashT(r0);
    var r1 = R.init();
    var h1: u64 = undefined;
    var r2 = R.init();

    try expectEql(r0, h0, r1);
    try expectEql(r0, h0, r2);
    r1.clear(null);
    r2.clear(testing.allocator);
    try expectEql(r0, h0, r1);
    try expectEql(r0, h0, r2);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    var views = [_]ngl.ImageView{
        .{ .impl = .{ .val = 1 }, .format = .rgba8_unorm, .samples = .@"4" },
        .{ .impl = .{ .val = 2 }, .format = .rgba8_unorm, .samples = .@"1" },
        .{ .impl = .{ .val = 3 }, .format = .rgba16_sfloat, .samples = .@"4" },
        .{ .impl = .{ .val = 4 }, .format = .rgba16_sfloat, .samples = .@"1" },
        .{ .impl = .{ .val = 5 }, .format = .a2bgr10_unorm, .samples = .@"4" },
        .{ .impl = .{ .val = 6 }, .format = .d32_sfloat_s8_uint, .samples = .@"4" },
        .{ .impl = .{ .val = 7 }, .format = .d32_sfloat_s8_uint, .samples = .@"1" },
    };
    const rend_empty = Cmd.Rendering{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 512, .height = 512 },
        .layers = 1,
        .contents = .@"inline",
    };
    const rend = Cmd.Rendering{
        .colors = &.{
            .{
                .view = &views[0],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .color_f32 = .{ 0, 0, 0, 0 } },
                .resolve = .{
                    .view = &views[1],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &views[2],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = .{
                    .view = &views[3],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &views[4],
                .layout = .color_attachment_optimal,
                .load_op = .load,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 0, 0, 0, 0 } },
                .resolve = null,
            },
        },
        .depth = .{
            .view = &views[5],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = .{
                .view = &views[6],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .stencil = .{
            .view = &views[5],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ undefined, 0xff } },
            .resolve = .{
                .view = &views[6],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .render_area = .{ .width = 480, .height = 270 },
        .layers = 1,
        .contents = .@"inline",
    };

    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_view.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r1.color_view = .{};
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    @memset(&r2.color_view.views, views[0].impl);
    try expectNotEql(r1, h1, r2);
    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);

    r2.color_format.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_format.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_format.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r2.color_format = .{};
    try expectNotEql(r1, h1, r2);
    for (r2.color_format.formats[0..rend.colors.len], rend.colors) |*format, attach|
        format.* = attach.view.format;
    try expectEql(r1, h1, r2);

    r2.color_samples.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_samples.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_samples.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    for (r1.color_samples.sample_counts[0..rend.colors.len], rend.colors) |count, attach|
        try testing.expect(count == attach.view.samples);
    for (r1.color_samples.sample_counts[rend.colors.len..]) |count|
        try testing.expect(count == .@"1");

    r2.color_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    for (r1.color_layout.layouts[0..rend.colors.len], rend.colors) |*layout, attach|
        layout.* = attach.layout;
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r1.color_layout.set(rend_empty);
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_layout = .{};
    try expectEql(r1, h1, r2);

    r2.color_op.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_op.set(rend);
    try expectNotEql(r1, h1, r2);
    for (0..rend.colors.len) |i| {
        r1.color_op.load[i] = rend.colors[i].load_op;
        r1.color_op.store[i] = rend.colors[i].store_op;
    }
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    @memset(&r2.color_op.store, .dont_care);
    try expectNotEql(r1, h1, r2);
    r1.color_op = .{};
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    @memset(&r2.color_op.load, .dont_care);
    try expectEql(r1, h1, r2);

    r2.color_resolve_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_resolve_view.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_resolve_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r1.color_resolve_view = .{};
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_resolve_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    @memset(&r2.color_resolve_view.views, views[1].impl);
    try expectNotEql(r1, h1, r2);
    r2.color_resolve_view.set(rend_empty);
    try expectEql(r1, h1, r2);

    r2.color_resolve_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_resolve_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    for (r1.color_resolve_layout.layouts[0..rend.colors.len], rend.colors) |*layout, attach|
        layout.* = if (attach.resolve) |x| x.layout else .unknown;
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r1.color_resolve_layout.set(rend_empty);
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_resolve_layout = .{};
    try expectEql(r1, h1, r2);

    r2.color_resolve_mode.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_resolve_mode.set(rend);
    try expectEql(r1, h1, r2);
    r2.color_resolve_mode.resolve_modes[1] = .min;
    try expectNotEql(r1, h1, r2);
    r2.color_resolve_mode = .{};
    try expectEql(r1, h1, r2);

    r2.depth_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_view.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_view.eql(r1.stencil_view));
    r1.depth_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_view.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_view.eql(r1.depth_view));
    r1.stencil_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_format.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_format.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_format.eql(r1.stencil_format));
    r1.depth_format.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_format.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_format.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_format.eql(r1.depth_format));
    r1.stencil_format.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_samples.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_samples.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_samples.eql(r1.stencil_samples));
    r1.depth_samples.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_samples.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_samples.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_samples.eql(r1.depth_samples));
    r1.stencil_samples.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_layout.eql(r1.stencil_layout));
    r1.depth_layout.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_layout.eql(r1.depth_layout));
    r1.stencil_layout.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_op.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_op.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_op.eql(r1.stencil_op));
    r1.depth_op.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_op.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_op.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_op.eql(r1.depth_op));
    r1.stencil_op.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_resolve_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_resolve_view.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_resolve_view.eql(r1.stencil_resolve_view));
    r1.depth_resolve_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_resolve_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_resolve_view.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_resolve_view.eql(r1.depth_resolve_view));
    r1.stencil_resolve_view.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_resolve_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_resolve_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_resolve_layout.eql(r1.stencil_resolve_layout));
    r1.depth_resolve_layout.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.stencil_resolve_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_resolve_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_resolve_layout.eql(r1.depth_resolve_layout));
    r1.stencil_resolve_layout.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);

    r2.depth_resolve_mode.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.depth_resolve_mode.set(rend);
    try expectEql(r1, h1, r2);
    r2.depth_resolve_mode.resolve_mode = .min;
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.stencil_resolve_mode.eql(r1.stencil_resolve_mode));
    r2.depth_resolve_mode = .{};
    try expectEql(r1, h1, r2);

    r2.stencil_resolve_mode.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.stencil_resolve_mode.set(rend);
    try expectEql(r1, h1, r2);
    r2.stencil_resolve_mode.resolve_mode = .min;
    try expectNotEql(r1, h1, r2);
    try testing.expect(r2.depth_resolve_mode.eql(r1.depth_resolve_mode));
    r2.stencil_resolve_mode = .{};
    try expectEql(r1, h1, r2);

    r2.render_area_size.set(rend_empty);
    try expectNotEql(r1, h1, r2);
    r1.render_area_size.set(rend);
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.render_area_size.set(rend);
    try expectEql(r1, h1, r2);

    r2.layers.set(rend_empty);
    try expectNotEql(r1, h1, r2);
    r2.layers.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.layers.set(rend);
    h1 = hashT(r1);
    try expectEql(r1, h1, r2);
    r1.layers.set(.{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1, .height = 1 },
        .layers = 2,
        .contents = .@"inline",
    });
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.layers.layers = 2;
    try expectEql(r1, h1, r2);

    r2.view_mask.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.view_mask.set(rend);
    try expectEql(r1, h1, r2);
    r1.view_mask.set(.{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1, .height = 1 },
        .layers = 0,
        .view_mask = 0x1,
        .contents = .@"inline",
    });
    h1 = hashT(r1);
    try expectNotEql(r1, h1, r2);
    r2.view_mask.view_mask = 0x1;
    try expectEql(r1, h1, r2);

    var cloned = try r1.clone(testing.allocator);
    defer cloned.clear(testing.allocator);
    try expectEql(r1, h1, cloned);
    comptime {
        for (@typeInfo(R).Struct.fields) |field|
            if (@hasDecl(field.type, "clone")) unreachable;
    }
    // Shouldn't fail and shouldn't leak.
    _ = try cloned.clone(testing.failing_allocator);

    comptime var m = R.mask;
    m.color_view = false;
    r2.color_view.set(rend);
    try expectNotEql(r1, h1, r2);
    try testing.expect(r1.eqlSubset(m, r2));
    try testing.expect(r2.eqlSubset(m, r1));
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        r1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } != h1);
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        r1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } == blk: {
        var hasher = std.hash.Wyhash.init(0);
        r2.hashSubset(m, &hasher);
        break :blk hasher.final();
    });
    m.color_view = true;
    try testing.expect(!r1.eqlSubset(m, r2));
    try testing.expect(!r2.eqlSubset(m, r1));
    try testing.expect(blk: {
        var hasher = std.hash.Wyhash.init(0);
        r1.hashSubset(m, &hasher);
        break :blk hasher.final();
    } == h1);

    r1.clear(null);
    try expectEql(r0, h0, r1);
    r1.set(rend);
    try expectNotEql(r0, h0, r1);
    h1 = hashT(r1);
    r2.clear(null);
    inline for (@typeInfo(R).Struct.fields) |field| {
        if (field.type == None) continue;
        @field(r2, field.name).set(rend);
        try testing.expect(@field(r2, field.name).eql(@field(r1, field.name)));
    }
    try expectEql(r1, h1, r2);
}
