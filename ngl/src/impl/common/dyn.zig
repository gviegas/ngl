const std = @import("std");

const ngl = @import("../../ngl.zig");
const Cmd = ngl.Cmd;
const Impl = @import("../Impl.zig");

/// Every field of `K` must have `hash` (update) and `eql` methods.
fn HashContext(comptime K: type) type {
    return struct {
        pub fn hash(_: @This(), key: K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            inline for (@typeInfo(K).Struct.fields) |field|
                @field(key, field.name).hash(&hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), key: K, other: K) bool {
            inline for (@typeInfo(K).Struct.fields) |field|
                if (!@field(key, field.name).eql(@field(other, field.name)))
                    return false;
            return true;
        }
    };
}

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

pub fn State(comptime state_mask: anytype) type {
    const M = @TypeOf(state_mask);

    const kind = switch (M) {
        StateMask(.primitive) => .primitive,
        StateMask(.compute) => .compute,
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

        pub const HashCtx = HashContext(@This());

        pub const init = getInitFn(@This());
        pub const clear = getClearFn(@This());
    };
}

pub fn StateMask(comptime kind: enum {
    primitive,
    compute,
}) type {
    const common = [_][:0]const u8{
        // `Cmd.setShaders`.
        "shaders",
    };

    const common_render = [_][:0]const u8{
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
        // `Cmd.setColorBlendEnable.`
        "color_blend_enable",
        // `Cmd.setColorBlend.`
        "color_blend",
        // `Cmd.setColorWrite.`
        "color_write",
        // `Cmd.setBlendConstants.`
        "blend_constants",
    };

    const names = &common ++ switch (kind) {
        .primitive => &[_][:0]const u8{
            // `Cmd.setVertexInput`.
            "vertex_input",
            // `Cmd.setPrimitiveTopology`.
            "primitive_topology",
        } ++ &common_render,
        .compute => &[_][:0]const u8{},
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
            // TODO
            return switch (ident) {
                .color_view => if (has) ColorView else None,
                .color_format => if (has) ColorFormat else None,
                .color_layout => if (has) ColorLayout else None,
                .color_op => if (has) None else None,
                .color_clear_value => if (has) None else None,
                .color_resolve_view => if (has) None else None,
                .color_resolve_layout => if (has) None else None,
                .color_resolve_mode => if (has) None else None,
                .depth_view => if (has) None else None,
                .depth_format => if (has) None else None,
                .depth_layout => if (has) None else None,
                .depth_op => if (has) None else None,
                .depth_clear_value => if (has) None else None,
                .depth_resolve_view => if (has) None else None,
                .depth_resolve_layout => if (has) None else None,
                .depth_resolve_mode => if (has) None else None,
                .stencil_view => if (has) None else None,
                .stencil_format => if (has) None else None,
                .stencil_layout => if (has) None else None,
                .stencil_op => if (has) None else None,
                .stencil_clear_value => if (has) None else None,
                .stencil_resolve_view => if (has) None else None,
                .stencil_resolve_layout => if (has) None else None,
                .stencil_resolve_mode => if (has) None else None,
                .render_area => if (has) None else None,
                .layers => if (has) None else None,
                .view_mask => if (has) None else None,
                .context => if (has) None else None,
                else => unreachable,
            };
        }
    }.getType;

    return struct {
        color_view: getType(.color_view),
        color_format: getType(.color_format),
        color_layout: getType(.color_layout),
        color_op: getType(.color_op),
        color_clear_value: getType(.color_clear_value),
        color_resolve_view: getType(.color_resolve_view),
        color_resolve_layout: getType(.color_resolve_layout),
        color_resolve_mode: getType(.color_resolve_mode),
        depth_view: getType(.depth_view),
        depth_format: getType(.depth_format),
        depth_layout: getType(.depth_layout),
        depth_op: getType(.depth_op),
        depth_clear_value: getType(.depth_clear_value),
        depth_resolve_view: getType(.depth_resolve_view),
        depth_resolve_layout: getType(.depth_resolve_layout),
        depth_resolve_mode: getType(.depth_resolve_mode),
        stencil_view: getType(.stencil_view),
        stencil_format: getType(.stencil_format),
        stencil_layout: getType(.stencil_layout),
        stencil_op: getType(.stencil_op),
        stencil_clear_value: getType(.stencil_clear_value),
        stencil_resolve_view: getType(.stencil_resolve_view),
        stencil_resolve_layout: getType(.stencil_resolve_layout),
        stencil_resolve_mode: getType(.stencil_resolve_mode),
        render_area: getType(.render_area),
        layers: getType(.layers),
        view_mask: getType(.view_mask),
        context: getType(.context),

        pub const mask = rendering_mask;

        pub const HashCtx = HashContext(@This());

        pub const init = getInitFn(@This());
        pub const clear = getClearFn(@This());
    };
}

pub const RenderingMask = packed struct {
    // `Cmd.Rendering.colors`.
    color_view: bool = false,
    color_format: bool = false,
    color_layout: bool = false,
    color_op: bool = false,
    color_clear_value: bool = false,
    color_resolve_view: bool = false,
    color_resolve_layout: bool = false,
    color_resolve_mode: bool = false,
    // `Cmd.Rendering.depth`.
    depth_view: bool = false,
    depth_format: bool = false,
    depth_layout: bool = false,
    depth_op: bool = false,
    depth_clear_value: bool = false,
    depth_resolve_view: bool = false,
    depth_resolve_layout: bool = false,
    depth_resolve_mode: bool = false,
    // `Cmd.Rendering.stencil`.
    stencil_view: bool = false,
    stencil_format: bool = false,
    stencil_layout: bool = false,
    stencil_op: bool = false,
    stencil_clear_value: bool = false,
    stencil_resolve_view: bool = false,
    stencil_resolve_layout: bool = false,
    stencil_resolve_mode: bool = false,
    // `Cmd.Rendering.render_area`.
    render_area: bool = false,
    // `Cmd.Rendering.layers`.
    layers: bool = false,
    // `Cmd.Rendering.view_mask`.
    view_mask: bool = false,
    // `Cmd.Rendering.context`.
    context: bool = false,
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

fn Shaders(comptime kind: enum {
    primitive,
    compute,
}) type {
    return struct {
        shader: switch (kind) {
            .primitive => struct {
                vertex: Impl.Shader = .{ .val = 0 },
                fragment: Impl.Shader = .{ .val = 0 },
            },
            .compute => struct {
                compute: Impl.Shader = .{ .val = 0 },
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
                        else => unreachable,
                    },
                    .compute => switch (@"type") {
                        .compute => self.shader.compute = if (shader) |x| x.impl else dfl,
                        else => unreachable,
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
    ) !void {
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
};

const PrimitiveTopology = struct {
    topology: Cmd.PrimitiveTopology = .triangle_list,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), topology: Cmd.PrimitiveTopology) void {
        self.topology = topology;
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

const max_color_attachment = 1 + @as(comptime_int, ~@as(Cmd.ColorAttachmentIndex, 0));

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
        for (self.views[rendering.colors.len..]) |*impl|
            impl.* = .{ .val = 0 };
    }
};

const ColorFormat = struct {
    formats: [max_color_attachment]ngl.Format = [_]ngl.Format{.unknown} ** max_color_attachment,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), rendering: Cmd.Rendering) void {
        for (self.formats[0..rendering.colors.len], rendering.colors) |*format, attach|
            format.* = attach.view.format;
        for (self.formats[rendering.colors.len..]) |*format|
            format.* = .unknown;
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
        for (self.layouts[rendering.colors.len..]) |*layout|
            layout.* = .unknown;
    }
};

const testing = std.testing;

fn expectEql(key: anytype, hash: u64, other_key: @TypeOf(key)) !void {
    const ctx = @TypeOf(key).HashCtx{};
    const other_hash = ctx.hash(other_key);
    try testing.expect(hash == other_hash and hash != 0);
    try testing.expect(ctx.eql(key, other_key));
    try testing.expect(ctx.eql(other_key, key));
}

fn expectNotEql(key: anytype, hash: u64, other_key: @TypeOf(key)) !void {
    const ctx = @TypeOf(key).HashCtx{};
    const other_hash = ctx.hash(other_key);
    try testing.expect(hash != 0 and other_hash != 0);
    if (hash == other_hash) std.log.warn("{s}: Hash value clash", .{@src().file});
    try testing.expect(!ctx.eql(key, other_key));
    try testing.expect(!ctx.eql(other_key, key));
}

test State {
    const P = State(StateMask(.primitive){
        .shaders = true,
        .vertex_input = true,
        .primitive_topology = true,
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

    const C = State(StateMask(.compute){ .shaders = true });
    if (@TypeOf(C.init().shaders) != Shaders(.compute))
        @compileError("Bad dyn.State layout");
    inline for (@typeInfo(@TypeOf(P.mask)).Struct.fields[1..]) |field|
        if (@TypeOf(@field(C.init(), field.name)) != None)
            @compileError("Bad dyn.State layout");

    // TODO: Consider disallowing this case.
    const X = State(StateMask(.primitive){});
    if (@sizeOf(X) != 0)
        @compileError("Bad dyn.State layout");

    inline for (.{ P, C, X }) |T| {
        const ctx = T.HashCtx{};
        const a = T.init();
        const b = T.init();
        try expectEql(a, ctx.hash(a), b);
    }

    var shaders: [3]ngl.Shader = .{
        .{ .impl = .{ .val = 1 } },
        .{ .impl = .{ .val = 2 } },
        .{ .impl = .{ .val = 3 } },
    };
    inline for (
        .{ P, C },
        .{
            .{
                &[_]ngl.Shader.Type{ .fragment, .vertex },
                &[_]*ngl.Shader{ &shaders[0], &shaders[1] },
            },
            .{
                &[_]ngl.Shader.Type{.compute},
                &[_]*ngl.Shader{&shaders[2]},
            },
        },
    ) |T, params| {
        const ctx = T.HashCtx{};
        var a = T.init();
        var b = T.init();
        var hb = ctx.hash(b);

        a.shaders.set(params[0], params[1]);
        try expectNotEql(b, hb, a);

        a.shaders = .{};
        try expectEql(b, hb, a);

        for (params[0], params[1]) |t, s| {
            a.shaders.set(&.{t}, &.{s});
            try expectNotEql(b, hb, a);
            b.shaders.set(&.{t}, &.{s});
            hb = ctx.hash(b);
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

    const ctx = P.HashCtx{};
    const s0 = P.init();
    const h0 = ctx.hash(s0);
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
    h1 = ctx.hash(s1);
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
    h1 = ctx.hash(s1);
    s2.vertex_input.bindings.items[0].binding -%= 1;
    try expectNotEql(s1, h1, s2);
    s2.primitive_topology.set(.line_list);
    try expectEql(s1, h1, s2);

    s1.vertex_input.clear(testing.allocator);
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s2.vertex_input.clear(testing.allocator);
    try expectEql(s1, h1, s2);

    s2.rasterization_enable.set(false);
    try expectNotEql(s1, h1, s2);
    s1.rasterization_enable.set(false);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.polygon_mode.set(.line);
    try expectNotEql(s1, h1, s2);
    s1.polygon_mode.set(.line);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.cull_mode.set(.front);
    try expectNotEql(s1, h1, s2);
    s1.cull_mode.set(.front);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.front_face.set(.counter_clockwise);
    try expectNotEql(s1, h1, s2);
    s1.front_face.set(.counter_clockwise);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.sample_count.set(.@"4");
    try expectNotEql(s1, h1, s2);
    s1.sample_count.set(.@"4");
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.sample_mask.set(0b1111);
    try expectNotEql(s1, h1, s2);
    s1.sample_mask.set(0xf);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.depth_bias_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_bias_enable.set(true);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.depth_bias.set(0.01, 2, 0);
    try expectNotEql(s1, h1, s2); // Clash.
    s1.depth_bias.value = 0.01;
    s1.depth_bias.slope = 2;
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.depth_test_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_test_enable.set(true);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.depth_compare_op.set(.less_equal);
    try expectNotEql(s1, h1, s2);
    s1.depth_compare_op.set(.less_equal);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.depth_write_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.depth_write_enable.set(true);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_test_enable.set(true);
    try expectNotEql(s1, h1, s2);
    s1.stencil_test_enable.set(true);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .invert, .replace, .equal);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s2.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s2.stencil_op.set(.front_and_back, .decrement_clamp, .increment_clamp, .zero, .greater);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.front, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s1.stencil_op.set(.back, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.stencil_read_mask.set(.back, 0x80);
    try expectNotEql(s1, h1, s2);
    s1.stencil_read_mask.set(.front, 0x80);
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_read_mask.set(.front, 0x80);
    try expectNotEql(s1, h1, s2);
    s1.stencil_read_mask.set(.back, 0x80);
    h1 = ctx.hash(s1);
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
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s1.stencil_write_mask.set(.back, 0x7f);
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s2.stencil_write_mask.set(.back, 0x7f);
    try expectEql(s1, h1, s2);
    s1.stencil_write_mask.set(.front_and_back, 0xfe);
    h1 = ctx.hash(s1);
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
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_blend_enable.set(1, &.{true});
    h1 = ctx.hash(s1);
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
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(1, &[_]Cmd.Blend{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }} ** 3);
    h1 = ctx.hash(s1);
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
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s1.color_blend.set(2, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .dest_color,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s2.color_blend = .{};
    try expectNotEql(s1, h1, s2);
    s1.color_blend.set(0, &[_]Cmd.Blend{.{}} ** max_color_attachment);
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);

    s2.color_write.set(0, &.{});
    try expectEql(s1, h1, s2);
    s2.color_write.set(1, &.{});
    try expectEql(s1, h1, s2);
    s2.color_write.set(1, &.{.all});
    try expectEql(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s1.color_write.set(1, &.{ .all, .{ .mask = .{ .r = true, .g = true, .b = true, .a = true } } });
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s1.color_write.set(2, &.{.all});
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
    s2.color_write.set(2, &.{.{ .mask = .{ .r = true } }});
    try expectNotEql(s1, h1, s2);
    s2.color_write.set(1, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** (max_color_attachment - 1));
    try expectNotEql(s1, h1, s2);
    s1.color_write.set(0, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** max_color_attachment);
    h1 = ctx.hash(s1);
    try expectNotEql(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = ctx.hash(s1);
    try expectEql(s1, h1, s2);
}

test Rendering {
    const U = @typeInfo(RenderingMask).Struct.backing_integer.?;

    const R = Rendering(.{
        .color_view = true,
        .color_format = true,
        .color_layout = true,
        .color_op = true,
        .color_clear_value = true,
        .color_resolve_view = true,
        .color_resolve_layout = true,
        .color_resolve_mode = true,
        .depth_view = true,
        .depth_format = true,
        .depth_layout = true,
        .depth_op = true,
        .depth_clear_value = true,
        .depth_resolve_view = true,
        .depth_resolve_layout = true,
        .depth_resolve_mode = true,
        .stencil_view = true,
        .stencil_format = true,
        .stencil_layout = true,
        .stencil_op = true,
        .stencil_clear_value = true,
        .stencil_resolve_view = true,
        .stencil_resolve_layout = true,
        .stencil_resolve_mode = true,
        .render_area = true,
        .layers = true,
        .view_mask = true,
        .context = true,
    });
    if (@as(U, @bitCast(R.mask)) != ~@as(U, 0))
        @compileError("Bad dyn.Rendering layout");
    // TODO
    //inline for (@typeInfo(R).Struct.fields) |field|
    //    if (field.type == None)
    //        @compileError("Bad dyn.Rendering layout");

    // TODO: Consider disallowing this case.
    const X = Rendering(.{});
    if (@as(U, @bitCast(X.mask)) != @as(U, 0) or @sizeOf(X) != 0)
        @compileError("Bad dyn.Rendering layout");

    const ctx = R.HashCtx{};
    const r0 = R.init();
    const h0 = ctx.hash(r0);
    var r1 = R.init();
    var h1: u64 = undefined;
    var r2 = R.init();

    try expectEql(r0, h0, r1);
    try expectEql(r0, h0, r2);
    r1.clear(null);
    r2.clear(testing.allocator);
    try expectEql(r0, h0, r1);
    try expectEql(r0, h0, r2);
    h1 = ctx.hash(r1);
    try expectEql(r1, h1, r2);

    var views = [_]ngl.ImageView{
        .{ .impl = .{ .val = 1 }, .format = .rgba8_unorm },
        .{ .impl = .{ .val = 2 }, .format = .rgba8_unorm },
        .{ .impl = .{ .val = 3 }, .format = .rgba16_sfloat },
        .{ .impl = .{ .val = 4 }, .format = .rgba16_sfloat },
        .{ .impl = .{ .val = 5 }, .format = .d32_sfloat_s8_uint },
        .{ .impl = .{ .val = 6 }, .format = .d32_sfloat_s8_uint },
    };
    const rend_empty = Cmd.Rendering{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 480, .height = 270 },
        .layers = 1,
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
        },
        .depth = .{
            .view = &views[4],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = .{
                .view = &views[5],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .stencil = .{
            .view = &views[4],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ undefined, 0xff } },
            .resolve = .{
                .view = &views[5],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .render_area = .{ .width = 480, .height = 270 },
        .layers = 1,
    };

    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_view.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_view.set(rend);
    h1 = ctx.hash(r1);
    try expectEql(r1, h1, r2);
    r1.color_view = .{};
    h1 = ctx.hash(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);
    @memset(&r2.color_view.views, views[1].impl);
    try expectNotEql(r1, h1, r2);
    r2.color_view.set(rend_empty);
    try expectEql(r1, h1, r2);

    r2.color_format.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_format.set(rend);
    try expectNotEql(r1, h1, r2);
    r1.color_format.set(rend);
    h1 = ctx.hash(r1);
    try expectEql(r1, h1, r2);
    r2.color_format = .{};
    try expectNotEql(r1, h1, r2);
    for (r2.color_format.formats[0..rend.colors.len], rend.colors) |*format, attach|
        format.* = attach.view.format;
    try expectEql(r1, h1, r2);

    r2.color_layout.set(rend_empty);
    try expectEql(r1, h1, r2);
    r2.color_layout.set(rend);
    try expectNotEql(r1, h1, r2);
    for (r1.color_layout.layouts[0..rend.colors.len], rend.colors) |*layout, attach|
        layout.* = attach.layout;
    h1 = ctx.hash(r1);
    try expectEql(r1, h1, r2);
    r1.color_layout.set(rend_empty);
    h1 = ctx.hash(r1);
    try expectNotEql(r1, h1, r2);
    r2.color_layout = .{};
    try expectEql(r1, h1, r2);
}
