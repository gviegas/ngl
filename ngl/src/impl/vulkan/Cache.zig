const std = @import("std");
const builtin = @import("builtin");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const dyn = @import("../common/dyn.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const log = @import("init.zig").log;
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

    fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
        var iter = self.hash_map.valueIterator();
        while (iter.next()) |val|
            device.vkDestroyPipeline(val[0], null);
        self.hash_map.deinit(allocator);
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

    fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
        var iter = self.hash_map.valueIterator();
        while (iter.next()) |val|
            device.vkDestroyRenderPass(val[0], null);
        self.hash_map.deinit(allocator);
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

pub fn createRenderPass(
    _: std.mem.Allocator,
    device: *Device,
    key: Rendering.Key,
) Error!c.VkRenderPass {
    const max_attach = ngl.Cmd.max_color_attachment * 2 + 2;
    var attachs = [_]c.VkAttachmentDescription{undefined} ** max_attach;
    var refs = [_]c.VkAttachmentReference{undefined} ** max_attach;

    // In case we decide to increase `Cmd.max_color_attachment`.
    if (@sizeOf(@TypeOf(attachs)) + @sizeOf(@TypeOf(refs)) >= 4096)
        @compileError("May want to allocate these in the heap");

    var attach_i: u32 = 0;

    // Only for references.
    const col_rv_off = ngl.Cmd.max_color_attachment;
    const ds_off = col_rv_off + ngl.Cmd.max_color_attachment;
    const ds_rv_off = ds_off + 1;

    const col_n = for (0..ngl.Cmd.max_color_attachment) |i| {
        if (key.color_format.formats[i] == .unknown)
            break i;

        const layt = conv.toVkImageLayout(key.color_layout.layouts[i]);
        attachs[attach_i] = .{
            .flags = 0,
            .format = try conv.toVkFormat(key.color_format.formats[i]),
            .samples = conv.toVkSampleCount(key.color_samples.sample_counts[i]),
            .loadOp = conv.toVkAttachmentLoadOp(key.color_op.load[i]),
            .storeOp = conv.toVkAttachmentStoreOp(key.color_op.store[i]),
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = layt,
            .finalLayout = layt,
        };
        refs[i] = .{
            .attachment = attach_i,
            .layout = layt,
        };

        attach_i += 1;

        if (key.color_resolve_layout.layouts[i] == .unknown) {
            refs[col_rv_off + i] = .{
                .attachment = c.VK_ATTACHMENT_UNUSED,
                .layout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            };
            continue;
        }

        const rv_layt = conv.toVkImageLayout(key.color_resolve_layout.layouts[i]);
        attachs[attach_i] = attachs[attach_i - 1];
        attachs[attach_i].samples = c.VK_SAMPLE_COUNT_1_BIT;
        attachs[attach_i].initialLayout = rv_layt;
        attachs[attach_i].finalLayout = rv_layt;
        refs[col_rv_off + i] = .{
            .attachment = attach_i,
            .layout = rv_layt,
        };

        attach_i += 1;
    } else ngl.Cmd.max_color_attachment;

    const ds: struct {
        format: ngl.Format,
        samples: ngl.SampleCount,
        layout: ngl.Image.Layout,
        rv_layout: ngl.Image.Layout,
    } = if (key.depth_format.format != .unknown) .{
        .format = key.depth_format.format,
        .samples = key.depth_samples.sample_count,
        .layout = key.depth_layout.layout,
        .rv_layout = key.depth_resolve_layout.layout,
    } else .{
        .format = key.stencil_format.format,
        .samples = key.stencil_samples.sample_count,
        .layout = key.stencil_layout.layout,
        .rv_layout = key.stencil_resolve_layout.layout,
    };

    if (ds.format != .unknown) {
        const layt = conv.toVkImageLayout(ds.layout);
        attachs[attach_i] = .{
            .flags = 0,
            .format = try conv.toVkFormat(ds.format),
            .samples = conv.toVkSampleCount(ds.samples),
            .loadOp = conv.toVkAttachmentLoadOp(key.depth_op.load),
            .storeOp = conv.toVkAttachmentStoreOp(key.depth_op.store),
            .stencilLoadOp = conv.toVkAttachmentLoadOp(key.stencil_op.load),
            .stencilStoreOp = conv.toVkAttachmentStoreOp(key.stencil_op.store),
            .initialLayout = layt,
            .finalLayout = layt,
        };
        refs[ds_off] = .{
            .attachment = attach_i,
            .layout = layt,
        };

        attach_i += 1;

        if (ds.rv_layout != .unknown) {
            const rv_layt = conv.toVkImageLayout(ds.rv_layout);
            attachs[attach_i] = attachs[attach_i - 1];
            attachs[attach_i].samples = c.VK_SAMPLE_COUNT_1_BIT;
            attachs[attach_i].initialLayout = rv_layt;
            attachs[attach_i].finalLayout = rv_layt;
            refs[ds_rv_off] = .{
                .attachment = attach_i,
                .layout = rv_layt,
            };

            attach_i += 1;
        }
    }

    // TODO: Depth/stencil resolve & resolve modes.
    if (ds.rv_layout != .unknown) {
        log.warn("Depth/stencil resolve not yet implemented", .{});
        return Error.NotSupported;
    }

    const create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = attach_i,
        .pAttachments = if (attach_i > 0) &attachs[0] else null,
        .subpassCount = 1,
        .pSubpasses = &.{
            .flags = 0,
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .colorAttachmentCount = @intCast(col_n),
            .pColorAttachments = if (col_n != 0) &refs[0] else null,
            .pResolveAttachments = if (col_n != 0) &refs[col_rv_off] else null,
            .pDepthStencilAttachment = if (ds.format != .unknown) &refs[ds_off] else null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
        },
        .dependencyCount = 0,
        .pDependencies = null,
    };

    if (builtin.is_test)
        validateRenderPass(key, create_info) catch return Error.Other;

    var rp: c.VkRenderPass = undefined;
    try check(device.vkCreateRenderPass(&create_info, null, &rp));
    return rp;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
    self.state.deinit(allocator, device);
    self.rendering.deinit(allocator, device);
}

const testing = std.testing;
const context = @import("../../test/test.zig").context;

test "Cache" {
    var cache = @This(){};
    defer cache.deinit(testing.allocator, Device.cast(context().device.impl));

    var d = Dynamic.init(Device.cast(context().device.impl).*);
    defer d.clear(testing.allocator);

    try cache.state.hash_map.put(testing.allocator, d, .{ null_handle, 1 });
    try testing.expect(cache.state.hash_map.contains(d));

    const r = &(d.rendering orelse return);

    try cache.rendering.hash_map.put(testing.allocator, r.*, .{ null_handle, 2 });
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

fn validateRenderPass(key: Rendering.Key, create_info: c.VkRenderPassCreateInfo) !void {
    if (!builtin.is_test) @compileError("For testing only");

    try testing.expect(create_info.subpassCount == 1);
    try testing.expect(create_info.pSubpasses != null);
    try testing.expect(create_info.dependencyCount == 0);

    const subpass = create_info.pSubpasses;
    try testing.expect(subpass.*.inputAttachmentCount == 0);
    try testing.expect(subpass.*.preserveAttachmentCount == 0);

    const col_n = blk: {
        var n: u32 = 0;
        while (key.color_format.formats[n] != .unknown) : (n += 1) {}
        try testing.expect(n == subpass.*.colorAttachmentCount);
        break :blk n;
    };
    const col_rv_n = blk: {
        var n: u32 = 0;
        for (0..col_n) |i| {
            if (key.color_resolve_layout.layouts[i] != .unknown)
                n += 1;
        }
        break :blk n;
    };
    const ds_n: u32 = blk: {
        const has_dep = key.depth_format.format != .unknown;
        const has_sten = key.stencil_format.format != .unknown;
        break :blk if (has_dep or has_sten) 1 else 0;
    };
    const ds_rv_n: u32 = 0; // TODO

    const attach_n = col_n + col_rv_n + ds_n + ds_rv_n;
    try testing.expect(attach_n == create_info.attachmentCount);

    // Code that create render passes and frame buffers
    // must put the attachments in the same order:
    //
    // * 1st color
    // * 1st color's resolve (optional)
    // * ...
    // * nth color
    // * nth color's resolve (optional)
    // * depth/stencil (optional)
    // * depth/stencil's resolve (optional; not yet supported)

    if (ds_rv_n != 0) {
        unreachable; // TODO
    } else if (ds_n != 0) {
        const ds = subpass.*.pDepthStencilAttachment;
        try testing.expect(ds != null);
        try testing.expect(ds.*.attachment == attach_n - 1);
    }

    var attach_i: u32 = 0;
    for (0..col_n) |i| {
        const col = subpass.*.pColorAttachments[i];
        try testing.expect(col.attachment == attach_i);
        attach_i += 1;
        if (key.color_resolve_layout.layouts[i] != .unknown) {
            const rv = subpass.*.pResolveAttachments[i];
            try testing.expect(rv.attachment == attach_i);
            attach_i += 1;
        }
    }
}

test createRenderPass {
    const dev = Device.cast(context().device.impl);

    var key = Dynamic.init(dev.*);

    const no_attach = try createRenderPass(testing.allocator, dev, key.rendering.?);
    dev.vkDestroyRenderPass(no_attach, null);

    var dep_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = .d16_unorm,
        .samples = .@"1",
    };
    key.rendering.?.set(.{
        .colors = &.{},
        .depth = .{
            .view = &dep_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = 1024, .height = 1024 },
        .layers = 1,
    });
    const dep_only = try createRenderPass(testing.allocator, dev, key.rendering.?);
    dev.vkDestroyRenderPass(dep_only, null);

    const s8_feat = ngl.Format.s8_uint.getFeatures(&context().device);
    if (s8_feat.optimal_tiling.depth_stencil_attachment) {
        var sten_view = ngl.ImageView{
            .impl = .{ .val = 0 },
            .format = .s8_uint,
            .samples = .@"1",
        };
        key.rendering.?.set(.{
            .colors = &.{},
            .depth = null,
            .stencil = .{
                .view = &sten_view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .depth_stencil = .{ undefined, 0x7f } },
                .resolve = null,
            },
            .render_area = .{ .width = 240, .height = 135 },
            .layers = 1,
        });
        const sten_only = try createRenderPass(testing.allocator, dev, key.rendering.?);
        dev.vkDestroyRenderPass(sten_only, null);
    } else log.warn("Skipping createRenderPass's stencil-only test", .{});

    var ms_dep_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = dep_view.format,
        .samples = .@"4",
    };
    key.rendering.?.set(.{
        .colors = &.{},
        .depth = .{
            .view = &ms_dep_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = .{
                .view = &dep_view,
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .stencil = null,
        .render_area = .{ .width = 2048, .height = 2048 },
        .layers = 1,
    });
    // TODO: Implement this.
    const ms_dep_only = createRenderPass(testing.allocator, dev, key.rendering.?);
    try testing.expect(ms_dep_only == Error.NotSupported);

    var col_views = [3]ngl.ImageView{
        .{
            .impl = .{ .val = 0 },
            .format = .rgba8_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0 },
            .format = .a2bgr10_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0 },
            .format = .rgba16_sfloat,
            .samples = .@"1",
        },
    };
    for ([_][]const *ngl.ImageView{
        &.{&col_views[0]},
        &.{ &col_views[0], &col_views[1] },
        &.{ &col_views[0], &col_views[1], &col_views[2] },
    }) |views| {
        var attachs: [col_views.len]ngl.Cmd.Rendering.Attachment = undefined;
        for (views, attachs[0..views.len]) |view, *attach|
            attach.* = .{
                .view = view,
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = null,
            };
        key.rendering.?.set(.{
            .colors = attachs[0..views.len],
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = 800, .height = 450 },
            .layers = 1,
        });
        const col_only = try createRenderPass(testing.allocator, dev, key.rendering.?);
        dev.vkDestroyRenderPass(col_only, null);
    }

    var ms_col_views = [3]ngl.ImageView{
        .{
            .impl = .{ .val = 0 },
            .format = col_views[0].format,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0 },
            .format = col_views[1].format,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0 },
            .format = col_views[2].format,
            .samples = .@"4",
        },
    };
    for ([_][]const struct { *ngl.ImageView, ?*ngl.ImageView }{
        &.{
            .{ &ms_col_views[0], &col_views[0] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], &col_views[1] },
        },
        &.{
            .{ &ms_col_views[0], null },
            .{ &ms_col_views[1], &col_views[1] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], null },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], &col_views[1] },
            .{ &ms_col_views[2], &col_views[2] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], null },
            .{ &ms_col_views[2], &col_views[2] },
        },
        &.{
            .{ &ms_col_views[0], null },
            .{ &ms_col_views[1], &col_views[1] },
            .{ &ms_col_views[2], null },
        },
    }) |views| {
        var attachs: [ms_col_views.len]ngl.Cmd.Rendering.Attachment = undefined;
        for (views, attachs[0..views.len]) |view, *attach|
            attach.* = .{
                .view = view[0],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = if (view[1] == null) .store else .dont_care,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = if (view[1]) |ss| .{
                    .view = ss,
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                } else null,
            };
        key.rendering.?.set(.{
            .colors = attachs[0..views.len],
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = 1024, .height = 576 },
            .layers = 1,
        });
        const ms_col_only = try createRenderPass(testing.allocator, dev, key.rendering.?);
        dev.vkDestroyRenderPass(ms_col_only, null);
    }

    var ds_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = for ([_]ngl.Format{
            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
        }) |comb| {
            if (comb.getFeatures(&context().device).optimal_tiling.depth_stencil_attachment)
                break comb;
        } else unreachable,
        .samples = .@"4",
    };
    key.rendering.?.set(.{
        .colors = &.{
            .{
                .view = &ms_col_views[0],
                .layout = .color_attachment_optimal,
                .load_op = .load,
                .store_op = .dont_care,
                .clear_value = null,
                .resolve = .{
                    .view = &col_views[0],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &ms_col_views[2],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .color_f32 = .{ 0.1, 0.2, 0.3, 1 } },
                .resolve = .{
                    .view = &col_views[2],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &ms_col_views[1],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 0.5, 0.5, 0.5, 1 } },
                .resolve = null,
            },
        },
        .depth = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        },
        .stencil = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ undefined, 0xff } },
            .resolve = null,
        },
        .render_area = .{ .width = 1920, .height = 1080 },
        .layers = 1,
    });
    const ms_col_ds = try createRenderPass(testing.allocator, dev, key.rendering.?);
    dev.vkDestroyRenderPass(ms_col_ds, null);
}
