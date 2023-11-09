const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const Instance = ngl.Instance;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");
const c = @import("../impl/c.zig");

pub const Surface = struct {
    impl: Impl.Surface,

    const Android = struct {
        window: *c.struct_ANativeWindow,
    };
    const Wayland = struct {
        display: *c.struct_wl_display,
        surface: *c.struct_wl_surface,
    };
    const Win32 = struct {
        hinstance: c.HINSTANCE,
        hwnd: c.HWND,
    };
    const Xcb = struct {
        connection: *c.xcb_connection_t,
        window: c.xcb_window_t,
    };

    // TODO: OS-agnostic platform
    pub const Platform = @Type(.{ .Union = .{
        .layout = .Auto,
        .tag_type = switch (builtin.os.tag) {
            .linux => if (builtin.target.isAndroid()) enum { android } else enum { wayland, xcb },
            .windows => enum { win32 },
            else => enum {},
        },
        .fields = blk: {
            const UnionField = std.builtin.Type.UnionField;
            var fields: []const UnionField = switch (builtin.os.tag) {
                .linux => if (builtin.target.isAndroid()) &[_]UnionField{.{
                    .name = "android",
                    .type = Android,
                    .alignment = @alignOf(Android),
                }} else &[_]UnionField{
                    .{
                        .name = "wayland",
                        .type = Wayland,
                        .alignment = @alignOf(Wayland),
                    },
                    .{
                        .name = "xcb",
                        .type = Xcb,
                        .alignment = @alignOf(Xcb),
                    },
                },
                .windows => &[_]UnionField{.{
                    .name = "win32",
                    .type = Win32,
                    .alignment = @alignOf(Win32),
                }},
                else => &[_]UnionField{},
            };
            break :blk fields;
        },
        .decls = &.{},
    } });

    pub const Desc = struct {
        platform: Platform,
    };

    const Self = @This();

    /// It's only valid to call this function if the instance was created
    /// with `Instance.Desc.presentation` set to `true`.
    pub fn init(allocator: std.mem.Allocator, instance: *Instance, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSurface(allocator, instance.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, instance: *Instance) void {
        Impl.get().deinitSurface(allocator, instance.impl, self.impl);
        self.* = undefined;
    }
};
