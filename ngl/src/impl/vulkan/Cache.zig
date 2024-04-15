const std = @import("std");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const dyn = @import("../common/dyn.zig");
const Device = @import("init.zig").Device;
const Dynamic = @import("cmd.zig").Dynamic;

state: State = .{},
rendering: Rendering = .{},

fn ValueWithStamp(comptime T: type) type {
    return struct { T, u64 };
}

const State = struct {
    hash_map: std.HashMapUnmanaged(Key, Value, Context, 80) = .{},
    mutex: std.Thread.Mutex = .{},

    const Key = Dynamic;
    const Value = ValueWithStamp(c.VkPipeline);

    // It suffices that the pipeline be compatible with
    // the render pass.
    // TODO: Try to refine this.
    const rendering_subset_mask = dyn.RenderingMask{
        .color_format = true,
        .color_samples = true,
        .depth_format = true,
        .depth_samples = true,
        .stencil_format = true,
        .stencil_samples = true,
        .view_mask = true,
    };

    const Context = struct {
        pub fn hash(_: @This(), d: Key) u64 {
            var hasher = std.hash.Wyhash.init(0);
            d.state.hash(&hasher);
            if (d.rendering) |x| x.hashSubset(rendering_subset_mask, &hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), d: Key, e: Key) bool {
            if (!d.state.eql(e.state)) return false;
            if (d.rendering) |x| return x.eqlSubset(rendering_subset_mask, e.rendering.?);
            return true;
        }
    };

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.hash_map.deinit(allocator);
        // TODO: Destroy handles.
    }
};

const Rendering = struct {
    hash_map: std.HashMapUnmanaged(Key, Value, Context, 80) = .{},
    mutex: std.Thread.Mutex = .{},

    const Key = dyn.Rendering(Dynamic.rendering_mask);
    const Value = ValueWithStamp(c.VkRenderPass);

    const subset_mask = dyn.RenderingMask{
        .color_format = true,
        .color_samples = true,
        .color_layout = true,
        .color_op = true,
        .color_resolve_layout = true,
        .color_resolve_mode = true,
        .depth_format = true,
        .depth_samples = true,
        .depth_layout = true,
        .depth_op = true,
        .depth_resolve_layout = true,
        .depth_resolve_mode = true,
        .stencil_format = true,
        .stencil_samples = true,
        .stencil_layout = true,
        .stencil_op = true,
        .stencil_resolve_layout = true,
        .stencil_resolve_mode = true,
        .view_mask = true,
    };

    const Context = struct {
        pub fn hash(_: @This(), r: Key) u64 {
            var hasher = std.hash.Wyhash.init(0);
            r.hashSubset(subset_mask, &hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), r: Key, s: Key) bool {
            return r.eqlSubset(subset_mask, s);
        }
    };

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.hash_map.deinit(allocator);
        // TODO: Destroy handles.
    }
};

pub fn getPrimitivePipeline(
    self: *@This(),
    allocator: std.mem.Allocator,
    device: *Device,
    key: State.Key,
) Error!c.VkPipeline {
    self.state.mutex.lock();
    defer self.state.mutex.unlock();

    if (self.state.hash_map.get(key)) |val| return val[0];

    // TODO
    _ = allocator;
    _ = device;
    return Error.Other;
}

pub fn getRenderPass(
    self: *@This(),
    allocator: std.mem.Allocator,
    device: *Device,
    key: Rendering.Key,
) Error!c.VkRenderPass {
    self.rendering.mutex.lock();
    defer self.rendering.mutex.unlock();

    if (self.rendering.hash_map.get(key)) |val| return val[0];

    // TODO
    _ = allocator;
    _ = device;
    return Error.Other;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.state.deinit(allocator);
    self.rendering.deinit(allocator);
}

const testing = std.testing;
const context = @import("../../test/test.zig").context;

test "Cache" {
    var cache = @This(){};
    defer cache.deinit(testing.allocator);

    var d = Dynamic.init(Device.cast(context().device.impl).*);
    defer d.clear(testing.allocator);

    try cache.state.hash_map.put(testing.allocator, d, .{ null, 1 });
    try testing.expect(cache.state.hash_map.contains(d));

    const r = &(d.rendering orelse return);

    try cache.rendering.hash_map.put(testing.allocator, r.*, .{ null, 2 });
    try testing.expect(cache.rendering.hash_map.contains(r.*));

    // Make sure `Cmd.Rendering` has no default values
    // on fields we need to check.
    var views = [_]ngl.ImageView{
        .{
            .impl = .{ .val = 0xbaba },
            .format = .rgba8_unorm,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0xbee },
            .format = .rgba8_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0xb00 },
            .format = .d24_unorm_s8_uint,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0xdeedee },
            .format = .d24_unorm_s8_uint,
            .samples = .@"1",
        },
    };
    const rend = ngl.Cmd.Rendering{
        .colors = &.{.{
            .view = &views[0],
            .layout = .color_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = .{
                .view = &views[1],
                .layout = .color_attachment_optimal,
                .mode = .min,
            },
        }},
        .depth = .{
            .view = &views[2],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ 0, undefined } },
            .resolve = .{
                .view = &views[3],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .min,
            },
        },
        .stencil = .{
            .view = &views[2],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ undefined, 0x80 } },
            .resolve = .{
                .view = &views[3],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .min,
            },
        },
        .render_area = .{ .width = 1, .height = 1 },
        .layers = 0,
        .view_mask = 0x1,
    };

    inline for (@typeInfo(@TypeOf(Dynamic.rendering_mask)).Struct.fields) |field| {
        if (!@field(Dynamic.rendering_mask, field.name)) continue;

        @field(r, field.name).set(rend);

        if (@field(State.rendering_subset_mask, field.name))
            try testing.expect(!cache.state.hash_map.contains(d))
        else
            try testing.expect(cache.state.hash_map.contains(d));

        if (@field(Rendering.subset_mask, field.name))
            try testing.expect(!cache.rendering.hash_map.contains(r.*))
        else
            try testing.expect(cache.rendering.hash_map.contains(r.*));

        d.clear(null);
        try testing.expect(cache.state.hash_map.contains(d));
        try testing.expect(cache.rendering.hash_map.contains(r.*));
    }
}
