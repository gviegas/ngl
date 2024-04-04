const std = @import("std");

const ngl = @import("../../ngl.zig");
const Impl = @import("../Impl.zig");

pub fn State(comptime mask: anytype) type {
    const M = @TypeOf(mask);

    switch (M) {
        Mask(.primitive), Mask(.compute) => {},
        else => @compileError("dyn.State's argument must be of type dyn.Mask"),
    }

    // TODO
    return struct {
        vertex_shader: if (@hasField(M, "vertex_shader") and mask.vertex_shader)
            ImplType(Impl.Shader)
        else
            None,
        fragment_shader: if (@hasField(M, "fragment_shader") and mask.fragment_shader)
            ImplType(Impl.Shader)
        else
            None,
        compute_shader: if (@hasField(M, "compute_shader") and mask.compute_shader)
            ImplType(Impl.Shader)
        else
            None,

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

const testing = std.testing;

test State {
    const P = State(Mask(.primitive){
        .vertex_shader = true,
        .fragment_shader = true,
    });
    if (@TypeOf(P.init().vertex_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().fragment_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().compute_shader) != None)
    {
        @compileError("Bad dyn.State layout");
    }

    const C = State(Mask(.compute){ .compute_shader = true });
    if (@sizeOf(C) >= @sizeOf(P) or
        @TypeOf(C.init().vertex_shader) != None or
        @TypeOf(C.init().fragment_shader) != None or
        @TypeOf(C.init().compute_shader) != ImplType(Impl.Shader))
    {
        @compileError("Bad dyn.State layout");
    }

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
}
