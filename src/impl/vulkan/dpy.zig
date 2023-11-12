const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const log = @import("init.zig").log;
const Instance = @import("init.zig").Instance;
const Device = @import("init.zig").Device;

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

    pub fn isCompatible(
        _: *anyopaque,
        instance: Impl.Instance,
        surface: Impl.Surface,
        device_desc: ngl.Device.Desc,
        queue_desc: ngl.Queue.Desc,
    ) Error!bool {
        const inst = Instance.cast(instance);
        const sf = cast(surface);
        const phys_dev: c.VkPhysicalDevice =
            @ptrFromInt(device_desc.impl orelse return Error.InvalidArgument);
        const queue_fam: u32 = @intCast(queue_desc.impl orelse return Error.InvalidArgument);

        var supported: c.VkBool32 = undefined;
        try (check(inst.vkGetPhysicalDeviceSurfaceSupportKHR(
            phys_dev,
            queue_fam,
            sf.handle,
            &supported,
        )));
        return supported == c.VK_TRUE;
    }

    pub fn getPresentModes(
        _: *anyopaque,
        instance: Impl.Instance,
        surface: Impl.Surface,
        device_desc: ngl.Device.Desc,
    ) Error!ngl.Surface.PresentMode.Flags {
        const inst = Instance.cast(instance);
        const sf = cast(surface);
        const phys_dev: c.VkPhysicalDevice =
            @ptrFromInt(device_desc.impl orelse return Error.InvalidArgument);

        var modes: [6]c.VkPresentModeKHR = undefined;
        var mode_n: u32 = undefined;
        try check(inst.vkGetPhysicalDeviceSurfacePresentModesKHR(
            phys_dev,
            sf.handle,
            &mode_n,
            null,
        ));
        if (mode_n > modes.len) {
            // Will have to increase the length of `modes` in this case
            // (currently it matches the number of valid present modes
            // that are defined in the C enum)
            std.debug.assert(false);
            log.warn(
                "Too many supported present modes for Surface - ignoring {}",
                .{mode_n - modes.len},
            );
            mode_n = modes.len;
        }
        const result = inst.vkGetPhysicalDeviceSurfacePresentModesKHR(
            phys_dev,
            sf.handle,
            &mode_n,
            &modes,
        );
        if (result != c.VK_SUCCESS and result != c.VK_INCOMPLETE) {
            try check(result);
            unreachable;
        }

        var flags: ngl.Surface.PresentMode.Flags = .{ .fifo = true };
        for (modes[0..mode_n]) |mode| {
            switch (mode) {
                c.VK_PRESENT_MODE_IMMEDIATE_KHR => flags.immediate = true,
                c.VK_PRESENT_MODE_MAILBOX_KHR => flags.mailbox = true,
                c.VK_PRESENT_MODE_FIFO_RELAXED_KHR => flags.fifo_relaxed = true,
                else => continue,
            }
        }
        return flags;
    }

    pub fn getFormats(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Impl.Instance,
        surface: Impl.Surface,
        device_desc: ngl.Device.Desc,
    ) Error![]ngl.Surface.Format {
        const inst = Instance.cast(instance);
        const sf = cast(surface);
        const phys_dev: c.VkPhysicalDevice =
            @ptrFromInt(device_desc.impl orelse return Error.InvalidArgument);

        const n = 16;
        var stk_fmts: [n]c.VkSurfaceFormatKHR = undefined;

        var fmts_n: u32 = undefined;
        try check(inst.vkGetPhysicalDeviceSurfaceFormatsKHR(phys_dev, sf.handle, &fmts_n, null));
        var fmts = if (fmts_n > n)
            try allocator.alloc(c.VkSurfaceFormatKHR, fmts_n)
        else
            stk_fmts[0..fmts_n];
        defer if (fmts_n > n) allocator.free(fmts);
        try check(inst.vkGetPhysicalDeviceSurfaceFormatsKHR(
            phys_dev,
            sf.handle,
            &fmts_n,
            fmts.ptr,
        ));

        // BUG: We don't expose all Vulkan formats and the implementation
        // is allowed to return anything it likes here
        var s = try allocator.alloc(ngl.Surface.Format, fmts.len);
        errdefer allocator.free(s);
        var i: usize = 0;
        for (fmts) |fmt| {
            // TODO: Consider defining these conversions in `conv.zig`
            s[i] = .{
                .format = switch (fmt.format) {
                    c.VK_FORMAT_R8G8B8A8_UNORM => .rgba8_unorm,
                    c.VK_FORMAT_R8G8B8A8_SRGB => .rgba8_srgb,
                    c.VK_FORMAT_R8G8B8A8_SNORM => .rgba8_snorm,
                    c.VK_FORMAT_B8G8R8A8_UNORM => .bgra8_unorm,
                    c.VK_FORMAT_B8G8R8A8_SRGB => .bgra8_srgb,
                    c.VK_FORMAT_B8G8R8A8_SNORM => .bgra8_snorm,
                    c.VK_FORMAT_A2R10G10B10_UNORM_PACK32 => .a2rgb10_unorm,
                    c.VK_FORMAT_A2B10G10R10_UNORM_PACK32 => .a2bgr10_unorm,
                    c.VK_FORMAT_R16G16B16A16_UNORM => .rgba16_unorm,
                    c.VK_FORMAT_R16G16B16A16_SNORM => .rgba16_snorm,
                    c.VK_FORMAT_R16G16B16A16_SFLOAT => .rgba16_sfloat,
                    else => |x| {
                        log.warn("Surface format {} ignored", .{x});
                        continue;
                    },
                },
                .color_space = switch (fmt.colorSpace) {
                    c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR => .srgb_non_linear,
                    else => |x| {
                        log.warn("Surface color space {} ignored", .{x});
                        continue;
                    },
                },
            };
            i += 1;
        }
        return if (i > 0) s[0..i] else Error.NotSupported;
    }

    pub fn getCapabilities(
        _: *anyopaque,
        instance: Impl.Instance,
        surface: Impl.Surface,
        device_desc: ngl.Device.Desc,
        present_mode: ngl.Surface.PresentMode,
    ) Error!ngl.Surface.Capabilities {
        const inst = Instance.cast(instance);
        const sf = cast(surface);
        const phys_dev: c.VkPhysicalDevice =
            @ptrFromInt(device_desc.impl orelse return Error.InvalidArgument);

        // TODO: Use get_surface_capabilities2/surface_maintenance1

        // TODO: Should check whether `present_mode` is supported at all
        _ = present_mode;

        var capab: c.VkSurfaceCapabilitiesKHR = undefined;
        try check(inst.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys_dev, sf.handle, &capab));
        return .{
            .min_count = capab.minImageCount,
            .max_count = capab.maxImageCount,
            .current_width = capab.currentExtent.width,
            .current_height = capab.currentExtent.height,
            .min_width = capab.minImageExtent.width,
            .min_height = capab.minImageExtent.height,
            .max_width = capab.maxImageExtent.width,
            .max_height = capab.maxImageExtent.height,
            .max_layers = capab.maxImageArrayLayers,
            // TODO: Consider defining these conversions in `conv.zig`
            .current_transform = switch (capab.currentTransform) {
                c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR => .identity,
                c.VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR => .rotate_90,
                c.VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR => .rotate_180,
                c.VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR => .rotate_270,
                c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR => .horizontal_mirror,
                c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR => .horizontal_mirror_rotate_90,
                c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR => .horizontal_mirror_rotate_180,
                c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR => .horizontal_mirror_rotate_270,
                c.VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR => .inherit,
                else => {
                    std.debug.assert(false);
                    return Error.Other;
                },
            },
            .supported_transforms = blk: {
                var flags = ngl.Surface.Transform.Flags{};
                const mask = capab.supportedTransforms;
                if (mask & c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR != 0) flags.identity = true;
                if (mask & c.VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR != 0) flags.rotate_90 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR != 0) flags.rotate_180 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR != 0) flags.rotate_270 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR != 0) flags.horizontal_mirror = true;
                if (mask & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR != 0) flags.horizontal_mirror_rotate_90 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR != 0) flags.horizontal_mirror_rotate_180 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR != 0) flags.horizontal_mirror_rotate_270 = true;
                if (mask & c.VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR != 0) flags.inherit = true;
                break :blk flags;
            },
            .supported_composite_alpha = blk: {
                var flags = ngl.Surface.CompositeAlpha.Flags{};
                const mask = capab.supportedCompositeAlpha;
                if (mask & c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR != 0) flags.@"opaque" = true;
                if (mask & c.VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR != 0) flags.pre_multiplied = true;
                if (mask & c.VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR != 0) flags.post_multiplied = true;
                if (mask & c.VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR != 0) flags.inherit = true;
                break :blk flags;
            },
            .supported_usage = blk: {
                var usage = ngl.Image.Usage{};
                const mask = capab.supportedUsageFlags;
                if (mask & c.VK_IMAGE_USAGE_SAMPLED_BIT != 0) usage.sampled_image = true;
                if (mask & c.VK_IMAGE_USAGE_STORAGE_BIT != 0) usage.storage_image = true;
                if (mask & c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT != 0) usage.color_attachment = true;
                if (mask & c.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT != 0) usage.input_attachment = true;
                if (mask & c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT != 0) usage.transfer_source = true;
                if (mask & c.VK_IMAGE_USAGE_TRANSFER_DST_BIT != 0) usage.transfer_dest = true;
                break :blk usage;
            },
        };
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

pub const SwapChain = packed struct {
    handle: c.VkSwapchainKHR,

    pub inline fn cast(impl: Impl.SwapChain) SwapChain {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.SwapChain.Desc,
    ) Error!Impl.SwapChain {
        const dev = Device.cast(device);

        var swapchain: c.VkSwapchainKHR = undefined;

        try check(dev.vkCreateSwapchainKHR(&.{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = Surface.cast(desc.surface.impl).handle,
            .minImageCount = desc.min_count,
            .imageFormat = try conv.toVkFormat(desc.format),
            .imageColorSpace = conv.toVkColorSpace(desc.color_space),
            .imageExtent = .{ .width = desc.width, .height = desc.height },
            .imageArrayLayers = desc.layers,
            .imageUsage = blk: {
                var usage: c.VkImageUsageFlags = 0;
                if (desc.usage.sampled_image) usage |= c.VK_IMAGE_USAGE_SAMPLED_BIT;
                if (desc.usage.storage_image) usage |= c.VK_IMAGE_USAGE_STORAGE_BIT;
                if (desc.usage.color_attachment) usage |= c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
                if (desc.usage.input_attachment) usage |= c.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
                if (desc.usage.transfer_source) usage |= c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
                if (desc.usage.transfer_dest) usage |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
                // TODO: Do these checks on `Impl`
                std.debug.assert(usage != 0);
                std.debug.assert(!desc.usage.depth_stencil_attachment);
                std.debug.assert(!desc.usage.transient_attachment);
                break :blk usage;
            },
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = conv.toVkSurfaceTransform(desc.pre_transform),
            .compositeAlpha = conv.toVkCompositeAlpha(desc.composite_alpha),
            .presentMode = conv.toVkPresentMode(desc.present_mode),
            .clipped = if (desc.clipped) c.VK_TRUE else c.VK_FALSE,
            .oldSwapchain = if (desc.old_swap_chain) |x| cast(x.impl).handle else null_handle,
        }, null, &swapchain));

        return .{ .val = @bitCast(SwapChain{ .handle = swapchain }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        swap_chain: Impl.SwapChain,
    ) void {
        Device.cast(device).vkDestroySwapchainKHR(cast(swap_chain).handle, null);
    }
};
