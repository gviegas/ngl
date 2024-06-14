//! A highly simplified window system implementation for use in
//! tests and sample programs.

const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("ngl.zig");
const c = @import("inc.zig");

pub const Platform = struct {
    impl: switch (builtin.os.tag) {
        .linux => if (builtin.target.isAndroid()) PlatformAndroid else PlatformWayland,
        .windows => PlatformWin32,
        else => @compileError("OS not supported"),
    },
    surface: ngl.Surface,
    format: ngl.Surface.Format,
    swapchain: ngl.Swapchain,
    images: []ngl.Image,
    image_views: []ngl.ImageView,
    width: u32,
    height: u32,
    queue_index: ngl.Queue.Index,
    mutex: std.Thread.Mutex = .{},

    pub const Desc = struct {
        width: u32,
        height: u32,
        // TODO...
    };

    pub const Input = packed struct {
        done: bool = false,
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
        option: bool = false,
        option_2: bool = false,
    };

    pub const Error = ngl.Error || @typeInfo(Platform).Struct.fields[0].type.Error;

    /// Call this once.
    // TODO: Detect misuse.
    pub fn init(
        allocator: std.mem.Allocator,
        gpu: ngl.Gpu,
        device: *ngl.Device,
        desc: Desc,
    ) Error!Platform {
        if (!gpu.feature_set.presentation)
            return error.NotSupported;

        var impl = try @typeInfo(Platform).Struct.fields[0].type.init(allocator);
        errdefer impl.deinit(allocator);

        var sf = try switch (builtin.os.tag) {
            .linux => if (builtin.target.isAndroid())
                @compileError("TODO")
            else
                ngl.Surface.init(allocator, .{
                    .platform = .{
                        .wayland = .{
                            .display = impl.display,
                            .surface = impl.surface,
                        },
                    },
                }),
            .windows => @compileError("TODO"),
            else => @compileError("OS not supported"),
        };
        errdefer sf.deinit(allocator);

        const fmt = blk: {
            const fmts = try sf.getFormats(allocator, gpu);
            defer allocator.free(fmts);
            for (fmts) |fmt| {
                // TODO
                break :blk fmt;
            } else unreachable;
        };
        const capab = try sf.getCapabilities(gpu, .fifo);

        var sc = try ngl.Swapchain.init(allocator, device, .{
            .surface = &sf,
            .min_count = capab.min_count,
            .format = fmt.format,
            .color_space = fmt.color_space,
            .width = desc.width,
            .height = desc.height,
            .layers = 1,
            .usage = .{ .color_attachment = true },
            .pre_transform = capab.current_transform,
            .composite_alpha = blk: {
                const CAlpha = ngl.Surface.CompositeAlpha;
                const fields = @typeInfo(CAlpha).Enum.fields;
                break :blk inline for (fields) |f| {
                    if (@field(capab.supported_composite_alpha, f.name))
                        break @field(CAlpha, f.name);
                } else unreachable;
            },
            .present_mode = .fifo, // TODO: Not the best choice for Wayland.
            .clipped = true,
            .old_swapchain = null,
        });
        errdefer sc.deinit(allocator, device);

        const imgs = try sc.getImages(allocator, device);
        errdefer allocator.free(imgs);

        var views = try allocator.alloc(ngl.ImageView, imgs.len);
        errdefer allocator.free(views);
        for (views, imgs, 0..) |*view, *img, i|
            view.* = ngl.ImageView.init(allocator, device, .{
                .image = img,
                .type = .@"2d",
                .format = fmt.format,
                .range = .{
                    .aspect_mask = .{ .color = true },
                    .level = 0,
                    .levels = 1,
                    .layer = 0,
                    .layers = 1,
                },
            }) catch |err| {
                for (0..i) |j|
                    views[j].deinit(allocator, device);
                return err;
            };

        const que_idx = for (gpu.queues, 0..) |que_desc, i| {
            if (que_desc == null)
                continue;
            const que_idx = @as(ngl.Queue.Index, @intCast(i));
            const is = sf.isCompatible(gpu, que_idx) catch continue;
            if (is)
                break que_idx;
        } else return Error.NotSupported;

        return .{
            .impl = impl,
            .surface = sf,
            .format = fmt,
            .swapchain = sc,
            .images = imgs,
            .image_views = views,
            .width = desc.width,
            .height = desc.height,
            .queue_index = que_idx,
        };
    }

    pub fn poll(self: *Platform) Input {
        return self.impl.poll();
    }

    pub fn lock(self: *Platform) void {
        self.mutex.lock();
    }

    pub fn unlock(self: *Platform) void {
        self.mutex.unlock();
    }

    pub fn deinit(self: *Platform, allocator: std.mem.Allocator, device: *ngl.Device) void {
        for (self.image_views) |*view|
            view.deinit(allocator, device);
        allocator.free(self.image_views);
        allocator.free(self.images);
        self.swapchain.deinit(allocator, device);
        self.surface.deinit(allocator);
        self.impl.deinit(allocator);
        self.* = undefined;
    }
};

// TODO
const PlatformAndroid = struct {
    const Error = error{};

    fn init(_: std.mem.Allocator) Error!PlatformAndroid {
        @compileError("TODO");
    }

    fn poll(_: *PlatformAndroid) Platform.Input {
        @compileError("TODO");
    }

    fn deinit(_: *PlatformAndroid, _: std.mem.Allocator) void {
        @compileError("TODO");
    }
};

const PlatformWayland = struct {
    display: *c.struct_wl_display,
    surface: *c.struct_wl_surface,
    pinned: *Pinned,

    const Pinned = struct {
        // These shouldn't be `null`.
        compositor: ?*c.struct_wl_compositor,
        xdg_wm_base: ?*c.struct_xdg_wm_base,
        shm: ?*c.struct_wl_shm,
        seat: ?*c.struct_wl_seat,
        output: ?*c.struct_wl_output,

        // These may be `null`.
        pointer: ?*c.struct_wl_pointer,
        keyboard: ?*c.struct_wl_keyboard,
        touch: ?*c.struct_wl_touch,

        input: Platform.Input = .{},
    };

    const Error = error{
        Lib,
        Sym,
        Connection,
        Registry,
        Listener,
        Missing,
        Surface,
        XdgSurface,
        XdgToplevel,
    } || std.mem.Allocator.Error;

    fn init(allocator: std.mem.Allocator) Error!PlatformWayland {
        try setVars();

        const display = displayConnect(null) orelse return Error.Connection;

        const pinned = try allocator.create(Pinned);
        errdefer allocator.destroy(pinned);
        pinned.* = .{
            .compositor = null,
            .xdg_wm_base = null,
            .shm = null,
            .seat = null,
            .output = null,
            .pointer = null,
            .keyboard = null,
            .touch = null,
        };

        const registry = req.displayGetRegistry(display) orelse return Error.Registry;
        if (req.registryAddListener(registry, &evt.registry_listener, pinned) != 0)
            return Error.Listener;

        _ = displayRoundtrip(display);

        if (pinned.compositor == null or
            pinned.xdg_wm_base == null or
            pinned.shm == null or
            pinned.seat == null or
            pinned.output == null)
        {
            return Error.Missing;
        }

        const surface = req.compositorCreateSurface(pinned.compositor.?) orelse
            return Error.Surface;
        if (req.surfaceAddListener(surface, &evt.surface_listener, pinned) != 0)
            return Error.Listener;

        if (req.xdgWmBaseAddListener(pinned.xdg_wm_base.?, &evt.xdg_wm_base_listener, pinned) != 0)
            return Error.Listener;

        const xdg_surface = req.xdgWmBaseGetXdgSurface(pinned.xdg_wm_base.?, surface) orelse
            return Error.XdgSurface;
        if (req.xdgSurfaceAddListener(xdg_surface, &evt.xdg_surface_listener, pinned) != 0)
            return Error.Listener;

        const xdg_toplevel = req.xdgSurfaceGetToplevel(xdg_surface) orelse
            return Error.XdgToplevel;
        if (req.xdgToplevelAddListener(xdg_toplevel, &evt.xdg_toplevel_listener, pinned) != 0)
            return Error.Listener;

        if (req.seatAddListener(pinned.seat.?, &evt.seat_listener, pinned) != 0)
            return Error.Listener;

        _ = displayRoundtrip(display);

        if (pinned.pointer) |pointer|
            if (req.pointerAddListener(pointer, &evt.pointer_listener, pinned) != 0)
                return Error.Listener;

        if (pinned.keyboard) |keyboard|
            if (req.keyboardAddListener(keyboard, &evt.keyboard_listener, pinned) != 0)
                return Error.Listener;

        if (pinned.touch) |touch|
            // TODO
            _ = touch;

        _ = displayRoundtrip(display);

        // TODO: Should poll in case of error.
        _ = displayFlush(display);

        return .{
            .display = display,
            .surface = surface,
            .pinned = pinned,
        };
    }

    fn poll(self: *PlatformWayland) Platform.Input {
        // TODO: Should poll in case of error.
        _ = displayFlush(self.display);
        _ = displayDispatchPending(self.display);
        return self.pinned.input;
    }

    fn deinit(self: *PlatformWayland, allocator: std.mem.Allocator) void {
        // TODO: Destroy objects.
        allocator.destroy(self.pinned);
        displayDisconnect(self.display);
        _ = std.c.dlclose(lib);
    }

    fn setVars() Error!void {
        const lib_name = "libwayland-client.so";
        lib = std.c.dlopen(lib_name, c.RTLD_LAZY | c.RTLD_LOCAL) orelse return Error.Lib;
        errdefer _ = std.c.dlclose(lib);

        displayConnect = @ptrCast(std.c.dlsym(lib, "wl_display_connect") orelse return Error.Sym);
        displayDisconnect = @ptrCast(std.c.dlsym(lib, "wl_display_disconnect") orelse return Error.Sym);
        displayDispatch = @ptrCast(std.c.dlsym(lib, "wl_display_dispatch") orelse return Error.Sym);
        displayDispatchPending = @ptrCast(std.c.dlsym(lib, "wl_display_dispatch_pending") orelse return Error.Sym);
        displayFlush = @ptrCast(std.c.dlsym(lib, "wl_display_flush") orelse return Error.Sym);
        displayRoundtrip = @ptrCast(std.c.dlsym(lib, "wl_display_roundtrip") orelse return Error.Sym);
        proxyMarshalFlags = @ptrCast(std.c.dlsym(lib, "wl_proxy_marshal_flags") orelse return Error.Sym);
        proxyAddListener = @ptrCast(std.c.dlsym(lib, "wl_proxy_add_listener") orelse return Error.Sym);
        proxyGetVersion = @ptrCast(std.c.dlsym(lib, "wl_proxy_get_version") orelse return Error.Sym);

        xdg_surface_types[2] = &xdg_surface_interface;
        xdg_toplevel_types[0] = &xdg_toplevel_interface;
    }

    var lib: *anyopaque = undefined;

    var displayConnect: *const @TypeOf(c.wl_display_connect) = undefined;
    var displayDisconnect: *const @TypeOf(c.wl_display_disconnect) = undefined;
    var displayDispatch: *const @TypeOf(c.wl_display_dispatch) = undefined;
    var displayDispatchPending: *const @TypeOf(c.wl_display_dispatch_pending) = undefined;
    var displayFlush: *const @TypeOf(c.wl_display_flush) = undefined;
    var displayRoundtrip: *const @TypeOf(c.wl_display_roundtrip) = undefined;
    var proxyMarshalFlags: *const @TypeOf(c.wl_proxy_marshal_flags) = undefined;
    var proxyAddListener: *const @TypeOf(c.wl_proxy_add_listener) = undefined;
    var proxyGetVersion: *const @TypeOf(c.wl_proxy_get_version) = undefined;

    var null_types = [_]?*const c.struct_wl_interface{null} ** 8;

    const wl_callback_interface = c.struct_wl_interface{
        .name = "wl_callback",
        .version = 1,
        .method_count = 0,
        .methods = null,
        .event_count = 1,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "done",
            .signature = "u",
            .types = &null_types,
        }})),
    };

    const wl_registry_interface = c.struct_wl_interface{
        .name = "wl_registry",
        .version = 1,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "bind",
            .signature = "usun",
            .types = &null_types,
        }})),
        .event_count = 2,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "global",
                .signature = "usu",
                .types = &null_types,
            },
            .{
                .name = "global_remove",
                .signature = "u",
                .types = &null_types,
            },
        })),
    };

    var wl_compositor_types = [_]?*const c.struct_wl_interface{
        &wl_surface_interface,
        &wl_region_interface,
    };

    const wl_compositor_interface = c.struct_wl_interface{
        .name = "wl_compositor",
        .version = 5,
        .method_count = 2,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "create_surface",
                .signature = "n",
                .types = wl_compositor_types[0..1],
            },
            .{
                .name = "create_region",
                .signature = "n",
                .types = wl_compositor_types[1..2],
            },
        })),
        .event_count = 0,
        .events = null,
    };

    var wl_surface_types = [_]?*const c.struct_wl_interface{
        &wl_buffer_interface,
        null,
        null,
        &wl_callback_interface,
        &wl_region_interface,
        &wl_output_interface,
    };

    const wl_surface_interface = c.struct_wl_interface{
        .name = "wl_surface",
        .version = 5,
        .method_count = 11,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "attach",
                .signature = "?oii",
                .types = wl_surface_types[0..3],
            },
            .{
                .name = "damage",
                .signature = "iiii",
                .types = &null_types,
            },
            .{
                .name = "frame",
                .signature = "n",
                .types = wl_surface_types[3..4],
            },
            .{
                .name = "set_opaque_region",
                .signature = "?o",
                .types = wl_surface_types[4..5],
            },
            .{
                .name = "set_input_region",
                .signature = "?o",
                .types = wl_surface_types[4..5],
            },
            .{
                .name = "commit",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "set_buffer_transform",
                .signature = "2i",
                .types = &null_types,
            },
            .{
                .name = "set_buffer_scale",
                .signature = "3i",
                .types = &null_types,
            },
            .{
                .name = "damage_buffer",
                .signature = "4iiii",
                .types = &null_types,
            },
            .{
                .name = "offset",
                .signature = "5ii",
                .types = &null_types,
            },
        })),
        .event_count = 2,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "enter",
                .signature = "o",
                .types = wl_surface_types[5..6],
            },
            .{
                .name = "leave",
                .signature = "o",
                .types = wl_surface_types[5..6],
            },
        })),
    };

    const wl_region_interface = c.struct_wl_interface{
        .name = "wl_region",
        .version = 1,
        .method_count = 3,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "add",
                .signature = "iiii",
                .types = &null_types,
            },
            .{
                .name = "subtract",
                .signature = "iiii",
                .types = &null_types,
            },
        })),
        .event_count = 0,
        .events = null,
    };

    var xdg_wm_base_types = [_]?*const c.struct_wl_interface{
        &xdg_positioner_interface,
        &xdg_surface_interface,
        &wl_surface_interface,
    };

    const xdg_wm_base_interface = c.struct_wl_interface{
        .name = "xdg_wm_base",
        .version = 4,
        .method_count = 4,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "create_positioner",
                .signature = "n",
                .types = xdg_wm_base_types[0..1],
            },
            .{
                .name = "get_xdg_surface",
                .signature = "no",
                .types = xdg_wm_base_types[1..3],
            },
            .{
                .name = "pong",
                .signature = "u",
                .types = &null_types,
            },
        })),
        .event_count = 1,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "ping",
            .signature = "u",
            .types = &null_types,
        }})),
    };

    const xdg_positioner_interface = c.struct_wl_interface{
        .name = "xdg_positioner",
        .version = 4,
        .method_count = 10,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "set_size",
                .signature = "ii",
                .types = &null_types,
            },
            .{
                .name = "set_anchor_rect",
                .signature = "iiii",
                .types = &null_types,
            },
            .{
                .name = "set_anchor",
                .signature = "u",
                .types = &null_types,
            },
            .{
                .name = "set_gravity",
                .signature = "u",
                .types = &null_types,
            },
            .{
                .name = "set_constraint_adjustment",
                .signature = "u",
                .types = &null_types,
            },
            .{
                .name = "set_offset",
                .signature = "ii",
                .types = &null_types,
            },
            .{
                .name = "set_reactive",
                .signature = "3",
                .types = &null_types,
            },
            .{
                .name = "set_parent_size",
                .signature = "3ii",
                .types = &null_types,
            },
            .{
                .name = "set_parent_configure",
                .signature = "3u",
                .types = &null_types,
            },
        })),
        .event_count = 0,
        .events = null,
    };

    var xdg_surface_types = [_]?*const c.struct_wl_interface{
        &xdg_toplevel_interface,
        &xdg_popup_interface,
        // error: dependency loop detected
        //&xdg_surface_interface,
        undefined,
        &xdg_positioner_interface,
    };

    const xdg_surface_interface = c.struct_wl_interface{
        .name = "xdg_surface",
        .version = 4,
        .method_count = 5,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "get_toplevel",
                .signature = "n",
                .types = xdg_surface_types[0..1],
            },
            .{
                .name = "get_popup",
                .signature = "n?oo",
                .types = xdg_surface_types[1..4],
            },
            .{
                .name = "set_window_geometry",
                .signature = "iiii",
                .types = &null_types,
            },
            .{
                .name = "ack_configure",
                .signature = "u",
                .types = &null_types,
            },
        })),
        .event_count = 1,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "configure",
            .signature = "u",
            .types = &null_types,
        }})),
    };

    var xdg_toplevel_types = [_]?*const c.struct_wl_interface{
        // error: dependency loop detected
        //&xdg_toplevel_interface,
        undefined,
        &wl_seat_interface,
        null,
        null,
        null,
        &wl_output_interface,
    };

    const xdg_toplevel_interface = c.struct_wl_interface{
        .name = "xdg_toplevel",
        .version = 4,
        .method_count = 14,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "set_parent",
                .signature = "?o",
                .types = xdg_toplevel_types[0..1],
            },
            .{
                .name = "set_title",
                .signature = "s",
                .types = &null_types,
            },
            .{
                .name = "set_app_id",
                .signature = "s",
                .types = &null_types,
            },
            .{
                .name = "show_window_menu",
                .signature = "ouii",
                .types = xdg_toplevel_types[1..5],
            },
            .{
                .name = "move",
                .signature = "ou",
                .types = xdg_toplevel_types[1..3],
            },
            .{
                .name = "resize",
                .signature = "ouu",
                .types = xdg_toplevel_types[1..4],
            },
            .{
                .name = "set_max_size",
                .signature = "ii",
                .types = &null_types,
            },
            .{
                .name = "set_min_size",
                .signature = "ii",
                .types = &null_types,
            },
            .{
                .name = "set_maximized",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "unset_maximized",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "set_fullscreen",
                .signature = "?o",
                .types = xdg_toplevel_types[5..6],
            },
            .{
                .name = "unset_fullscreen",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "set_minimized",
                .signature = "",
                .types = &null_types,
            },
        })),
        .event_count = 3,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "configure",
                .signature = "iia",
                .types = &null_types,
            },
            .{
                .name = "close",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "configure_bounds",
                .signature = "4ii",
                .types = &null_types,
            },
        })),
    };

    var xdg_popup_types = [_]?*const c.struct_wl_interface{
        &wl_seat_interface,
        null,
        &xdg_positioner_interface,
        null,
    };

    const xdg_popup_interface = c.struct_wl_interface{
        .name = "xdg_popup",
        .version = 4,
        .method_count = 3,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "grab",
                .signature = "ou",
                .types = xdg_popup_types[0..2],
            },
            .{
                .name = "reposition",
                .signature = "3ou",
                .types = xdg_popup_types[2..4],
            },
        })),
        .event_count = 3,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "configure",
                .signature = "iiii",
                .types = &null_types,
            },
            .{
                .name = "popup_done",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "repositioned",
                .signature = "3u",
                .types = &null_types,
            },
        })),
    };

    var wl_shm_types = [_]?*const c.struct_wl_interface{
        &wl_shm_pool_interface,
        null,
        null,
    };

    const wl_shm_interface = c.struct_wl_interface{
        .name = "wl_shm",
        .version = 1,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "create_pool",
            .signature = "nhi",
            .types = wl_shm_types[0..3],
        }})),
        .event_count = 1,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "format",
            .signature = "u",
            .types = &null_types,
        }})),
    };

    var wl_shm_pool_types = [_]?*const c.struct_wl_interface{
        &wl_buffer_interface,
        null,
        null,
        null,
        null,
        null,
    };

    const wl_shm_pool_interface = c.struct_wl_interface{
        .name = "wl_shm_pool",
        .version = 1,
        .method_count = 3,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "create_buffer",
                .signature = "niiiiu",
                .types = wl_shm_pool_types[0..6],
            },
            .{
                .name = "destroy",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "resize",
                .signature = "i",
                .types = &null_types,
            },
        })),
        .event_count = 0,
        .events = null,
    };

    const wl_buffer_interface = c.struct_wl_interface{
        .name = "wl_buffer",
        .version = 1,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "destroy",
            .signature = "",
            .types = &null_types,
        }})),
        .event_count = 1,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "release",
            .signature = "",
            .types = &null_types,
        }})),
    };

    var wl_seat_types = [_]?*const c.struct_wl_interface{
        &wl_pointer_interface,
        &wl_keyboard_interface,
        &wl_touch_interface,
    };

    const wl_seat_interface = c.struct_wl_interface{
        .name = "wl_seat",
        .version = 7,
        .method_count = 4,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "get_pointer",
                .signature = "n",
                .types = wl_seat_types[0..1],
            },
            .{
                .name = "get_keyboard",
                .signature = "n",
                .types = wl_seat_types[1..2],
            },
            .{
                .name = "get_touch",
                .signature = "n",
                .types = wl_seat_types[2..3],
            },
            .{
                .name = "release",
                .signature = "5",
                .types = &null_types,
            },
        })),
        .event_count = 2,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "capabilities",
                .signature = "u",
                .types = &null_types,
            },
            .{
                .name = "name",
                .signature = "2s",
                .types = &null_types,
            },
        })),
    };

    var wl_pointer_types = [_]?*const c.struct_wl_interface{
        null,
        &wl_surface_interface,
        null,
        null,
    };

    const wl_pointer_interface = c.struct_wl_interface{
        .name = "wl_pointer",
        .version = 7,
        .method_count = 2,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "set_cursor",
                .signature = "u?oii",
                .types = wl_pointer_types[0..4],
            },
            .{
                .name = "release",
                .signature = "3",
                .types = &null_types,
            },
        })),
        .event_count = 9,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "enter",
                .signature = "uoff",
                .types = wl_pointer_types[0..4],
            },
            .{
                .name = "leave",
                .signature = "uo",
                .types = wl_pointer_types[0..2],
            },
            .{
                .name = "motion",
                .signature = "uff",
                .types = &null_types,
            },
            .{
                .name = "button",
                .signature = "uuuu",
                .types = &null_types,
            },
            .{
                .name = "axis",
                .signature = "uuf",
                .types = &null_types,
            },
            .{
                .name = "frame",
                .signature = "5",
                .types = &null_types,
            },
            .{
                .name = "axis_source",
                .signature = "5u",
                .types = &null_types,
            },
            .{
                .name = "axis_stop",
                .signature = "5uu",
                .types = &null_types,
            },
            .{
                .name = "axis_discrete",
                .signature = "5ui",
                .types = &null_types,
            },
        })),
    };

    var wl_keyboard_types = [_]?*const c.struct_wl_interface{
        null,
        &wl_surface_interface,
        null,
    };

    const wl_keyboard_interface = c.struct_wl_interface{
        .name = "wl_keyboard",
        .version = 7,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "release",
            .signature = "3",
            .types = &null_types,
        }})),
        .event_count = 6,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "keymap",
                .signature = "uhu",
                .types = &null_types,
            },
            .{
                .name = "enter",
                .signature = "uoa",
                .types = wl_keyboard_types[0..3],
            },
            .{
                .name = "leave",
                .signature = "uo",
                .types = wl_keyboard_types[0..2],
            },
            .{
                .name = "key",
                .signature = "uuuu",
                .types = &null_types,
            },
            .{
                .name = "modifiers",
                .signature = "uuuuu",
                .types = &null_types,
            },
            .{
                .name = "repeat_info",
                .signature = "4ii",
                .types = &null_types,
            },
        })),
    };

    var wl_touch_types = [_]?*const c.struct_wl_interface{
        null,
        null,
        &wl_surface_interface,
        null,
        null,
        null,
    };

    const wl_touch_interface = c.struct_wl_interface{
        .name = "wl_touch",
        .version = 7,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "release",
            .signature = "3",
            .types = &null_types,
        }})),
        .event_count = 7,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "down",
                .signature = "uuoiff",
                .types = wl_touch_types[0..6],
            },
            .{
                .name = "up",
                .signature = "uui",
                .types = &null_types,
            },
            .{
                .name = "motion",
                .signature = "uiff",
                .types = &null_types,
            },
            .{
                .name = "frame",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "cancel",
                .signature = "",
                .types = &null_types,
            },
            .{
                .name = "shape",
                .signature = "6iff",
                .types = &null_types,
            },
            .{
                .name = "orientation",
                .signature = "6if",
                .types = &null_types,
            },
        })),
    };

    const wl_output_interface = c.struct_wl_interface{
        .name = "wl_output",
        .version = 4,
        .method_count = 1,
        .methods = @ptrCast(@as([]const c.struct_wl_message, &.{.{
            .name = "release",
            .signature = "3",
            .types = &null_types,
        }})),
        .event_count = 6,
        .events = @ptrCast(@as([]const c.struct_wl_message, &.{
            .{
                .name = "geometry",
                .signature = "iiiiissi",
                .types = &null_types,
            },
            .{
                .name = "mode",
                .signature = "uiii",
                .types = &null_types,
            },
            .{
                .name = "done",
                .signature = "2",
                .types = &null_types,
            },
            .{
                .name = "scale",
                .signature = "2i",
                .types = &null_types,
            },
            .{
                .name = "name",
                .signature = "4s",
                .types = &null_types,
            },
            .{
                .name = "description",
                .signature = "4s",
                .types = &null_types,
            },
        })),
    };

    const req = struct {
        fn displayGetRegistry(display: ?*c.struct_wl_display) ?*c.struct_wl_registry {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(display),
                c.WL_DISPLAY_GET_REGISTRY,
                &wl_registry_interface,
                proxyGetVersion(@ptrCast(display)),
                0,
                c.NULL,
            ));
        }

        fn registryBind(
            registry: ?*c.struct_wl_registry,
            name: u32,
            interface: ?*const c.struct_wl_interface,
            version: u32,
        ) ?*anyopaque {
            return proxyMarshalFlags(
                @ptrCast(registry),
                c.WL_REGISTRY_BIND,
                interface,
                version,
                0,
                name,
                interface.?.name,
                version,
                c.NULL,
            );
        }

        fn registryAddListener(
            registry: ?*c.struct_wl_registry,
            listener: *const c.struct_wl_registry_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(registry), @ptrCast(@constCast(listener)), data);
        }

        fn compositorCreateSurface(compositor: ?*c.struct_wl_compositor) ?*c.struct_wl_surface {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(compositor),
                c.WL_COMPOSITOR_CREATE_SURFACE,
                &wl_surface_interface,
                proxyGetVersion(@ptrCast(compositor)),
                0,
                c.NULL,
            ));
        }

        fn surfaceAddListener(
            surface: ?*c.struct_wl_surface,
            listener: *const c.struct_wl_surface_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(surface), @ptrCast(@constCast(listener)), data);
        }

        fn xdgWmBaseGetXdgSurface(
            xdg_wm_base: ?*c.struct_xdg_wm_base,
            surface: ?*c.struct_wl_surface,
        ) ?*c.struct_xdg_surface {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(xdg_wm_base),
                c.XDG_WM_BASE_GET_XDG_SURFACE,
                &xdg_surface_interface,
                proxyGetVersion(@ptrCast(xdg_wm_base)),
                0,
                c.NULL,
                surface,
            ));
        }

        fn xdgWmBaseAddListener(
            xdg_wm_base: ?*c.struct_xdg_wm_base,
            listener: ?*const c.struct_xdg_wm_base_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(xdg_wm_base), @ptrCast(@constCast(listener)), data);
        }

        fn xdgWmBasePong(xdg_wm_base: ?*c.struct_xdg_wm_base, serial: u32) void {
            _ = proxyMarshalFlags(
                @ptrCast(xdg_wm_base),
                c.XDG_WM_BASE_PONG,
                null,
                proxyGetVersion(@ptrCast(xdg_wm_base)),
                0,
                serial,
            );
        }

        fn xdgSurfaceGetToplevel(xdg_surface: ?*c.struct_xdg_surface) ?*c.struct_xdg_toplevel {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(xdg_surface),
                c.XDG_SURFACE_GET_TOPLEVEL,
                &xdg_toplevel_interface,
                proxyGetVersion(@ptrCast(xdg_surface)),
                0,
                c.NULL,
            ));
        }

        fn xdgSurfaceAddListener(
            xdg_surface: ?*c.struct_xdg_surface,
            listener: *const c.struct_xdg_surface_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(xdg_surface), @ptrCast(@constCast(listener)), data);
        }

        fn xdgSurfaceAckConfigure(xdg_surface: ?*c.struct_xdg_surface, serial: u32) void {
            _ = proxyMarshalFlags(
                @ptrCast(xdg_surface),
                c.XDG_SURFACE_ACK_CONFIGURE,
                null,
                proxyGetVersion(@ptrCast(xdg_surface)),
                0,
                serial,
            );
        }

        fn xdgToplevelAddListener(
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            listener: *const c.struct_xdg_toplevel_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(xdg_toplevel), @ptrCast(@constCast(listener)), data);
        }

        fn seatGetPointer(seat: ?*c.struct_wl_seat) ?*c.struct_wl_pointer {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(seat),
                c.WL_SEAT_GET_POINTER,
                &wl_pointer_interface,
                proxyGetVersion(@ptrCast(seat)),
                0,
                c.NULL,
            ));
        }

        fn seatGetKeyboard(seat: ?*c.struct_wl_seat) ?*c.struct_wl_keyboard {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(seat),
                c.WL_SEAT_GET_KEYBOARD,
                &wl_keyboard_interface,
                proxyGetVersion(@ptrCast(seat)),
                0,
                c.NULL,
            ));
        }

        fn seatGetTouch(seat: ?*c.struct_wl_seat) ?*c.struct_wl_touch {
            return @ptrCast(proxyMarshalFlags(
                @ptrCast(seat),
                c.WL_SEAT_GET_TOUCH,
                &wl_touch_interface,
                proxyGetVersion(@ptrCast(seat)),
                0,
                c.NULL,
            ));
        }

        fn seatAddListener(
            seat: ?*c.struct_wl_seat,
            listener: *const c.struct_wl_seat_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(seat), @ptrCast(@constCast(listener)), data);
        }

        fn pointerAddListener(
            pointer: ?*c.struct_wl_pointer,
            listener: *const c.struct_wl_pointer_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(pointer), @ptrCast(@constCast(listener)), data);
        }

        fn pointerSetCursor(
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            surface: ?*c.struct_wl_surface,
            hotspot_x: i32,
            hotspot_y: i32,
        ) void {
            _ = proxyMarshalFlags(
                @ptrCast(pointer),
                c.WL_POINTER_SET_CURSOR,
                null,
                proxyGetVersion(@ptrCast(pointer)),
                0,
                serial,
                surface,
                hotspot_x,
                hotspot_y,
            );
        }

        fn keyboardAddListener(
            keyboard: ?*c.struct_wl_keyboard,
            listener: *const c.struct_wl_keyboard_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(keyboard), @ptrCast(@constCast(listener)), data);
        }

        fn touchAddListener(
            touch: ?*c.struct_wl_touch,
            listener: *const c.struct_wl_touch_listener,
            data: ?*anyopaque,
        ) c_int {
            return proxyAddListener(@ptrCast(touch), @ptrCast(@constCast(listener)), data);
        }
    };

    const evt = struct {
        const registry_listener = c.struct_wl_registry_listener{
            .global = registryGlobal,
            .global_remove = registryGlobalRemove,
        };

        fn registryGlobal(
            data: ?*anyopaque,
            registry: ?*c.struct_wl_registry,
            name: u32,
            interface: ?[*:0]const u8,
            version: u32,
        ) callconv(.C) void {
            const pinned: *Pinned = @ptrCast(@alignCast(data));
            const ifc = interface orelse return;
            const vers: c_int = if (version <= std.math.maxInt(c_int))
                @intCast(version)
            else
                return;

            if (std.mem.orderZ(u8, "wl_compositor", ifc) == .eq) {
                pinned.compositor = @ptrCast(req.registryBind(
                    registry,
                    name,
                    &wl_compositor_interface,
                    @intCast(@min(vers, wl_compositor_interface.version)),
                ));
            } else if (std.mem.orderZ(u8, "xdg_wm_base", ifc) == .eq) {
                pinned.xdg_wm_base = @ptrCast(req.registryBind(
                    registry,
                    name,
                    &xdg_wm_base_interface,
                    @intCast(@min(vers, xdg_wm_base_interface.version)),
                ));
            } else if (std.mem.orderZ(u8, "wl_shm", ifc) == .eq) {
                pinned.shm = @ptrCast(req.registryBind(
                    registry,
                    name,
                    &wl_shm_interface,
                    @intCast(@min(vers, wl_shm_interface.version)),
                ));
            } else if (std.mem.orderZ(u8, "wl_seat", ifc) == .eq) {
                pinned.seat = @ptrCast(req.registryBind(
                    registry,
                    name,
                    &wl_seat_interface,
                    @intCast(@min(vers, wl_seat_interface.version)),
                ));
            } else if (std.mem.orderZ(u8, "wl_output", ifc) == .eq) {
                pinned.output = @ptrCast(req.registryBind(
                    registry,
                    name,
                    &wl_output_interface,
                    @intCast(@min(vers, wl_output_interface.version)),
                ));
            }
        }

        fn registryGlobalRemove(
            data: ?*anyopaque,
            registry: ?*c.struct_wl_registry,
            name: u32,
        ) callconv(.C) void {
            // TODO: Should handle this.
            _ = data;
            _ = registry;
            _ = name;
        }

        const surface_listener = c.struct_wl_surface_listener{
            .enter = surfaceEnter,
            .leave = surfaceLeave,
        };

        fn surfaceEnter(
            data: ?*anyopaque,
            surface: ?*c.struct_wl_surface,
            output: ?*c.struct_wl_output,
        ) callconv(.C) void {
            _ = data;
            _ = surface;
            _ = output;
        }

        fn surfaceLeave(
            data: ?*anyopaque,
            surface: ?*c.struct_wl_surface,
            output: ?*c.struct_wl_output,
        ) callconv(.C) void {
            _ = data;
            _ = surface;
            _ = output;
        }

        const xdg_wm_base_listener = c.struct_xdg_wm_base_listener{
            .ping = xdgWmBasePing,
        };

        fn xdgWmBasePing(
            data: ?*anyopaque,
            xdg_wm_base: ?*c.struct_xdg_wm_base,
            serial: u32,
        ) callconv(.C) void {
            _ = data;

            req.xdgWmBasePong(xdg_wm_base, serial);
        }

        const xdg_surface_listener = c.struct_xdg_surface_listener{
            .configure = xdgSurfaceConfigure,
        };

        fn xdgSurfaceConfigure(
            data: ?*anyopaque,
            xdg_surface: ?*c.struct_xdg_surface,
            serial: u32,
        ) callconv(.C) void {
            _ = data;

            req.xdgSurfaceAckConfigure(xdg_surface, serial);
        }

        const xdg_toplevel_listener = c.struct_xdg_toplevel_listener{
            .configure = xdgToplevelConfigure,
            .close = xdgToplevelClose,
            .configure_bounds = xdgToplevelConfigureBounds,
        };

        fn xdgToplevelConfigure(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            width: i32,
            height: i32,
            states: ?*c.struct_wl_array,
        ) callconv(.C) void {
            _ = data;
            _ = xdg_toplevel;
            _ = width;
            _ = height;
            _ = states;
        }

        fn xdgToplevelClose(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
        ) callconv(.C) void {
            _ = xdg_toplevel;

            const pinned: *Pinned = @ptrCast(@alignCast(data));
            pinned.input.done = true;
        }

        fn xdgToplevelConfigureBounds(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            width: i32,
            height: i32,
        ) callconv(.C) void {
            _ = data;
            _ = xdg_toplevel;
            _ = width;
            _ = height;
        }

        const seat_listener = c.struct_wl_seat_listener{
            .capabilities = seatCapabilities,
            .name = seatName,
        };

        fn seatCapabilities(
            data: ?*anyopaque,
            seat: ?*c.struct_wl_seat,
            capabilities: u32,
        ) callconv(.C) void {
            const pinned: *Pinned = @ptrCast(@alignCast(data));

            if (capabilities & c.WL_SEAT_CAPABILITY_POINTER != 0)
                pinned.pointer = req.seatGetPointer(seat);
            if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0)
                pinned.keyboard = req.seatGetKeyboard(seat);
            if (capabilities & c.WL_SEAT_CAPABILITY_TOUCH != 0)
                pinned.touch = req.seatGetTouch(seat);
        }

        fn seatName(
            data: ?*anyopaque,
            seat: ?*c.struct_wl_seat,
            name: ?[*:0]const u8,
        ) callconv(.C) void {
            _ = data;
            _ = seat;
            _ = name;
        }

        const pointer_listener = c.struct_wl_pointer_listener{
            .enter = pointerEnter,
            .leave = pointerLeave,
            .motion = pointerMotion,
            .button = pointerButton,
            .axis = pointerAxis,
            .frame = pointerFrame,
            .axis_source = pointerAxisSource,
            .axis_stop = pointerAxisStop,
            .axis_discrete = pointerAxisDiscrete,
        };

        fn pointerEnter(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            surface: ?*c.struct_wl_surface,
            surface_x: c.wl_fixed_t,
            surface_y: c.wl_fixed_t,
        ) callconv(.C) void {
            _ = data;
            _ = surface;
            _ = surface_x;
            _ = surface_y;

            req.pointerSetCursor(pointer, serial, null, 0, 0);
        }

        fn pointerLeave(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            surface: ?*c.struct_wl_surface,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = serial;
            _ = surface;
        }

        fn pointerMotion(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            surface_x: c.wl_fixed_t,
            surface_y: c.wl_fixed_t,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = time;
            _ = surface_x;
            _ = surface_y;
        }

        fn pointerButton(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            time: u32,
            button: u32,
            state: u32,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = serial;
            _ = time;
            _ = button;
            _ = state;
        }

        fn pointerAxis(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            axis: u32,
            value: c.wl_fixed_t,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = time;
            _ = axis;
            _ = value;
        }

        fn pointerFrame(data: ?*anyopaque, pointer: ?*c.struct_wl_pointer) callconv(.C) void {
            _ = data;
            _ = pointer;
        }

        fn pointerAxisSource(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis_source: u32,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = axis_source;
        }

        fn pointerAxisStop(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            axis: u32,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = time;
            _ = axis;
        }

        fn pointerAxisDiscrete(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis: u32,
            discrete: i32,
        ) callconv(.C) void {
            _ = data;
            _ = pointer;
            _ = axis;
            _ = discrete;
        }

        const keyboard_listener = c.struct_wl_keyboard_listener{
            .keymap = keyboardKeymap,
            .enter = keyboardEnter,
            .leave = keyboardLeave,
            .key = keyboardKey,
            .modifiers = keyboardModifiers,
            .repeat_info = keyboardRepeatInfo,
        };

        fn keyboardKeymap(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            format: u32,
            fd: i32,
            size: u32,
        ) callconv(.C) void {
            _ = data;
            _ = keyboard;
            _ = format;
            _ = fd;
            _ = size;
        }

        fn keyboardEnter(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            surface: ?*c.struct_wl_surface,
            keys: ?*c.struct_wl_array,
        ) callconv(.C) void {
            _ = data;
            _ = keyboard;
            _ = serial;
            _ = surface;
            _ = keys;
        }

        fn keyboardLeave(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            surface: ?*c.struct_wl_surface,
        ) callconv(.C) void {
            _ = data;
            _ = keyboard;
            _ = serial;
            _ = surface;
        }

        fn keyboardKey(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            time: u32,
            key: u32,
            state: u32,
        ) callconv(.C) void {
            _ = keyboard;
            _ = serial;
            _ = time;

            const pinned: *Pinned = @ptrCast(@alignCast(data));
            const pressed = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;

            switch (key) {
                1 => pinned.input.done = pressed,
                2 => pinned.input.option = pressed,
                3 => pinned.input.option_2 = pressed,
                103 => pinned.input.up = pressed,
                105 => pinned.input.left = pressed,
                106 => pinned.input.right = pressed,
                108 => pinned.input.down = pressed,
                else => {},
            }
        }

        fn keyboardModifiers(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            mods_depressed: u32,
            mods_latched: u32,
            mods_locked: u32,
            group: u32,
        ) callconv(.C) void {
            _ = data;
            _ = keyboard;
            _ = serial;
            _ = mods_depressed;
            _ = mods_latched;
            _ = mods_locked;
            _ = group;
        }

        fn keyboardRepeatInfo(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            rate: i32,
            delay: i32,
        ) callconv(.C) void {
            _ = data;
            _ = keyboard;
            _ = rate;
            _ = delay;
        }
    };
};

// TODO
const PlatformWin32 = struct {
    const Error = error{};

    fn init(_: std.mem.Allocator) Error!PlatformWin32 {
        @compileError("TODO");
    }

    fn poll(_: *PlatformWin32) Platform.Input {
        @compileError("TODO");
    }

    fn deinit(_: *PlatformWin32, _: std.mem.Allocator) void {
        @compileError("TODO");
    }
};
