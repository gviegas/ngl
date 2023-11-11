const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const Instance = ngl.Instance;
const Device = ngl.Device;
const Queue = ngl.Queue;
const Format = ngl.Format;
const Image = ngl.Image;
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

    // TODO: Other color spaces
    pub const ColorSpace = enum {
        srgb_non_linear,
    };

    pub const Transform = enum {
        identity,
        rotate_90,
        rotate_180,
        rotate_270,
        horizontal_mirror,
        horizontal_mirror_rotate_90,
        horizontal_mirror_rotate_180,
        horizontal_mirror_rotate_270,
        inherit,

        pub const Flags = ngl.Flags(Transform);
    };

    pub const CompositeAlpha = enum {
        @"opaque",
        pre_multiplied,
        post_multiplied,
        inherit,

        pub const Flags = ngl.Flags(CompositeAlpha);
    };

    pub const PresentMode = enum {
        immediate,
        mailbox,
        fifo,
        fifo_relaxed,

        pub const Flags = ngl.Flags(PresentMode);
    };

    const Self = @This();

    /// It's only valid to call this function if the instance was created
    /// with `Instance.Desc.presentation` set to `true`.
    pub fn init(allocator: std.mem.Allocator, instance: *Instance, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSurface(allocator, instance.impl, desc) };
    }

    /// Returns whether the given queue of the given device can present
    /// to the surface.
    /// `device_desc` must have been obtained through a call to
    /// `instance.listDevices`.
    /// `queue_desc` must refer to an element of `device_desc.queues`.
    pub fn isCompatible(
        self: *Self,
        instance: *Instance,
        device_desc: Device.Desc,
        queue_desc: Queue.Desc,
    ) Error!bool {
        return Impl.get().isSurfaceCompatible(instance.impl, self.impl, device_desc, queue_desc);
    }

    pub fn getPresentModes(
        self: *Self,
        instance: *Instance,
        device_desc: Device.Desc,
    ) Error!PresentMode.Flags {
        return Impl.get().getSurfacePresentModes(instance.impl, self.impl, device_desc);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, instance: *Instance) void {
        Impl.get().deinitSurface(allocator, instance.impl, self.impl);
        self.* = undefined;
    }
};

pub const SwapChain = struct {
    impl: Impl.SwapChain,

    pub const Desc = struct {
        surface: *Surface,
        min_count: u32,
        format: Format,
        color_space: Surface.ColorSpace,
        width: u32,
        height: u32,
        layers: u32,
        usage: Image.Usage,
        pre_transform: Surface.Transform,
        composite_alpha: Surface.CompositeAlpha,
        present_mode: Surface.PresentMode,
        clipped: bool,
        old_swap_chain: ?*SwapChain,
    };

    const Self = @This();

    /// It's only valid to call this function if the device was created
    /// with `Device.Desc.feature_set.presentation` set to `true`.
    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSwapChain(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitSwapChain(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
