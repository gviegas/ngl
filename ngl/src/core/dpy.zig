const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const ngl = @import("../ngl.zig");
const Gpu = ngl.Gpu;
const Device = ngl.Device;
const Queue = ngl.Queue;
const Format = ngl.Format;
const Image = ngl.Image;
const Semaphore = ngl.Semaphore;
const Fence = ngl.Fence;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");
const c = @import("../inc.zig");

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

    // TODO: OS-agnostic platform.
    pub const Platform = @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = switch (builtin.os.tag) {
            .linux => if (builtin.abi.isAndroid()) enum { android } else enum { wayland },
            .windows => enum { win32 },
            else => enum {},
        },
        .fields = blk: {
            const UnionField = std.builtin.Type.UnionField;
            const fields: []const UnionField = switch (builtin.os.tag) {
                .linux => if (builtin.abi.isAndroid()) &[_]UnionField{.{
                    .name = "android",
                    .type = Android,
                    .alignment = @alignOf(Android),
                }} else &[_]UnionField{.{
                    .name = "wayland",
                    .type = Wayland,
                    .alignment = @alignOf(Wayland),
                }},
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

    // TODO: Other color spaces.
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

    pub const Format = struct {
        format: ngl.Format,
        color_space: ColorSpace,
    };

    pub const Capabilities = struct {
        min_count: u32,
        max_count: u32,
        current_width: ?u32,
        current_height: ?u32,
        min_width: u32,
        min_height: u32,
        max_width: u32,
        max_height: u32,
        max_layers: u32,
        current_transform: Transform,
        supported_transforms: Transform.Flags,
        supported_composite_alpha: CompositeAlpha.Flags,
        supported_usage: Image.Usage,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initSurface(allocator, desc) };
    }

    /// Returns whether the given queue of the given GPU can present
    /// to the surface.
    pub fn isCompatible(self: *Self, gpu: Gpu, queue: Queue.Index) Error!bool {
        return Impl.get().isSurfaceCompatible(self.impl, gpu, queue);
    }

    pub fn getPresentModes(self: *Self, gpu: Gpu) Error!PresentMode.Flags {
        const modes = try Impl.get().getSurfacePresentModes(self.impl, gpu);
        assert(modes != PresentMode.Flags{});
        return modes;
    }

    /// Caller is responsible for freeing the returned slice.
    pub fn getFormats(self: *Self, allocator: std.mem.Allocator, gpu: Gpu) Error![]Self.Format {
        const fmts = try Impl.get().getSurfaceFormats(allocator, self.impl, gpu);
        assert(fmts.len > 0);
        for (fmts) |fmt|
            assert(fmt.format != .unknown);
        return fmts;
    }

    pub fn getCapabilities(
        self: *Self,
        gpu: Gpu,
        present_mode: PresentMode,
    ) Error!Capabilities {
        const capab = try Impl.get().getSurfaceCapabilities(self.impl, gpu, present_mode);
        assert(capab.min_count > 0);
        assert(capab.max_count >= capab.min_count);
        assert(capab.max_width > 0);
        assert(capab.max_height > 0);
        assert(capab.max_layers > 0);
        assert(capab.current_width == null or capab.current_width.? <= capab.max_width);
        assert(capab.current_height == null or capab.current_height.? <= capab.max_height);
        assert(capab.supported_transforms != Transform.Flags{});
        assert(capab.supported_composite_alpha != CompositeAlpha.Flags{});
        assert(capab.supported_usage.color_attachment);
        return capab;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        Impl.get().deinitSurface(allocator, self.impl);
        self.* = undefined;
    }
};

pub const Swapchain = struct {
    impl: Impl.Swapchain,

    // TODO: Should use a smaller integer for this type
    // (need to update `Surface.Capabilities`).
    pub const Index = u32;

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
        old_swapchain: ?*Swapchain,
    };

    const Self = @This();

    /// It is only valid to call this function if the device was
    /// created with `Device.Desc.feature_set.presentation` set
    /// to `true`.
    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        assert(desc.min_count > 0);
        assert(desc.format != .unknown);
        assert(desc.width > 0);
        assert(desc.height > 0);
        assert(desc.layers > 0);
        assert(desc.usage.color_attachment);
        return .{ .impl = try Impl.get().initSwapchain(allocator, device.impl, desc) };
    }

    /// Caller is responsible for freeing the returned slice.
    ///
    /// The images are owned by the swapchain and will be freed
    /// by `self.deinit`. Calling `Image.deinit` on these images
    /// is not allowed.
    pub fn getImages(self: *Self, allocator: std.mem.Allocator, device: *Device) Error![]Image {
        const imgs = try Impl.get().getSwapchainImages(allocator, device.impl, self.impl);
        assert(imgs.len > 0);
        return imgs;
    }

    /// `semaphore` and `fence` must not both be `null`.
    pub fn nextImage(
        self: *Self,
        device: *Device,
        timeout: u64,
        semaphore: ?*Semaphore,
        fence: ?*Fence,
    ) Error!Index {
        assert(semaphore != null or fence != null);
        return Impl.get().nextSwapchainImage(
            device.impl,
            self.impl,
            timeout,
            if (semaphore) |x| x.impl else null,
            if (fence) |x| x.impl else null,
        );
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitSwapchain(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
