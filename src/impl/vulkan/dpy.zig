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
const Image = @import("res.zig").Image;
const Semaphore = @import("sync.zig").Semaphore;
const Fence = @import("sync.zig").Fence;

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
            if (device_desc.impl) |x| @ptrFromInt(x.impl) else return Error.InvalidArgument;
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
            if (device_desc.impl) |x| @ptrFromInt(x.impl) else return Error.InvalidArgument;

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
            if (device_desc.impl) |x| @ptrFromInt(x.impl) else return Error.InvalidArgument;

        const n = 16;
        var stk_fmts: [n]c.VkSurfaceFormatKHR = undefined;

        var fmts_n: u32 = undefined;
        try check(inst.vkGetPhysicalDeviceSurfaceFormatsKHR(phys_dev, sf.handle, &fmts_n, null));
        const fmts = if (fmts_n > n)
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
            s[i] = .{
                .format = conv.fromVkFormat(fmt.format) catch {
                    log.warn("Surface format {} ignored", .{fmt.format});
                    continue;
                },
                .color_space = conv.fromVkColorSpace(fmt.colorSpace) catch {
                    log.warn("Surface color space {} ignored", .{fmt.colorSpace});
                    continue;
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
            if (device_desc.impl) |x| @ptrFromInt(x.impl) else return Error.InvalidArgument;

        // TODO: Use get_surface_capabilities2/surface_maintenance1

        // TODO: Should check whether `present_mode` is supported at all
        _ = present_mode;

        var capab: c.VkSurfaceCapabilitiesKHR = undefined;
        try check(inst.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys_dev, sf.handle, &capab));
        const no_max_count = capab.maxImageCount == 0;
        const no_cur_extent = capab.currentExtent.width == 0xffffffff and
            capab.currentExtent.height == 0xffffffff;
        return .{
            .min_count = capab.minImageCount,
            .max_count = if (no_max_count) std.math.maxInt(u32) else capab.maxImageCount,
            .current_width = if (no_cur_extent) null else capab.currentExtent.width,
            .current_height = if (no_cur_extent) null else capab.currentExtent.height,
            .min_width = capab.minImageExtent.width,
            .min_height = capab.minImageExtent.height,
            .max_width = capab.maxImageExtent.width,
            .max_height = capab.maxImageExtent.height,
            .max_layers = capab.maxImageArrayLayers,
            .current_transform = conv.fromVkSurfaceTransform(capab.currentTransform),
            .supported_transforms = conv.fromVkSurfaceTransformFlags(capab.supportedTransforms),
            .supported_composite_alpha = conv.fromVkCompositeAlphaFlags(capab.supportedCompositeAlpha),
            .supported_usage = conv.fromVkImageUsageFlags(capab.supportedUsageFlags),
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
        const usage = conv.toVkImageUsageFlags(desc.usage);
        // Usage must not be zero
        if (usage == 0) return Error.InvalidArgument;

        var swapchain: c.VkSwapchainKHR = undefined;
        try check(Device.cast(device).vkCreateSwapchainKHR(&.{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = Surface.cast(desc.surface.impl).handle,
            .minImageCount = desc.min_count,
            .imageFormat = try conv.toVkFormat(desc.format),
            .imageColorSpace = conv.toVkColorSpace(desc.color_space),
            .imageExtent = .{ .width = desc.width, .height = desc.height },
            .imageArrayLayers = desc.layers,
            .imageUsage = usage,
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

    pub fn getImages(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        swap_chain: Impl.SwapChain,
    ) Error![]ngl.Image {
        const dev = Device.cast(device);
        const sc = cast(swap_chain);

        const n = 8;
        var stk_imgs: [n]c.VkImage = undefined;

        var img_n: u32 = undefined;
        try check(dev.vkGetSwapchainImagesKHR(sc.handle, &img_n, null));
        const imgs = if (img_n > n) try allocator.alloc(c.VkImage, img_n) else stk_imgs[0..img_n];
        defer if (img_n > n) allocator.free(imgs);
        try check(dev.vkGetSwapchainImagesKHR(sc.handle, &img_n, imgs.ptr));

        const s = try allocator.alloc(ngl.Image, img_n);
        for (s, imgs) |*image, handle|
            image.* = .{ .impl = .{ .val = @bitCast(Image{ .handle = handle }) } };
        return s;
    }

    pub fn nextImage(
        _: *anyopaque,
        device: Impl.Device,
        swap_chain: Impl.SwapChain,
        timeout: u64,
        semaphore: ?Impl.Semaphore,
        fence: ?Impl.Fence,
    ) Error!ngl.SwapChain.Index {
        var idx: u32 = undefined;
        const result = Device.cast(device).vkAcquireNextImageKHR(
            cast(swap_chain).handle,
            timeout,
            if (semaphore) |x| Semaphore.cast(x).handle else null_handle,
            if (fence) |x| Fence.cast(x).handle else null_handle,
            &idx,
        );

        return switch (result) {
            // We can't treat suboptimal as out of date error in this
            // case due to the semaphore/fence operations
            // However, we can do such in `Queue.present`, so pretend
            // that we succeeded here and let that method fail with
            // `Error.OutOfDate` (most likely)
            c.VK_SUCCESS,
            c.VK_SUBOPTIMAL_KHR,
            => idx,

            else => |x| if (check(x)) |_| unreachable else |err| err,
        };
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
