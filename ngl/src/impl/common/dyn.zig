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
                .rasterization_enable => if (has) RasterizationEnable else None,
                .polygon_mode => if (has) PolygonMode else None,
                .cull_mode => if (has) CullMode else None,
                .front_face => if (has) FrontFace else None,
                .sample_count => if (has) SampleCount else None,
                .sample_mask => if (has) SampleMask else None,
                .depth_bias_enable => if (has) DepthBiasEnable else None,
                .depth_bias => if (has) DepthBias else None,
                .depth_test_enable => if (has) DepthTestEnable else None,
                .depth_compare_op => if (has) DepthCompareOp else None,
                .depth_write_enable => if (has) DepthWriteEnable else None,
                .stencil_test_enable => if (has) StencilTestEnable else None,
                .stencil_op => if (has) StencilOp else None,
                .stencil_read_mask => if (has) StencilReadMask else None,
                .stencil_write_mask => if (has) StencilWriteMask else None,
                .stencil_reference => if (has) StencilReference else None,
                .color_blend_enable => if (has) ColorBlendEnable else None,
                .color_blend => if (has) ColorBlend else None,
                .color_write => if (has) ColorWrite else None,
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

fn getDefaultHashFn(comptime K: type) (fn (K, hasher: anytype) void) {
    return struct {
        fn hash(key: K, hasher: anytype) void {
            std.hash.autoHash(hasher, key);
        }
    }.hash;
}

fn getDefaultEqlFn(comptime K: type) (fn (K, K) bool) {
    return struct {
        fn eql(key: K, other: K) bool {
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

fn ImplType(comptime T: anytype) type {
    return struct {
        impl: T = .{ .val = 0 },

        pub const hash = getDefaultHashFn(@This());
        pub const eql = getDefaultEqlFn(@This());

        pub fn set(self: *@This(), impl: T) void {
            self.impl = impl;
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

const RasterizationEnable = struct {
    enable: bool = true,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), enable: bool) void {
        self.enable = enable;
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

const DepthBiasEnable = struct {
    enable: bool = false,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), enable: bool) void {
        self.enable = enable;
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

const DepthTestEnable = struct {
    enable: bool = false,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), enable: bool) void {
        self.enable = enable;
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

const DepthWriteEnable = struct {
    enable: bool = false,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), enable: bool) void {
        self.enable = enable;
    }
};

const StencilTestEnable = struct {
    enable: bool = false,

    pub const hash = getDefaultHashFn(@This());
    pub const eql = getDefaultEqlFn(@This());

    pub fn set(self: *@This(), enable: bool) void {
        self.enable = enable;
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

const StencilReadMask = struct {
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

const StencilWriteMask = struct {
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

// May want to use dynamic allocation in this case.
comptime {
    if (max_color_attachment > 16) unreachable;
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

const testing = std.testing;

fn expectState(state: anytype, hash: u64, other_state: @TypeOf(state)) !void {
    const ctx = @TypeOf(state).HashCtx{};
    const other_hash = ctx.hash(other_state);
    try testing.expect(hash == other_hash and hash != 0);
    try testing.expect(ctx.eql(state, other_state));
    try testing.expect(ctx.eql(other_state, state));
}

fn expectNotState(state: anytype, hash: u64, other_state: @TypeOf(state)) !void {
    const ctx = @TypeOf(state).HashCtx{};
    const other_hash = ctx.hash(other_state);
    try testing.expect(hash != 0 and other_hash != 0);
    if (hash == other_hash) std.log.warn("{s}: Hash value clash", .{@src().file});
    try testing.expect(!ctx.eql(state, other_state));
    try testing.expect(!ctx.eql(other_state, state));
}

test State {
    const P = State(Mask(.primitive){
        .vertex_shader = true,
        .vertex_input = true,
        .primitive_topology = true,
        .fragment_shader = true,
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
    // TODO
    if (@TypeOf(P.init().vertex_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().fragment_shader) != ImplType(Impl.Shader) or
        @TypeOf(P.init().compute_shader) != None)
    {
        @compileError("Bad dyn.State layout");
    }

    const C = State(Mask(.compute){ .compute_shader = true });
    if (@TypeOf(C.init().compute_shader) != ImplType(Impl.Shader))
        @compileError("Bad dyn.State layout");
    // TODO
    inline for (@typeInfo(Mask(.primitive)).Struct.fields[0..2]) |field|
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
        try expectState(a, ctx.hash(a), b);
    }

    inline for (.{ P, C }, .{ "fragment_shader", "compute_shader" }) |T, field_name| {
        var a = T.init();
        const b = T.init();
        const ctx = T.HashCtx{};
        const hb = ctx.hash(b);

        @field(a, field_name).set(.{ .val = 1 });
        try expectNotState(b, hb, a);

        @field(a, field_name) = .{};
        try expectState(b, hb, a);
    }

    inline for (.{ P, C }, .{ "vertex_shader", "compute_shader" }) |T, field_name| {
        var a = T.init();
        var b = T.init();
        const ctx = T.HashCtx{};
        const ha = ctx.hash(a);

        @field(b, field_name).set(.{ .val = 2 });
        try expectNotState(a, ha, b);

        b.clear(null);
        try expectState(a, ha, b);

        a.clear(null);
        try expectState(b, ctx.hash(b), a);
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
    try expectNotState(s0, h0, s1);

    try s2.vertex_input.set(testing.allocator, s1.vertex_input.bindings.items, &.{});
    try expectNotState(s0, h0, s2);
    try expectNotState(s1, h1, s2);
    try s2.vertex_input.set(
        testing.allocator,
        s1.vertex_input.bindings.items,
        s1.vertex_input.attributes.items,
    );
    try expectNotState(s0, h0, s2);
    try expectState(s1, h1, s2);

    s2.vertex_input.bindings.items[0].binding +%= 1;
    try expectNotState(s0, h0, s2);
    try expectNotState(s1, h1, s2);
    s1.primitive_topology.set(.line_list);
    h1 = ctx.hash(s1);
    s2.vertex_input.bindings.items[0].binding -%= 1;
    try expectNotState(s1, h1, s2);
    s2.primitive_topology.set(.line_list);
    try expectState(s1, h1, s2);

    s1.vertex_input.clear(testing.allocator);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.vertex_input.clear(testing.allocator);
    try expectState(s1, h1, s2);

    s2.rasterization_enable.set(false);
    try expectNotState(s1, h1, s2);
    s1.rasterization_enable.set(false);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.polygon_mode.set(.line);
    try expectNotState(s1, h1, s2);
    s1.polygon_mode.set(.line);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.cull_mode.set(.front);
    try expectNotState(s1, h1, s2);
    s1.cull_mode.set(.front);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.front_face.set(.counter_clockwise);
    try expectNotState(s1, h1, s2);
    s1.front_face.set(.counter_clockwise);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.sample_count.set(.@"4");
    try expectNotState(s1, h1, s2);
    s1.sample_count.set(.@"4");
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.sample_mask.set(0b1111);
    try expectNotState(s1, h1, s2);
    s1.sample_mask.set(0xf);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.depth_bias_enable.set(true);
    try expectNotState(s1, h1, s2);
    s1.depth_bias_enable.set(true);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.depth_bias.set(0.01, 2, 0);
    try expectNotState(s1, h1, s2); // Clash.
    s1.depth_bias.value = 0.01;
    s1.depth_bias.slope = 2;
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.depth_test_enable.set(true);
    try expectNotState(s1, h1, s2);
    s1.depth_test_enable.set(true);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.depth_compare_op.set(.less_equal);
    try expectNotState(s1, h1, s2);
    s1.depth_compare_op.set(.less_equal);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.depth_write_enable.set(true);
    try expectNotState(s1, h1, s2);
    s1.depth_write_enable.set(true);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.stencil_test_enable.set(true);
    try expectNotState(s1, h1, s2);
    s1.stencil_test_enable.set(true);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    try expectNotState(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .invert, .replace, .equal);
    try expectNotState(s1, h1, s2);
    s1.stencil_op.set(.front, .zero, .replace, .invert, .equal);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s2.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    try expectNotState(s1, h1, s2);
    s1.stencil_op.set(.back, .keep, .increment_wrap, .keep, .greater);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s2.stencil_op.set(.front_and_back, .decrement_clamp, .increment_clamp, .zero, .greater);
    try expectNotState(s1, h1, s2);
    s1.stencil_op.set(.front, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s1.stencil_op.set(.back, .decrement_clamp, .increment_clamp, .zero, .greater);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.stencil_read_mask.set(.back, 0x80);
    try expectNotState(s1, h1, s2);
    s1.stencil_read_mask.set(.front, 0x80);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.stencil_read_mask.set(.front, 0x80);
    try expectNotState(s1, h1, s2);
    s1.stencil_read_mask.set(.back, 0x80);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s2.stencil_read_mask.set(.front_and_back, 0x80);
    try expectState(s1, h1, s2);
    s2.stencil_read_mask.set(.front_and_back, 0x1);
    try expectNotState(s1, h1, s2);
    s2.stencil_read_mask.set(.front, 0x80);
    try expectNotState(s1, h1, s2);
    s2.stencil_read_mask.set(.back, 0x80);
    try expectState(s1, h1, s2);

    s2.stencil_write_mask.set(.front, 0x7f);
    try expectNotState(s1, h1, s2);
    s1.stencil_write_mask.set(.front, 0x7f);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s1.stencil_write_mask.set(.back, 0x7f);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.stencil_write_mask.set(.back, 0x7f);
    try expectState(s1, h1, s2);
    s1.stencil_write_mask.set(.front_and_back, 0xfe);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.stencil_write_mask.set(.front_and_back, 0xfe);
    try expectState(s1, h1, s2);

    s2.color_blend_enable.set(1, &.{});
    try expectState(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{true});
    try expectNotState(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{false});
    try expectState(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{false});
    try expectState(s1, h1, s2);
    s1.color_blend_enable.set(2, &.{true});
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s1.color_blend_enable.set(1, &.{true});
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.color_blend_enable.set(1, &.{ true, true });
    try expectState(s1, h1, s2);

    s2.color_blend.set(2, &.{});
    try expectState(s1, h1, s2);
    s2.color_blend.set(2, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    try expectNotState(s1, h1, s2);
    s1.color_blend.set(1, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s1.color_blend.set(1, &[_]Cmd.Blend{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }} ** 3);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.color_blend.set(1, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .one,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    try expectNotState(s1, h1, s2);
    s1.color_blend.set(3, &.{.{}});
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s1.color_blend.set(2, &.{.{
        .color_source_factor = .source_color,
        .color_dest_factor = .dest_color,
        .color_op = .min,
        .alpha_source_factor = .source_alpha,
        .alpha_dest_factor = .zero,
        .alpha_op = .max,
    }});
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s2.color_blend = .{};
    try expectNotState(s1, h1, s2);
    s1.color_blend.set(0, &[_]Cmd.Blend{.{}} ** max_color_attachment);
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);

    s2.color_write.set(0, &.{});
    try expectState(s1, h1, s2);
    s2.color_write.set(1, &.{});
    try expectState(s1, h1, s2);
    s2.color_write.set(1, &.{.all});
    try expectState(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s1.color_write.set(1, &.{ .all, .{ .mask = .{ .r = true, .g = true, .b = true, .a = true } } });
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s1.color_write.set(2, &.{.all});
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
    s2.color_write.set(2, &.{.{ .mask = .{ .r = true } }});
    try expectNotState(s1, h1, s2);
    s2.color_write.set(1, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** (max_color_attachment - 1));
    try expectNotState(s1, h1, s2);
    s1.color_write.set(0, &[_]Cmd.ColorMask{.{ .mask = .{} }} ** max_color_attachment);
    h1 = ctx.hash(s1);
    try expectNotState(s1, h1, s2);
    s1.color_write.set(0, &.{.all});
    h1 = ctx.hash(s1);
    try expectState(s1, h1, s2);
}
