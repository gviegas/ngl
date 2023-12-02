const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;
const c = @import("../impl/c.zig");

test "Surface.init/deinit" {
    var inst = ngl.Instance.init(gpa, .{ .presentation = true }) catch |err| {
        if (err == ngl.Error.NotPresent) return error.SkipZigTest;
        try testing.expect(false);
        unreachable;
    };
    defer inst.deinit(gpa);

    switch (builtin.os.tag) {
        .linux => if (builtin.target.isAndroid()) {
            @compileError("TODO");
        } else {
            var plat = try PlatformXcb.init();
            defer plat.deinit();
            var sf = try ngl.Surface.init(gpa, &inst, .{
                .platform = .{ .xcb = .{
                    .connection = plat.connection,
                    .window = plat.window,
                } },
            });
            sf.deinit(gpa, &inst);
        },
        .windows => @compileError("TODO"),
        else => @compileError("OS not supported"),
    }
}

test "Surface queries" {
    const ctx = context();
    const sf = &(try platform()).surface;

    for (ctx.device_desc.queues) |queue_desc| {
        const is_compatible = try sf.isCompatible(
            &ctx.instance,
            ctx.device_desc,
            queue_desc orelse continue,
        );
        if (is_compatible) break;
    } else {
        // NOTE: This could happen but shouldn't
        try testing.expect(false);
    }

    const pres_modes = try sf.getPresentModes(&ctx.instance, ctx.device_desc);
    // FIFO support is mandatory
    try testing.expect(pres_modes.fifo);

    // NOTE: Currently this may return no formats at all
    const fmts = try sf.getFormats(gpa, &ctx.instance, ctx.device_desc);
    defer gpa.free(fmts);
    for (fmts) |fmt|
        try testing.expect(fmt.format.getFeatures(&ctx.device).optimal_tiling.color_attachment);

    const capab = try sf.getCapabilities(&ctx.instance, ctx.device_desc, .fifo);
    try testing.expect(capab.min_count > 0);
    // This differs from Vulkan
    try testing.expect(capab.max_count >= capab.min_count);
    if (capab.current_width) |w| {
        if (capab.current_height) |h| {
            try testing.expect(w >= capab.min_width);
            try testing.expect(h >= capab.min_height);
            try testing.expect(w <= capab.max_width);
            try testing.expect(h <= capab.max_height);
        } else try testing.expect(false);
    } else try testing.expectEqual(capab.current_height, null);
    try testing.expect(capab.min_width <= capab.max_width);
    try testing.expect(capab.min_height <= capab.max_height);
    try testing.expect(capab.max_layers > 0);
    try testing.expect(!ngl.noFlagsSet(capab.supported_transforms));
    try testing.expect(!ngl.noFlagsSet(capab.supported_composite_alpha));
    try testing.expect(capab.supported_usage.color_attachment);
}

pub const Platform = struct {
    impl: switch (builtin.os.tag) {
        .linux => if (builtin.target.isAndroid()) PlatformAndroid else PlatformXcb,
        .windows => PlatformWin32,
        else => @compileError("OS not supported"),
    },
    surface: ngl.Surface,
    format: ngl.Surface.Format,
    swap_chain: ngl.SwapChain,
    images: []ngl.Image,
    image_views: []ngl.ImageView,
    queue_index: usize,

    pub const width = 960;
    pub const height = 540;

    pub const Input = packed struct {
        done: bool = false,
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
        option: bool = false,
        option_2: bool = false,
    };

    fn init(allocator: std.mem.Allocator) !Platform {
        const ctx = context();
        if (!ctx.instance_desc.presentation or !ctx.device_desc.feature_set.presentation)
            return error.SkipZigTest;

        var impl = try @typeInfo(Platform).Struct.fields[0].type.init();
        errdefer impl.deinit();

        var sf = try switch (builtin.os.tag) {
            .linux => if (builtin.target.isAndroid())
                @compileError("TODO")
            else
                ngl.Surface.init(allocator, &ctx.instance, .{
                    .platform = .{ .xcb = .{
                        .connection = impl.connection,
                        .window = impl.window,
                    } },
                }),
            .windows => @compileError("TODO"),
            else => @compileError("OS not supported"),
        };
        errdefer sf.deinit(allocator, &ctx.instance);

        const fmts = try sf.getFormats(allocator, &ctx.instance, ctx.device_desc);
        defer allocator.free(fmts);
        const fmt_i = for (fmts, 0..) |fmt, i| {
            // TODO
            _ = fmt;
            break i;
        } else unreachable;
        const capab = try sf.getCapabilities(&ctx.instance, ctx.device_desc, .fifo);

        var sc = try ngl.SwapChain.init(allocator, &ctx.device, .{
            .surface = &sf,
            .min_count = capab.min_count,
            .format = fmts[fmt_i].format,
            .color_space = fmts[fmt_i].color_space,
            .width = width,
            .height = height,
            .layers = 1,
            .usage = .{ .color_attachment = true },
            .pre_transform = capab.current_transform,
            .composite_alpha = inline for (
                @typeInfo(ngl.Surface.CompositeAlpha.Flags).Struct.fields,
            ) |f| {
                if (@field(capab.supported_composite_alpha, f.name))
                    break @field(ngl.Surface.CompositeAlpha, f.name);
            } else unreachable,
            .present_mode = .fifo,
            .clipped = true,
            .old_swap_chain = null,
        });
        errdefer sc.deinit(allocator, &ctx.device);

        const imgs = try sc.getImages(allocator, &ctx.device);
        errdefer allocator.free(imgs);

        var views = try allocator.alloc(ngl.ImageView, imgs.len);
        errdefer allocator.free(views);
        for (views, imgs, 0..) |*view, *image, i| {
            view.* = ngl.ImageView.init(allocator, &ctx.device, .{
                .image = image,
                .type = .@"2d",
                .format = fmts[fmt_i].format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .base_level = 0,
                    .levels = 1,
                    .base_layer = 0,
                    .layers = 1,
                },
            }) catch |err| {
                for (0..i) |j| views[j].deinit(allocator, &ctx.device);
                return err;
            };
        }

        const queue_i = for (ctx.device_desc.queues, 0..) |queue_desc, i| {
            const is = sf.isCompatible(
                &ctx.instance,
                ctx.device_desc,
                queue_desc orelse continue,
            ) catch continue;
            if (is) break i;
        } else return error.SkipZigTest;

        return .{
            .impl = impl,
            .surface = sf,
            .format = fmts[fmt_i],
            .swap_chain = sc,
            .images = imgs,
            .image_views = views,
            .queue_index = queue_i,
        };
    }

    pub fn poll(self: *Platform) Input {
        return self.impl.poll();
    }

    fn deinit(self: *Platform, allocator: std.mem.Allocator) void {
        const ctx = context();
        for (self.image_views) |*view| view.deinit(allocator, &ctx.device);
        allocator.free(self.image_views);
        allocator.free(self.images);
        self.swap_chain.deinit(allocator, &ctx.device);
        self.surface.deinit(allocator, &ctx.instance);
        self.impl.deinit();
        self.* = undefined;
    }
};

pub fn platform() !*Platform {
    const Static = struct {
        var plat: anyerror!Platform = undefined;
        var once = std.once(init);

        fn init() void {
            // Let it leak
            const allocator = std.heap.page_allocator;
            plat = Platform.init(allocator);
            if (plat) |_| {} else |err| {
                if (err != error.SkipZigTest) @panic(@errorName(err));
            }
        }
    };

    Static.once.call();
    return &(try Static.plat);
}

pub var platform_lock = std.Thread.Mutex{};

// TODO
const PlatformAndroid = struct {
    fn init() !PlatformAndroid {
        @compileError("TODO");
    }

    fn poll(_: PlatformAndroid) Platform.Input {
        @compileError("TODO");
    }

    fn deinit(_: *PlatformAndroid) void {
        @compileError("TODO");
    }
};

// TODO
const PlatformWin32 = struct {
    fn init() !PlatformWin32 {
        @compileError("TODO");
    }

    fn poll(_: PlatformWin32) Platform.Input {
        @compileError("TODO");
    }

    fn deinit(_: *PlatformWin32) void {
        @compileError("TODO");
    }
};

const PlatformXcb = struct {
    connection: *c.xcb_connection_t,
    setup: *const c.xcb_setup_t,
    screen: c.xcb_screen_t,
    window: c.xcb_window_t,

    fn init() !PlatformXcb {
        var self: PlatformXcb = undefined;

        self.connection = c.xcb_connect(null, null).?;
        if (c.xcb_connection_has_error(self.connection) != 0)
            return error.Connection;
        errdefer c.xcb_disconnect(self.connection);
        self.setup = c.xcb_get_setup(self.connection);
        self.screen = c.xcb_setup_roots_iterator(self.setup).data.*;
        self.window = try self.createWindow(Platform.width, Platform.height);
        errdefer _ = c.xcb_destroy_window(self.connection, self.window);
        try self.mapWindow(self.window);

        return self;
    }

    fn createWindow(self: PlatformXcb, width: u16, height: u16) !c.xcb_window_t {
        const id = c.xcb_generate_id(self.connection);
        const class = c.XCB_WINDOW_CLASS_INPUT_OUTPUT;
        const value_mask = c.XCB_CW_BACK_PIXEL | c.XCB_CW_EVENT_MASK;
        const value_list = [2]u32{
            self.screen.black_pixel,
            c.XCB_EVENT_MASK_KEY_PRESS |
                c.XCB_EVENT_MASK_KEY_RELEASE |
                c.XCB_EVENT_MASK_BUTTON_PRESS |
                c.XCB_EVENT_MASK_BUTTON_RELEASE |
                c.XCB_EVENT_MASK_ENTER_WINDOW |
                c.XCB_EVENT_MASK_LEAVE_WINDOW |
                c.XCB_EVENT_MASK_POINTER_MOTION |
                c.XCB_EVENT_MASK_BUTTON_MOTION |
                c.XCB_EVENT_MASK_EXPOSURE |
                c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_FOCUS_CHANGE,
        };
        const cookie = c.xcb_create_window_checked(
            self.connection,
            0,
            id,
            self.screen.root,
            0,
            0,
            width,
            height,
            0,
            class,
            self.screen.root_visual,
            value_mask,
            &value_list,
        );
        if (c.xcb_request_check(self.connection, cookie)) |err| {
            std.c.free(err);
            return error.WindowCreation;
        }
        return id;
    }

    fn mapWindow(self: PlatformXcb, window: c.xcb_window_t) !void {
        const cookie = c.xcb_map_window_checked(self.connection, window);
        if (c.xcb_request_check(self.connection, cookie)) |err| {
            std.c.free(err);
            return error.WindowMap;
        }
    }

    fn poll(self: PlatformXcb) Platform.Input {
        var input = Platform.Input{};
        while (c.xcb_poll_for_event(self.connection)) |event| {
            defer std.c.free(event);
            switch (event.*.response_type & 127) {
                c.XCB_KEY_PRESS => {
                    const evt: *const c.xcb_key_press_event_t = @ptrCast(event);
                    const key = evt.detail - 8;
                    switch (key) {
                        1 => input.done = true,
                        2 => input.option = true,
                        3 => input.option_2 = true,
                        103 => input.up = true,
                        105 => input.left = true,
                        106 => input.right = true,
                        108 => input.down = true,
                        else => {},
                    }
                },
                c.XCB_KEY_RELEASE => {},
                c.XCB_BUTTON_PRESS => {},
                c.XCB_BUTTON_RELEASE => {},
                c.XCB_MOTION_NOTIFY => {},
                c.XCB_ENTER_NOTIFY => {},
                c.XCB_LEAVE_NOTIFY => {},
                c.XCB_FOCUS_IN => {},
                c.XCB_FOCUS_OUT => {},
                c.XCB_EXPOSE => {},
                c.XCB_CONFIGURE_NOTIFY => {},
                c.XCB_CLIENT_MESSAGE => {},
                else => {},
            }
        }
        return input;
    }

    fn deinit(self: *PlatformXcb) void {
        _ = c.xcb_destroy_window(self.connection, self.window);
        c.xcb_disconnect(self.connection);
        self.* = undefined;
    }
};
