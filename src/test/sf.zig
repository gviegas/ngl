const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
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

        self.window = try self.createWindow(480, 270);
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

    fn poll(self: PlatformXcb) usize {
        var n: usize = 0;
        while (c.xcb_poll_for_event(self.connection)) |event| {
            defer std.c.free(event);
            n += 1;
            switch (event.*.response_type & 127) {
                c.XCB_KEY_PRESS, c.XCB_KEY_RELEASE => {},
                c.XCB_BUTTON_PRESS, c.XCB_BUTTON_RELEASE => {},
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
        return n;
    }

    fn deinit(self: *PlatformXcb) void {
        _ = c.xcb_destroy_window(self.connection, self.window);
        c.xcb_disconnect(self.connection);
        self.* = undefined;
    }
};
