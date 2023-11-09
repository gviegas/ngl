const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const check = conv.check;
const Instance = @import("init.zig").Instance;

pub const Surface = packed struct {
    handle: c.VkSurfaceKHR,

    pub inline fn cast(impl: Impl.Surface) Surface {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        instance: Impl.Instance,
        desc: ngl.Surface.Desc,
    ) Error!Impl.Surface {
        const inst = Instance.cast(instance);

        var surface: c.VkSurfaceKHR = undefined;

        switch (builtin.os.tag) {
            .linux => if (builtin.target.isAndroid()) {
                switch (desc.platform) {
                    .android => |x| try check(inst.vkCreateAndroidSurfaceKHR(&.{
                        .sType = c.VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR,
                        .pNext = null,
                        .flags = 0,
                        .window = x.window,
                    }, null, &surface)),
                }
            } else {
                switch (desc.platform) {
                    .wayland => |x| try check(inst.vkCreateWaylandSurfaceKHR(&.{
                        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                        .pNext = null,
                        .flags = 0,
                        .display = x.display,
                        .surface = x.surface,
                    }, null, &surface)),
                    .xcb => |x| try check(inst.vkCreateXcbSurfaceKHR(&.{
                        .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                        .pNext = null,
                        .flags = 0,
                        .connection = x.connection,
                        .window = x.window,
                    }, null, &surface)),
                }
            },
            .windows => switch (desc.platform) {
                .win32 => |x| try check(inst.vkCreateWin32SurfaceKHR(&.{
                    .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                    .pNext = null,
                    .flags = 0,
                    .hinstance = x.hinstance,
                    .hwnd = x.hwnd,
                }, null, &surface)),
            },
            else => @compileError("OS not supported"),
        }

        return .{ .val = @bitCast(Surface{ .handle = surface }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        instance: Impl.Instance,
        surface: Impl.Surface,
    ) void {
        Instance.cast(instance).vkDestroySurfaceKHR(cast(surface).handle, null);
    }
};
