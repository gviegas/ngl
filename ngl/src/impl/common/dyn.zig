const std = @import("std");

const ngl = @import("../../ngl.zig");
const Cmd = ngl.Cmd;
const Impl = @import("../Impl.zig");

pub fn State(comptime mask: anytype) type {
    const M = @TypeOf(mask);

    switch (M) {
        Mask(.primitive), Mask(.compute) => {},
        else => @compileError("dyn.State's argument must be of type dyn.Mask"),
    }

    const getType = struct {
        fn getType(comptime ident: anytype) type {
            const name = @tagName(ident);
            const has = @hasField(@TypeOf(mask), name) and @field(mask, name);
            return switch (ident) {
                .vertex_shader => if (has) ImplType(Impl.Shader) else None,
                .vertex_input => if (has) VertexInput else None,
                .primitive_topology => if (has) PrimitiveTopology else None,
                .fragment_shader => if (has) ImplType(Impl.Shader) else None,
                .viewports => if (has) Viewports else None,
                .scissor_rects => if (has) ScissorRects else None,
                .stencil_reference => if (has) StencilReference else None,
                .blend_constants => if (has) BlendConstants else None,
                .compute_shader => if (has) ImplType(Impl.Shader) else None,
                else => unreachable,
            };
        }
    }.getType;

    // TODO
    return struct {
        vertex_shader: getType(.vertex_shader),
        vertex_input: getType(.vertex_input),
        primitive_topology: getType(.primitive_topology),
        fragment_shader: getType(.fragment_shader),
        viewports: getType(.viewports),
        scissor_rects: getType(.scissor_rects),
        stencil_reference: getType(.stencil_reference),
        blend_constants: getType(.blend_constants),
        compute_shader: getType(.compute_shader),

        const Self = @This();

        pub const HashCtx = struct {
            pub fn hash(_: @This(), state: Self) u64 {
                var hasher = std.hash.Wyhash.init(0);
                inline for (fields()) |field|
                    @field(state, field.name).hash(&hasher);
                return hasher.final();
            }

            pub fn eql(_: @This(), state: Self, other: Self) bool {
                inline for (fields()) |field|
                    if (!@field(state, field.name).eql(@field(other, field.name)))
                        return false;
                return true;
            }
        };

        pub fn init() Self {
            var self: Self = undefined;
            inline for (fields()) |field|
                @field(self, field.name) = .{};
            return self;
        }

        pub fn clear(self: *Self, allocator: ?std.mem.Allocator) void {
            inline for (fields()) |field| {
                if (@hasDecl(field.type, "clear"))
                    @field(self, field.name).clear(allocator)
                else
                    @field(self, field.name) = .{};
            }
        }

        fn fields() @TypeOf(@typeInfo(Self).Struct.fields) {
            return @typeInfo(Self).Struct.fields;
        }
    };
}

pub fn Mask(comptime kind: enum {
    primitive,
    compute,
}) type {
    const names = switch (kind) {
        .primitive => &[_][:0]const u8{
            // `Cmd.setShaders`.
            "vertex_shader",
            // `Cmd.setVertexInput`.
            "vertex_input",
            // `Cmd.setPrimitiveTopology`.
            "primitive_topology",
        } ++ &common_render,
        .compute => &[_][:0]const u8{
            // `Cmd.setShaders`.
            "compute_shader",
        },
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

const common_render = [_][:0]const u8{
    // `Cmd.setShaders`.
    "fragment_shader",
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

const None = struct {
    pub inline fn hash(self: @This(), hasher: anytype) void {
        _ = self;
        _ = hasher;
    }

    pub inline fn eql(self: @This(), other: @This()) bool {
        _ = self;
        _ = other;
        return true;
    }
};

fn ImplType(comptime T: anytype) type {
    return struct {
        impl: T = .{ .val = 0 },

        pub inline fn hash(self: @This(), hasher: anytype) void {
            std.hash.autoHash(hasher, self.impl.val);
        }

        pub inline fn eql(self: @This(), other: @This()) bool {
            return std.meta.eql(self.impl.val, other.impl.val);
        }
    };
}

const VertexInput = struct {
    bindings: std.ArrayListUnmanaged(Cmd.VertexInputBinding) = .{},
    attributes: std.ArrayListUnmanaged(Cmd.VertexInputAttribute) = .{},

    pub inline fn hash(self: @This(), hasher: anytype) void {
        for (self.bindings.items) |bind|
            std.hash.autoHash(hasher, bind);
        for (self.attributes.items) |attr|
            std.hash.autoHash(hasher, attr);
    }

    pub inline fn eql(self: @This(), other: @This()) bool {
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

    pub inline fn hash(self: @This(), hasher: anytype) void {
        std.hash.autoHash(hasher, self.topology);
    }

    pub inline fn eql(self: @This(), other: @This()) bool {
        return std.meta.eql(self, other);
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

const StencilReference = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const BlendConstants = struct {
    comptime {
        @compileError("Shouldn't be necessary");
    }
};

const testing = std.testing;

test State {
    const P = State(Mask(.primitive){
        .vertex_shader = true,
        .vertex_input = true,
        .primitive_topology = true,
        .fragment_shader = true,
        .viewports = false,
        .scissor_rects = false,
        .stencil_reference = false,
        .blend_constants = false,
    });
    if (@TypeOf(P.init().vertex_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().vertex_input) != VertexInput or
        @TypeOf(P.init().primitive_topology) != PrimitiveTopology or
        @TypeOf(P.init().fragment_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().compute_shader) != None)
    {
        @compileError("Bad dyn.State layout");
    }

    const C = State(Mask(.compute){ .compute_shader = true });
    if (@TypeOf(C.init().compute_shader) != ImplType(Impl.Shader))
        @compileError("Bad dyn.State layout");
    // TODO
    inline for (@typeInfo(Mask(.primitive)).Struct.fields[0..4]) |field|
        if (@TypeOf(@field(C.init(), field.name)) != None)
            @compileError("Bad dyn.State layout");

    // TODO: Consider disallowing this case.
    const X = State(Mask(.primitive){});
    if (@sizeOf(X) != 0)
        @compileError("Bad dyn.State layout");

    inline for (.{ P, C, X }) |T| {
        const a = T.init();
        const b = T.init();
        const ctx = T.HashCtx{};
        const ha = ctx.hash(a);
        const hb = ctx.hash(b);
        try testing.expect(ha == hb and ha != 0);
        try testing.expect(ctx.eql(a, b));
        try testing.expect(ctx.eql(b, a));
    }

    inline for (.{ P, C }, .{ "fragment_shader", "compute_shader" }) |T, field_name| {
        var a = T.init();
        const b = T.init();
        const ctx = T.HashCtx{};
        const hb = ctx.hash(b);

        @field(a, field_name) = .{ .impl = .{ .val = 1 } };
        var ha = ctx.hash(a);
        try testing.expect(ha != hb and ha != 0);
        try testing.expect(!ctx.eql(a, b));
        try testing.expect(!ctx.eql(b, a));

        @field(a, field_name) = .{};
        ha = ctx.hash(a);
        try testing.expect(ha == hb and ha != 0);
        try testing.expect(ctx.eql(a, b));
        try testing.expect(ctx.eql(b, a));
    }

    inline for (.{ P, C }, .{ "vertex_shader", "compute_shader" }) |T, field_name| {
        var a = T.init();
        var b = T.init();
        const ctx = T.HashCtx{};
        var ha = ctx.hash(a);

        @field(b, field_name) = .{ .impl = .{ .val = 2 } };
        var hb = ctx.hash(b);
        try testing.expect(ha != hb and ha != 0);
        try testing.expect(!ctx.eql(a, b));
        try testing.expect(!ctx.eql(b, a));

        b.clear(null);
        hb = ctx.hash(b);
        try testing.expect(ha == hb and ha != 0);
        try testing.expect(ctx.eql(a, b));
        try testing.expect(ctx.eql(b, a));

        a.clear(null);
        ha = ctx.hash(a);
        try testing.expect(ha == hb and ha != 0);
        try testing.expect(ctx.eql(a, b));
        try testing.expect(ctx.eql(b, a));
    }

    const ctx = P.HashCtx{};
    const s0 = P.init();
    const h0 = ctx.hash(s0);
    var s = P.init();
    var h: u64 = undefined;

    try s.vertex_input.set(testing.allocator, &.{.{
        .binding = 0,
        .stride = 12,
        .step_rate = .vertex,
    }}, &.{.{
        .location = 0,
        .binding = 0,
        .format = .rgb32_sfloat,
        .offset = 0,
    }});
    h = ctx.hash(s);
    try testing.expect(h != h0 and h != 0);
    try testing.expect(!ctx.eql(s, s0));
    try testing.expect(!ctx.eql(s0, s));

    s.primitive_topology.topology = .line_list;
    try testing.expect(ctx.hash(s) != h0 and ctx.hash(s) != h and ctx.hash(s) != 0);
    try testing.expect(!ctx.eql(s, s0));
    try testing.expect(!ctx.eql(s0, s));

    s.primitive_topology = .{};
    try testing.expect(ctx.hash(s) == h);
    try testing.expect(!ctx.eql(s, s0));
    try testing.expect(!ctx.eql(s0, s));

    s.vertex_input.clear(testing.allocator);
    try testing.expect(ctx.hash(s) == h0);
    try testing.expect(ctx.eql(s, s0));
    try testing.expect(ctx.eql(s0, s));
}
