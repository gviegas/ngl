const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(.@"ngl/impl/vulkan");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const CommandBuffer = @import("cmd.zig").CommandBuffer;
const Fence = @import("sync.zig").Fence;
const Semaphore = @import("sync.zig").Semaphore;

var libvulkan: ?*anyopaque = null;
var getInstanceProcAddr: c.PFN_vkGetInstanceProcAddr = null;

// NOTE: Procs from any version greater than 1.0, as well as extensions,
// are allowed to be null after initialization.

// v1.0
var createInstance: c.PFN_vkCreateInstance = null;
inline fn vkCreateInstance(
    create_info: *const c.VkInstanceCreateInfo,
    vk_allocator: ?*const c.VkAllocationCallbacks,
    instance: *c.VkInstance,
) c.VkResult {
    return createInstance.?(create_info, vk_allocator, instance);
}

// v1.0
var enumerateInstanceLayerProperties: c.PFN_vkEnumerateInstanceLayerProperties = null;
inline fn vkEnumerateInstanceLayerProperties(
    property_count: *u32,
    properties: ?[*]c.VkLayerProperties,
) c.VkResult {
    return enumerateInstanceLayerProperties.?(property_count, properties);
}

// v1.0
var enumerateInstanceExtensionProperties: c.PFN_vkEnumerateInstanceExtensionProperties = null;
inline fn vkEnumerateInstanceExtensionProperties(
    layer_name: ?[*:0]const u8,
    property_count: *u32,
    properties: ?[*]c.VkExtensionProperties,
) c.VkResult {
    return enumerateInstanceExtensionProperties.?(layer_name, property_count, properties);
}

// v1.1
var enumerateInstanceVersion: c.PFN_vkEnumerateInstanceVersion = null;
/// This wrapper can be called regardless of API version.
inline fn vkEnumerateInstanceVersion(version: *u32) c.VkResult {
    if (enumerateInstanceVersion) |fp| return fp(version);
    version.* = c.VK_API_VERSION_1_0;
    return c.VK_SUCCESS;
}

/// The returned proc is guaranteed to be non-null.
/// Use for global procs only.
fn getProc(name: [:0]const u8) Error!c.PFN_vkVoidFunction {
    std.debug.assert(getInstanceProcAddr != null);
    return if (getInstanceProcAddr.?(null, name)) |fp| fp else Error.InitializationFailed;
}

pub fn init() Error!Impl {
    const sym = "vkGetInstanceProcAddr";

    if (builtin.os.tag != .linux and builtin.os.tag != .windows)
        @compileError("OS not supported");

    if (builtin.os.tag == .linux) {
        errdefer {
            if (libvulkan) |handle| {
                _ = std.c.dlclose(handle);
                libvulkan = null;
                getInstanceProcAddr = null;
            }
        }
        const name = if (builtin.target.isAndroid()) "libvulkan.so" else "libvulkan.so.1";
        libvulkan = std.c.dlopen(name, c.RTLD_LAZY | c.RTLD_LOCAL);
        if (libvulkan == null) return Error.InitializationFailed;
        getInstanceProcAddr = @ptrCast(std.c.dlsym(libvulkan.?, sym));
        if (getInstanceProcAddr == null) return Error.InitializationFailed;
    }

    if (builtin.os.tag == .windows) {
        // TODO
        @compileError("Not yet implemented");
    }

    createInstance = @ptrCast(try getProc("vkCreateInstance"));
    enumerateInstanceLayerProperties = @ptrCast(try getProc("vkEnumerateInstanceLayerProperties"));
    enumerateInstanceExtensionProperties = @ptrCast(try getProc("vkEnumerateInstanceExtensionProperties"));
    enumerateInstanceVersion = @ptrCast(getProc("vkEnumerateInstanceVersion") catch null);

    return .{
        .ptr = undefined,
        .vtable = &vtable,
    };
}

// TODO
fn deinit(_: *anyopaque, _: std.mem.Allocator) void {
    if (libvulkan) |handle| {
        if (builtin.os.tag != .windows) {
            _ = std.c.dlclose(handle);
        } else {
            @compileError("Not yet implemented");
        }
        libvulkan = null;
        getInstanceProcAddr = null;
        createInstance = null;
        enumerateInstanceLayerProperties = null;
        enumerateInstanceExtensionProperties = null;
        enumerateInstanceVersion = null;
    }
}

pub const Instance = struct {
    handle: c.VkInstance,

    // v1.0
    destroyInstance: c.PFN_vkDestroyInstance,
    enumeratePhysicalDevices: c.PFN_vkEnumeratePhysicalDevices,
    getPhysicalDeviceProperties: c.PFN_vkGetPhysicalDeviceProperties,
    getPhysicalDeviceQueueFamilyProperties: c.PFN_vkGetPhysicalDeviceQueueFamilyProperties,
    getPhysicalDeviceMemoryProperties: c.PFN_vkGetPhysicalDeviceMemoryProperties,
    getPhysicalDeviceFormatProperties: c.PFN_vkGetPhysicalDeviceFormatProperties,
    getPhysicalDeviceFeatures: c.PFN_vkGetPhysicalDeviceFeatures,
    createDevice: c.PFN_vkCreateDevice,
    enumerateDeviceExtensionProperties: c.PFN_vkEnumerateDeviceExtensionProperties,
    // VK_KHR_surface
    destroySurface: c.PFN_vkDestroySurfaceKHR,
    getPhysicalDeviceSurfaceSupport: c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR,
    getPhysicalDeviceSurfaceCapabilities: c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR,
    getPhysicalDeviceSurfaceFormats: c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR,
    getPhysicalDeviceSurfacePresentModes: c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR,
    // VK_KHR_android_surface
    createAndroidSurface: if (builtin.target.isAndroid())
        c.PFN_vkCreateAndroidSurfaceKHR
    else
        void,
    // VK_KHR_wayland_surface
    createWaylandSurface: if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c.PFN_vkCreateWaylandSurfaceKHR
    else
        void,
    // VK_KHR_win32_surface
    createWin32Surface: if (builtin.os.tag == .windows)
        c.PFN_vkCreateWin32SurfaceKHR
    else
        void,
    // VK_KHR_xcb_surface
    createXcbSurface: if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c.PFN_vkCreateXcbSurfaceKHR
    else
        void,

    pub inline fn cast(impl: Impl.Instance) *Instance {
        return impl.ptr(Instance);
    }

    /// The returned proc is guaranteed to be non-null.
    pub fn getProc(instance: c.VkInstance, name: [:0]const u8) Error!c.PFN_vkVoidFunction {
        std.debug.assert(getInstanceProcAddr != null);
        return if (getInstanceProcAddr.?(instance, name)) |fp| fp else Error.InitializationFailed;
    }

    fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        desc: ngl.Instance.Desc,
    ) Error!Impl.Instance {
        std.debug.assert(createInstance != null);
        std.debug.assert(enumerateInstanceLayerProperties != null);
        std.debug.assert(enumerateInstanceExtensionProperties != null);

        var ext_prop_n: u32 = undefined;
        try check(vkEnumerateInstanceExtensionProperties(null, &ext_prop_n, null));
        var ext_props = try allocator.alloc(c.VkExtensionProperties, ext_prop_n);
        defer allocator.free(ext_props);
        try check(vkEnumerateInstanceExtensionProperties(null, &ext_prop_n, ext_props.ptr));

        var ext_names = std.ArrayList([*:0]const u8).init(allocator);
        defer ext_names.deinit();

        if (desc.presentation) {
            const surface_ext = "VK_KHR_surface";
            for (ext_props) |prop| {
                if (std.mem.eql(u8, prop.extensionName[0..surface_ext.len], surface_ext)) {
                    try ext_names.append(@ptrCast(&prop.extensionName));
                    break;
                }
            } else return Error.NotPresent;
            const platform_exts = switch (builtin.os.tag) {
                .linux => if (builtin.target.isAndroid())
                    .{"VK_KHR_android_surface"}
                else
                    .{ "VK_KHR_wayland_surface", "VK_KHR_xcb_surface" },
                .windows => .{"VK_KHR_win32_surface"},
                else => @compileError("OS not supported"),
            };
            // TODO: Consider succeeding if at least one of the
            // surface extensions is available
            inline for (platform_exts) |ext| {
                for (ext_props) |prop| {
                    if (std.mem.eql(u8, prop.extensionName[0..ext.len], ext)) {
                        try ext_names.append(@ptrCast(&prop.extensionName));
                        break;
                    }
                } else return Error.NotPresent;
            }
        }

        // TODO
        if (desc.debugging) log.warn("Instance.Desc.debugging ignored", .{});

        // TODO: App info
        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = null,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = @intCast(ext_names.items.len),
            .ppEnabledExtensionNames = if (ext_names.items.len > 0) ext_names.items.ptr else null,
        };
        var inst: c.VkInstance = undefined;
        try check(vkCreateInstance(&create_info, null, &inst));
        errdefer if (Instance.getProc(inst, "vkDestroyInstance")) |x| {
            if (@as(c.PFN_vkDestroyInstance, @ptrCast(x))) |f| f(inst, null);
        } else |_| {};

        var ptr = try allocator.create(Instance);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .handle = inst,
            .destroyInstance = @ptrCast(try Instance.getProc(inst, "vkDestroyInstance")),
            .enumeratePhysicalDevices = @ptrCast(try Instance.getProc(inst, "vkEnumeratePhysicalDevices")),
            .getPhysicalDeviceProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceProperties")),
            .getPhysicalDeviceQueueFamilyProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceQueueFamilyProperties")),
            .getPhysicalDeviceMemoryProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceMemoryProperties")),
            .getPhysicalDeviceFormatProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceFormatProperties")),
            .getPhysicalDeviceFeatures = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceFeatures")),
            .createDevice = @ptrCast(try Instance.getProc(inst, "vkCreateDevice")),
            .enumerateDeviceExtensionProperties = @ptrCast(try Instance.getProc(inst, "vkEnumerateDeviceExtensionProperties")),

            .destroySurface = if (desc.presentation)
                @ptrCast(try Instance.getProc(inst, "vkDestroySurfaceKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceSupport = if (desc.presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceSupportKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceCapabilities = if (desc.presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceFormats = if (desc.presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceFormatsKHR"))
            else
                null,
            .getPhysicalDeviceSurfacePresentModes = if (desc.presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfacePresentModesKHR"))
            else
                null,

            .createAndroidSurface = if (builtin.target.isAndroid())
                if (desc.presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateAndroidSurfaceKHR"))
                else
                    null
            else {},

            .createWaylandSurface = if (builtin.os.tag == .linux and !builtin.target.isAndroid())
                if (desc.presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateWaylandSurfaceKHR"))
                else
                    null
            else {},

            .createWin32Surface = if (builtin.os.tag == .windows)
                if (desc.presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateWin32SurfaceKHR"))
                else
                    null
            else {},

            .createXcbSurface = if (builtin.os.tag == .linux and !builtin.target.isAndroid())
                if (desc.presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateXcbSurfaceKHR"))
                else
                    null
            else {},
        };

        return .{ .val = @intFromPtr(ptr) };
    }

    fn listDevices(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Impl.Instance,
    ) Error![]ngl.Device.Desc {
        const inst = cast(instance);

        var dev_n: u32 = undefined;
        try check(inst.vkEnumeratePhysicalDevices(&dev_n, null));
        if (dev_n == 0) return Error.NotSupported; // TODO: Need a better error for this
        var devs = try allocator.alloc(c.VkPhysicalDevice, dev_n);
        defer allocator.free(devs);
        try check(inst.vkEnumeratePhysicalDevices(&dev_n, devs.ptr));

        var descs = try allocator.alloc(ngl.Device.Desc, dev_n);
        errdefer allocator.free(descs);

        var queue_props = std.ArrayList(c.VkQueueFamilyProperties).init(allocator);
        defer queue_props.deinit();

        for (devs, descs) |dev, *desc| {
            var prop: c.VkPhysicalDeviceProperties = undefined;
            inst.vkGetPhysicalDeviceProperties(dev, &prop);

            var n: u32 = undefined;
            inst.vkGetPhysicalDeviceQueueFamilyProperties(dev, &n, null);
            try queue_props.resize(n);
            inst.vkGetPhysicalDeviceQueueFamilyProperties(dev, &n, queue_props.items.ptr);

            // TODO: Other queues
            var main_queue: ngl.Queue.Desc = undefined;
            for (queue_props.items, 0..n) |qp, fam| {
                const mask = c.VK_QUEUE_GRAPHICS_BIT | c.VK_QUEUE_COMPUTE_BIT;
                if (qp.queueFlags & mask == mask) {
                    main_queue = .{
                        .capabilities = .{
                            .graphics = true,
                            .compute = true,
                            .transfer = true,
                        },
                        .priority = .default,
                        .impl = fam,
                    };
                    break;
                }
            } else return Error.InitializationFailed; // TODO: This should never happen

            if (@typeInfo(ngl.Feature).Union.fields.len > 2)
                @compileError("Set new feature(s)");

            desc.* = .{
                .type = switch (prop.deviceType) {
                    c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => .discrete_gpu,
                    c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => .integrated_gpu,
                    c.VK_PHYSICAL_DEVICE_TYPE_CPU => .cpu,
                    else => .other,
                },
                .queues = .{ main_queue, null, null, null },
                .feature_set = .{
                    .core = true,
                    // Don't expose this feature if the instance was created
                    // with presentation disabled, regardless of whether or not
                    // the device can support it
                    .presentation = if (inst.destroySurface != null)
                        (try inst.hasDeviceExtensions(allocator, dev, &.{"VK_KHR_swapchain"}))[0]
                    else
                        false,
                },
                .impl = @intFromPtr(dev),
            };
        }

        return descs;
    }

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, instance: Impl.Instance) void {
        const inst = cast(instance);
        // TODO: Need to gate destruction until all devices
        // and instance-level objects have been destroyed
        inst.vkDestroyInstance(null);
        allocator.destroy(inst);
    }

    fn hasDeviceExtensions(
        self: *Instance,
        allocator: std.mem.Allocator,
        device: c.VkPhysicalDevice,
        comptime names: []const [:0]const u8,
    ) Error![names.len]bool {
        var ext_prop_n: u32 = undefined;
        try check(self.vkEnumerateDeviceExtensionProperties(device, null, &ext_prop_n, null));
        var ext_props = try allocator.alloc(c.VkExtensionProperties, ext_prop_n);
        defer allocator.free(ext_props);
        try check(self.vkEnumerateDeviceExtensionProperties(
            device,
            null,
            &ext_prop_n,
            ext_props.ptr,
        ));
        var has: [names.len]bool = undefined;
        for (names, 0..) |name, i| {
            has[i] = for (ext_props) |prop| {
                if (std.mem.eql(u8, name, prop.extensionName[0..name.len]))
                    break true;
            } else false;
        }
        return has;
    }

    // Wrappers --------------------------------------------

    pub inline fn vkDestroyInstance(
        self: *Instance,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyInstance.?(self.handle, vk_allocator);
    }

    pub inline fn vkEnumeratePhysicalDevices(
        self: *Instance,
        device_count: *u32,
        devices: ?[*]c.VkPhysicalDevice,
    ) c.VkResult {
        return self.enumeratePhysicalDevices.?(self.handle, device_count, devices);
    }

    pub inline fn vkGetPhysicalDeviceProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceProperties,
    ) void {
        self.getPhysicalDeviceProperties.?(device, properties);
    }

    pub inline fn vkGetPhysicalDeviceQueueFamilyProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        property_count: *u32,
        properties: ?[*]c.VkQueueFamilyProperties,
    ) void {
        self.getPhysicalDeviceQueueFamilyProperties.?(device, property_count, properties);
    }

    pub inline fn vkGetPhysicalDeviceMemoryProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.getPhysicalDeviceMemoryProperties.?(device, properties);
    }

    pub inline fn vkGetPhysicalDeviceFormatProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        format: c.VkFormat,
        properties: *c.VkFormatProperties,
    ) void {
        self.getPhysicalDeviceFormatProperties.?(device, format, properties);
    }

    pub inline fn vkGetPhysicalDeviceFeatures(
        self: *Instance,
        device: c.VkPhysicalDevice,
        features: *c.VkPhysicalDeviceFeatures,
    ) void {
        self.getPhysicalDeviceFeatures.?(device, features);
    }

    pub inline fn vkCreateDevice(
        self: *Instance,
        physical_device: c.VkPhysicalDevice,
        create_info: *const c.VkDeviceCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        device: *c.VkDevice,
    ) c.VkResult {
        return self.createDevice.?(physical_device, create_info, vk_allocator, device);
    }

    pub inline fn vkEnumerateDeviceExtensionProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        layer_name: ?[*]const u8,
        property_count: *u32,
        properties: ?[*]c.VkExtensionProperties,
    ) c.VkResult {
        return self.enumerateDeviceExtensionProperties.?(
            device,
            layer_name,
            property_count,
            properties,
        );
    }

    pub inline fn vkDestroySurfaceKHR(
        self: *Instance,
        surface: c.VkSurfaceKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroySurface.?(self.handle, surface, vk_allocator);
    }

    pub inline fn vkGetPhysicalDeviceSurfaceSupportKHR(
        self: *Instance,
        device: c.VkPhysicalDevice,
        queue_family: u32,
        surface: c.VkSurfaceKHR,
        supported: *c.VkBool32,
    ) c.VkResult {
        return self.getPhysicalDeviceSurfaceSupport.?(device, queue_family, surface, supported);
    }

    pub inline fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        self: *Instance,
        device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        capabilities: *c.VkSurfaceCapabilitiesKHR,
    ) c.VkResult {
        return self.getPhysicalDeviceSurfaceCapabilities.?(device, surface, capabilities);
    }

    pub inline fn vkGetPhysicalDeviceSurfaceFormatsKHR(
        self: *Instance,
        device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        format_count: *u32,
        formats: ?[*]c.VkSurfaceFormatKHR,
    ) c.VkResult {
        return self.getPhysicalDeviceSurfaceFormats.?(device, surface, format_count, formats);
    }

    pub inline fn vkGetPhysicalDeviceSurfacePresentModesKHR(
        self: *Instance,
        device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        present_mode_count: *u32,
        present_modes: ?[*]c.VkPresentModeKHR,
    ) c.VkResult {
        return self.getPhysicalDeviceSurfacePresentModes.?(
            device,
            surface,
            present_mode_count,
            present_modes,
        );
    }

    pub inline fn vkCreateAndroidSurfaceKHR(
        self: *Instance,
        create_info: *const c.VkAndroidSurfaceCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        surface: *c.VkSurfaceKHR,
    ) c.VkResult {
        return self.createAndroidSurface.?(self.handle, create_info, vk_allocator, surface);
    }

    pub inline fn vkCreateWaylandSurfaceKHR(
        self: *Instance,
        create_info: *const c.VkWaylandSurfaceCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        surface: *c.VkSurfaceKHR,
    ) c.VkResult {
        return self.createWaylandSurface.?(self.handle, create_info, vk_allocator, surface);
    }

    pub inline fn vkCreateWin32SurfaceKHR(
        self: *Instance,
        create_info: *const c.VkWin32SurfaceCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        surface: *c.VkSurfaceKHR,
    ) c.VkResult {
        return self.createWin32Surface.?(self.handle, create_info, vk_allocator, surface);
    }

    pub inline fn vkCreateXcbSurfaceKHR(
        self: *Instance,
        create_info: *const c.VkXcbSurfaceCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        surface: *c.VkSurfaceKHR,
    ) c.VkResult {
        return self.createXcbSurface.?(self.handle, create_info, vk_allocator, surface);
    }
};

pub const Device = struct {
    instance: *Instance,
    physical_device: c.VkPhysicalDevice,
    handle: c.VkDevice,
    queues: [ngl.Queue.max]Queue,
    queue_n: u8,

    getDeviceProcAddr: c.PFN_vkGetDeviceProcAddr,

    // v1.0
    destroyDevice: c.PFN_vkDestroyDevice,
    deviceWaitIdle: c.PFN_vkDeviceWaitIdle,
    getDeviceQueue: c.PFN_vkGetDeviceQueue,
    queueSubmit: c.PFN_vkQueueSubmit,
    queueWaitIdle: c.PFN_vkQueueWaitIdle,
    allocateMemory: c.PFN_vkAllocateMemory,
    freeMemory: c.PFN_vkFreeMemory,
    mapMemory: c.PFN_vkMapMemory,
    unmapMemory: c.PFN_vkUnmapMemory,
    flushMappedMemoryRanges: c.PFN_vkFlushMappedMemoryRanges,
    invalidateMappedMemoryRanges: c.PFN_vkInvalidateMappedMemoryRanges,
    createCommandPool: c.PFN_vkCreateCommandPool,
    destroyCommandPool: c.PFN_vkDestroyCommandPool,
    resetCommandPool: c.PFN_vkResetCommandPool,
    allocateCommandBuffers: c.PFN_vkAllocateCommandBuffers,
    freeCommandBuffers: c.PFN_vkFreeCommandBuffers,
    beginCommandBuffer: c.PFN_vkBeginCommandBuffer,
    endCommandBuffer: c.PFN_vkEndCommandBuffer,
    cmdBindPipeline: c.PFN_vkCmdBindPipeline,
    cmdBindDescriptorSets: c.PFN_vkCmdBindDescriptorSets,
    cmdPushConstants: c.PFN_vkCmdPushConstants,
    cmdBindIndexBuffer: c.PFN_vkCmdBindIndexBuffer,
    cmdBindVertexBuffers: c.PFN_vkCmdBindVertexBuffers,
    cmdSetViewport: c.PFN_vkCmdSetViewport,
    cmdSetScissor: c.PFN_vkCmdSetScissor,
    cmdSetStencilReference: c.PFN_vkCmdSetStencilReference,
    cmdSetBlendConstants: c.PFN_vkCmdSetBlendConstants,
    cmdBeginRenderPass: c.PFN_vkCmdBeginRenderPass,
    cmdNextSubpass: c.PFN_vkCmdNextSubpass,
    cmdEndRenderPass: c.PFN_vkCmdEndRenderPass,
    cmdDraw: c.PFN_vkCmdDraw,
    cmdDrawIndexed: c.PFN_vkCmdDrawIndexed,
    cmdDrawIndirect: c.PFN_vkCmdDrawIndirect,
    cmdDrawIndexedIndirect: c.PFN_vkCmdDrawIndexedIndirect,
    cmdDispatch: c.PFN_vkCmdDispatch,
    cmdDispatchIndirect: c.PFN_vkCmdDispatchIndirect,
    cmdFillBuffer: c.PFN_vkCmdFillBuffer,
    cmdCopyBuffer: c.PFN_vkCmdCopyBuffer,
    cmdCopyImage: c.PFN_vkCmdCopyImage,
    cmdCopyBufferToImage: c.PFN_vkCmdCopyBufferToImage,
    cmdCopyImageToBuffer: c.PFN_vkCmdCopyImageToBuffer,
    cmdPipelineBarrier: c.PFN_vkCmdPipelineBarrier,
    cmdExecuteCommands: c.PFN_vkCmdExecuteCommands,
    createFence: c.PFN_vkCreateFence,
    destroyFence: c.PFN_vkDestroyFence,
    getFenceStatus: c.PFN_vkGetFenceStatus,
    resetFences: c.PFN_vkResetFences,
    waitForFences: c.PFN_vkWaitForFences,
    createSemaphore: c.PFN_vkCreateSemaphore,
    destroySemaphore: c.PFN_vkDestroySemaphore,
    createBuffer: c.PFN_vkCreateBuffer,
    destroyBuffer: c.PFN_vkDestroyBuffer,
    getBufferMemoryRequirements: c.PFN_vkGetBufferMemoryRequirements,
    bindBufferMemory: c.PFN_vkBindBufferMemory,
    createBufferView: c.PFN_vkCreateBufferView,
    destroyBufferView: c.PFN_vkDestroyBufferView,
    createImage: c.PFN_vkCreateImage,
    destroyImage: c.PFN_vkDestroyImage,
    getImageMemoryRequirements: c.PFN_vkGetImageMemoryRequirements,
    bindImageMemory: c.PFN_vkBindImageMemory,
    createImageView: c.PFN_vkCreateImageView,
    destroyImageView: c.PFN_vkDestroyImageView,
    createSampler: c.PFN_vkCreateSampler,
    destroySampler: c.PFN_vkDestroySampler,
    createRenderPass: c.PFN_vkCreateRenderPass,
    destroyRenderPass: c.PFN_vkDestroyRenderPass,
    createFramebuffer: c.PFN_vkCreateFramebuffer,
    destroyFramebuffer: c.PFN_vkDestroyFramebuffer,
    createDescriptorSetLayout: c.PFN_vkCreateDescriptorSetLayout,
    destroyDescriptorSetLayout: c.PFN_vkDestroyDescriptorSetLayout,
    createPipelineLayout: c.PFN_vkCreatePipelineLayout,
    destroyPipelineLayout: c.PFN_vkDestroyPipelineLayout,
    createDescriptorPool: c.PFN_vkCreateDescriptorPool,
    destroyDescriptorPool: c.PFN_vkDestroyDescriptorPool,
    resetDescriptorPool: c.PFN_vkResetDescriptorPool,
    allocateDescriptorSets: c.PFN_vkAllocateDescriptorSets,
    updateDescriptorSets: c.PFN_vkUpdateDescriptorSets,
    createGraphicsPipelines: c.PFN_vkCreateGraphicsPipelines,
    createComputePipelines: c.PFN_vkCreateComputePipelines,
    destroyPipeline: c.PFN_vkDestroyPipeline,
    createPipelineCache: c.PFN_vkCreatePipelineCache,
    destroyPipelineCache: c.PFN_vkDestroyPipelineCache,
    createShaderModule: c.PFN_vkCreateShaderModule,
    destroyShaderModule: c.PFN_vkDestroyShaderModule,
    // VK_KHR_swapchain
    createSwapchain: c.PFN_vkCreateSwapchainKHR,
    destroySwapchain: c.PFN_vkDestroySwapchainKHR,

    pub fn cast(impl: Impl.Device) *Device {
        return impl.ptr(Device);
    }

    /// The returned proc is guaranteed to be non-null.
    pub fn getProc(
        get: c.PFN_vkGetDeviceProcAddr,
        device: c.VkDevice,
        name: [:0]const u8,
    ) Error!c.PFN_vkVoidFunction {
        std.debug.assert(get != null);
        return if (get.?(device, name)) |fp| fp else Error.InitializationFailed;
    }

    fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Impl.Instance,
        desc: ngl.Device.Desc,
    ) Error!Impl.Device {
        const inst = Instance.cast(instance);
        const phys_dev: c.VkPhysicalDevice = if (desc.impl) |x|
            @ptrFromInt(x)
        else {
            // TODO: Consider supporting this
            log.warn("Device.init requires a description produced by Instance.listDevices", .{});
            return Error.InvalidArgument;
        };

        var queue_infos: [ngl.Queue.max]c.VkDeviceQueueCreateInfo = undefined;
        var queue_prios: [ngl.Queue.max]f32 = undefined;
        const queue_n = blk: {
            var n: u32 = 0;
            for (desc.queues) |queue| {
                const q = queue orelse continue;
                // Don't distinguish between default and high priority
                queue_prios[n] = if (q.priority == .low) 0 else 1;
                queue_infos[n] = .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .queueFamilyIndex = @intCast(q.impl orelse return Error.InvalidArgument),
                    .queueCount = 1,
                    .pQueuePriorities = &queue_prios[n],
                };
                n += 1;
            }
            if (n == 0) return Error.InvalidArgument;
            break :blk n;
        };

        // TODO: Check other extensions that may be useful
        var ext_prop_n: u32 = undefined;
        try check(inst.vkEnumerateDeviceExtensionProperties(phys_dev, null, &ext_prop_n, null));
        var ext_props = try allocator.alloc(c.VkExtensionProperties, ext_prop_n);
        defer allocator.free(ext_props);
        try check(inst.vkEnumerateDeviceExtensionProperties(
            phys_dev,
            null,
            &ext_prop_n,
            ext_props.ptr,
        ));

        var ext_names = std.ArrayList([*:0]const u8).init(allocator);
        defer ext_names.deinit();

        if (desc.feature_set.presentation) {
            if (inst.destroySurface == null) return Error.InvalidArgument;
            const exts = .{"VK_KHR_swapchain"};
            inline for (exts) |ext| {
                for (ext_props) |prop| {
                    if (std.mem.eql(u8, ext, prop.extensionName[0..ext.len])) {
                        try ext_names.append(@ptrCast(&prop.extensionName));
                        break;
                    }
                } else return Error.NotPresent;
            }
        }

        const feats: c.VkPhysicalDeviceFeatures = blk: {
            var feats: c.VkPhysicalDeviceFeatures = undefined;
            inst.vkGetPhysicalDeviceFeatures(phys_dev, &feats);
            // TODO: Expose/enable more features
            break :blk .{
                .robustBufferAccess = c.VK_FALSE,
                .fullDrawIndexUint32 = feats.fullDrawIndexUint32,
                .imageCubeArray = feats.imageCubeArray,
                .independentBlend = feats.independentBlend,
                .geometryShader = c.VK_FALSE,
                .tessellationShader = c.VK_FALSE,
                .sampleRateShading = c.VK_FALSE,
                .dualSrcBlend = c.VK_FALSE,
                .logicOp = c.VK_FALSE,
                .multiDrawIndirect = feats.multiDrawIndirect,
                .drawIndirectFirstInstance = feats.drawIndirectFirstInstance,
                .depthClamp = feats.depthClamp,
                .depthBiasClamp = feats.depthBiasClamp,
                .fillModeNonSolid = feats.fillModeNonSolid,
                .depthBounds = c.VK_FALSE,
                .wideLines = c.VK_FALSE,
                .largePoints = c.VK_FALSE,
                .alphaToOne = feats.alphaToOne,
                .multiViewport = c.VK_FALSE,
                .samplerAnisotropy = feats.samplerAnisotropy,
                .textureCompressionETC2 = c.VK_FALSE,
                .textureCompressionASTC_LDR = c.VK_FALSE,
                .textureCompressionBC = c.VK_FALSE,
                .occlusionQueryPrecise = c.VK_FALSE,
                .pipelineStatisticsQuery = c.VK_FALSE,
                .vertexPipelineStoresAndAtomics = feats.vertexPipelineStoresAndAtomics,
                .fragmentStoresAndAtomics = feats.fragmentStoresAndAtomics,
                .shaderTessellationAndGeometryPointSize = c.VK_FALSE,
                .shaderImageGatherExtended = c.VK_FALSE,
                .shaderStorageImageExtendedFormats = c.VK_FALSE,
                .shaderStorageImageMultisample = feats.shaderStorageImageMultisample,
                .shaderStorageImageReadWithoutFormat = c.VK_FALSE,
                .shaderStorageImageWriteWithoutFormat = c.VK_FALSE,
                .shaderUniformBufferArrayDynamicIndexing = c.VK_FALSE,
                .shaderSampledImageArrayDynamicIndexing = c.VK_FALSE,
                .shaderStorageBufferArrayDynamicIndexing = c.VK_FALSE,
                .shaderStorageImageArrayDynamicIndexing = c.VK_FALSE,
                .shaderClipDistance = c.VK_FALSE,
                .shaderCullDistance = c.VK_FALSE,
                .shaderFloat64 = c.VK_FALSE,
                .shaderInt64 = c.VK_FALSE,
                .shaderInt16 = c.VK_FALSE,
                .shaderResourceResidency = c.VK_FALSE,
                .shaderResourceMinLod = c.VK_FALSE,
                .sparseBinding = c.VK_FALSE,
                .sparseResidencyBuffer = c.VK_FALSE,
                .sparseResidencyImage2D = c.VK_FALSE,
                .sparseResidencyImage3D = c.VK_FALSE,
                .sparseResidency2Samples = c.VK_FALSE,
                .sparseResidency4Samples = c.VK_FALSE,
                .sparseResidency8Samples = c.VK_FALSE,
                .sparseResidency16Samples = c.VK_FALSE,
                .sparseResidencyAliased = c.VK_FALSE,
                .variableMultisampleRate = c.VK_FALSE,
                .inheritedQueries = c.VK_FALSE,
            };
        };

        var create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = queue_n,
            .pQueueCreateInfos = &queue_infos,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = @intCast(ext_names.items.len),
            .ppEnabledExtensionNames = if (ext_names.items.len > 0) ext_names.items.ptr else null,
            .pEnabledFeatures = &feats,
        };
        var dev: c.VkDevice = undefined;
        try check(inst.vkCreateDevice(phys_dev, &create_info, null, &dev));
        errdefer if (Instance.getProc(inst.handle, "vkDestroyDevice")) |x| {
            if (@as(c.PFN_vkDestroyDevice, @ptrCast(x))) |f| f(dev, null);
        } else |_| {};

        const get: c.PFN_vkGetDeviceProcAddr = @ptrCast(try Instance.getProc(
            inst.handle,
            "vkGetDeviceProcAddr",
        ));

        var ptr = try allocator.create(Device);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .instance = inst,
            .physical_device = phys_dev,
            .handle = dev,
            .queues = undefined,
            .queue_n = 0,
            .getDeviceProcAddr = get,
            .destroyDevice = @ptrCast(try Device.getProc(get, dev, "vkDestroyDevice")),
            .deviceWaitIdle = @ptrCast(try Device.getProc(get, dev, "vkDeviceWaitIdle")),
            .getDeviceQueue = @ptrCast(try Device.getProc(get, dev, "vkGetDeviceQueue")),
            .queueSubmit = @ptrCast(try Device.getProc(get, dev, "vkQueueSubmit")),
            .queueWaitIdle = @ptrCast(try Device.getProc(get, dev, "vkQueueWaitIdle")),
            .allocateMemory = @ptrCast(try Device.getProc(get, dev, "vkAllocateMemory")),
            .freeMemory = @ptrCast(try Device.getProc(get, dev, "vkFreeMemory")),
            .mapMemory = @ptrCast(try Device.getProc(get, dev, "vkMapMemory")),
            .unmapMemory = @ptrCast(try Device.getProc(get, dev, "vkUnmapMemory")),
            .flushMappedMemoryRanges = @ptrCast(try Device.getProc(get, dev, "vkFlushMappedMemoryRanges")),
            .invalidateMappedMemoryRanges = @ptrCast(try Device.getProc(get, dev, "vkInvalidateMappedMemoryRanges")),
            .createCommandPool = @ptrCast(try Device.getProc(get, dev, "vkCreateCommandPool")),
            .destroyCommandPool = @ptrCast(try Device.getProc(get, dev, "vkDestroyCommandPool")),
            .resetCommandPool = @ptrCast(try Device.getProc(get, dev, "vkResetCommandPool")),
            .allocateCommandBuffers = @ptrCast(try Device.getProc(get, dev, "vkAllocateCommandBuffers")),
            .freeCommandBuffers = @ptrCast(try Device.getProc(get, dev, "vkFreeCommandBuffers")),
            .beginCommandBuffer = @ptrCast(try Device.getProc(get, dev, "vkBeginCommandBuffer")),
            .endCommandBuffer = @ptrCast(try Device.getProc(get, dev, "vkEndCommandBuffer")),
            .cmdBindPipeline = @ptrCast(try Device.getProc(get, dev, "vkCmdBindPipeline")),
            .cmdBindDescriptorSets = @ptrCast(try Device.getProc(get, dev, "vkCmdBindDescriptorSets")),
            .cmdPushConstants = @ptrCast(try Device.getProc(get, dev, "vkCmdPushConstants")),
            .cmdBindIndexBuffer = @ptrCast(try Device.getProc(get, dev, "vkCmdBindIndexBuffer")),
            .cmdBindVertexBuffers = @ptrCast(try Device.getProc(get, dev, "vkCmdBindVertexBuffers")),
            .cmdSetViewport = @ptrCast(try Device.getProc(get, dev, "vkCmdSetViewport")),
            .cmdSetScissor = @ptrCast(try Device.getProc(get, dev, "vkCmdSetScissor")),
            .cmdSetStencilReference = @ptrCast(try Device.getProc(get, dev, "vkCmdSetStencilReference")),
            .cmdSetBlendConstants = @ptrCast(try Device.getProc(get, dev, "vkCmdSetBlendConstants")),
            .cmdBeginRenderPass = @ptrCast(try Device.getProc(get, dev, "vkCmdBeginRenderPass")),
            .cmdNextSubpass = @ptrCast(try Device.getProc(get, dev, "vkCmdNextSubpass")),
            .cmdEndRenderPass = @ptrCast(try Device.getProc(get, dev, "vkCmdEndRenderPass")),
            .cmdDraw = @ptrCast(try Device.getProc(get, dev, "vkCmdDraw")),
            .cmdDrawIndexed = @ptrCast(try Device.getProc(get, dev, "vkCmdDrawIndexed")),
            .cmdDrawIndirect = @ptrCast(try Device.getProc(get, dev, "vkCmdDrawIndirect")),
            .cmdDrawIndexedIndirect = @ptrCast(try Device.getProc(get, dev, "vkCmdDrawIndexedIndirect")),
            .cmdDispatch = @ptrCast(try Device.getProc(get, dev, "vkCmdDispatch")),
            .cmdDispatchIndirect = @ptrCast(try Device.getProc(get, dev, "vkCmdDispatchIndirect")),
            .cmdFillBuffer = @ptrCast(try Device.getProc(get, dev, "vkCmdFillBuffer")),
            .cmdCopyBuffer = @ptrCast(try Device.getProc(get, dev, "vkCmdCopyBuffer")),
            .cmdCopyImage = @ptrCast(try Device.getProc(get, dev, "vkCmdCopyImage")),
            .cmdCopyBufferToImage = @ptrCast(try Device.getProc(get, dev, "vkCmdCopyBufferToImage")),
            .cmdCopyImageToBuffer = @ptrCast(try Device.getProc(get, dev, "vkCmdCopyImageToBuffer")),
            .cmdPipelineBarrier = @ptrCast(try Device.getProc(get, dev, "vkCmdPipelineBarrier")),
            .cmdExecuteCommands = @ptrCast(try Device.getProc(get, dev, "vkCmdExecuteCommands")),
            .createFence = @ptrCast(try Device.getProc(get, dev, "vkCreateFence")),
            .destroyFence = @ptrCast(try Device.getProc(get, dev, "vkDestroyFence")),
            .getFenceStatus = @ptrCast(try Device.getProc(get, dev, "vkGetFenceStatus")),
            .resetFences = @ptrCast(try Device.getProc(get, dev, "vkResetFences")),
            .waitForFences = @ptrCast(try Device.getProc(get, dev, "vkWaitForFences")),
            .createSemaphore = @ptrCast(try Device.getProc(get, dev, "vkCreateSemaphore")),
            .destroySemaphore = @ptrCast(try Device.getProc(get, dev, "vkDestroySemaphore")),
            .createBuffer = @ptrCast(try Device.getProc(get, dev, "vkCreateBuffer")),
            .destroyBuffer = @ptrCast(try Device.getProc(get, dev, "vkDestroyBuffer")),
            .getBufferMemoryRequirements = @ptrCast(try Device.getProc(get, dev, "vkGetBufferMemoryRequirements")),
            .bindBufferMemory = @ptrCast(try Device.getProc(get, dev, "vkBindBufferMemory")),
            .createBufferView = @ptrCast(try Device.getProc(get, dev, "vkCreateBufferView")),
            .destroyBufferView = @ptrCast(try Device.getProc(get, dev, "vkDestroyBufferView")),
            .createImage = @ptrCast(try Device.getProc(get, dev, "vkCreateImage")),
            .destroyImage = @ptrCast(try Device.getProc(get, dev, "vkDestroyImage")),
            .getImageMemoryRequirements = @ptrCast(try Device.getProc(get, dev, "vkGetImageMemoryRequirements")),
            .bindImageMemory = @ptrCast(try Device.getProc(get, dev, "vkBindImageMemory")),
            .createImageView = @ptrCast(try Device.getProc(get, dev, "vkCreateImageView")),
            .destroyImageView = @ptrCast(try Device.getProc(get, dev, "vkDestroyImageView")),
            .createSampler = @ptrCast(try Device.getProc(get, dev, "vkCreateSampler")),
            .destroySampler = @ptrCast(try Device.getProc(get, dev, "vkDestroySampler")),
            .createRenderPass = @ptrCast(try Device.getProc(get, dev, "vkCreateRenderPass")),
            .destroyRenderPass = @ptrCast(try Device.getProc(get, dev, "vkDestroyRenderPass")),
            .createFramebuffer = @ptrCast(try Device.getProc(get, dev, "vkCreateFramebuffer")),
            .destroyFramebuffer = @ptrCast(try Device.getProc(get, dev, "vkDestroyFramebuffer")),
            .createDescriptorSetLayout = @ptrCast(try Device.getProc(get, dev, "vkCreateDescriptorSetLayout")),
            .destroyDescriptorSetLayout = @ptrCast(try Device.getProc(get, dev, "vkDestroyDescriptorSetLayout")),
            .createPipelineLayout = @ptrCast(try Device.getProc(get, dev, "vkCreatePipelineLayout")),
            .destroyPipelineLayout = @ptrCast(try Device.getProc(get, dev, "vkDestroyPipelineLayout")),
            .createDescriptorPool = @ptrCast(try Device.getProc(get, dev, "vkCreateDescriptorPool")),
            .destroyDescriptorPool = @ptrCast(try Device.getProc(get, dev, "vkDestroyDescriptorPool")),
            .resetDescriptorPool = @ptrCast(try Device.getProc(get, dev, "vkResetDescriptorPool")),
            .allocateDescriptorSets = @ptrCast(try Device.getProc(get, dev, "vkAllocateDescriptorSets")),
            .updateDescriptorSets = @ptrCast(try Device.getProc(get, dev, "vkUpdateDescriptorSets")),
            .createGraphicsPipelines = @ptrCast(try Device.getProc(get, dev, "vkCreateGraphicsPipelines")),
            .createComputePipelines = @ptrCast(try Device.getProc(get, dev, "vkCreateComputePipelines")),
            .destroyPipeline = @ptrCast(try Device.getProc(get, dev, "vkDestroyPipeline")),
            .createPipelineCache = @ptrCast(try Device.getProc(get, dev, "vkCreatePipelineCache")),
            .destroyPipelineCache = @ptrCast(try Device.getProc(get, dev, "vkDestroyPipelineCache")),
            .createShaderModule = @ptrCast(try Device.getProc(get, dev, "vkCreateShaderModule")),
            .destroyShaderModule = @ptrCast(try Device.getProc(get, dev, "vkDestroyShaderModule")),

            .createSwapchain = if (desc.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkCreateSwapchainKHR"))
            else
                null,
            .destroySwapchain = if (desc.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkDestroySwapchainKHR"))
            else
                null,
        };

        for (queue_infos[0..queue_n]) |info| {
            for (0..info.queueCount) |i| {
                var queue: c.VkQueue = undefined;
                ptr.vkGetDeviceQueue(info.queueFamilyIndex, @intCast(i), &queue);
                ptr.queues[ptr.queue_n] = .{
                    .handle = queue,
                    .family = info.queueFamilyIndex,
                    .index = @intCast(i),
                };
                ptr.queue_n += 1;
            }
        }

        return .{ .val = @intFromPtr(ptr) };
    }

    fn getQueues(
        _: *anyopaque,
        allocation: *[ngl.Queue.max]Impl.Queue,
        device: Impl.Device,
    ) []Impl.Queue {
        const dev = cast(device);
        for (0..dev.queue_n) |i| allocation[i] = .{ .val = @intFromPtr(&dev.queues[i]) };
        return allocation[0..dev.queue_n];
    }

    fn getMemoryTypes(
        _: *anyopaque,
        allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
        device: Impl.Device,
    ) []ngl.Memory.Type {
        const dev = cast(device);

        // TODO: May need to store this on device
        var props: c.VkPhysicalDeviceMemoryProperties = undefined;
        dev.instance.vkGetPhysicalDeviceMemoryProperties(dev.physical_device, &props);
        const mask: u32 =
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT |
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
            c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT |
            c.VK_MEMORY_PROPERTY_HOST_CACHED_BIT |
            c.VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT;

        for (0..props.memoryTypeCount) |i| {
            const flags = props.memoryTypes[i].propertyFlags;
            const heap: u4 = @intCast(props.memoryTypes[i].heapIndex);
            // TODO: Handle this somehow
            if (~mask & flags != 0) log.warn("Memory type {} has unexposed flag(s)", .{i});
            allocation[i] = .{
                .properties = .{
                    .device_local = flags & c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT != 0,
                    .host_visible = flags & c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT != 0,
                    .host_coherent = flags & c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT != 0,
                    .host_cached = flags & c.VK_MEMORY_PROPERTY_HOST_CACHED_BIT != 0,
                    .lazily_allocated = flags & c.VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT != 0,
                },
                .heap_index = heap,
            };
        }

        return allocation[0..props.memoryTypeCount];
    }

    fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Memory.Desc,
    ) Error!Impl.Memory {
        const dev = cast(device);

        var ptr = try allocator.create(Memory);
        errdefer allocator.destroy(ptr);

        var mem: c.VkDeviceMemory = undefined;
        try check(dev.vkAllocateMemory(&.{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = desc.size,
            .memoryTypeIndex = desc.type_index,
        }, null, &mem));

        ptr.* = .{ .handle = mem };
        return .{ .val = @intFromPtr(ptr) };
    }

    fn free(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
    ) void {
        const dev = cast(device);
        const mem = Memory.cast(memory);
        dev.vkFreeMemory(mem.handle, null);
        allocator.destroy(mem);
    }

    fn wait(_: *anyopaque, device: Impl.Device) Error!void {
        return check(cast(device).vkDeviceWaitIdle());
    }

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, device: Impl.Device) void {
        const dev = cast(device);
        // NOTE: This assumes that all device-level objects
        // have been destroyed
        dev.vkDestroyDevice(null);
        allocator.destroy(dev);
    }

    // Wrappers --------------------------------------------

    pub inline fn vkDestroyDevice(
        self: *Device,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyDevice.?(self.handle, vk_allocator);
    }

    pub inline fn vkDeviceWaitIdle(self: *Device) c.VkResult {
        return self.deviceWaitIdle.?(self.handle);
    }

    pub inline fn vkGetDeviceQueue(
        self: *Device,
        queue_family: u32,
        queue_index: u32,
        queue: *c.VkQueue,
    ) void {
        self.getDeviceQueue.?(self.handle, queue_family, queue_index, queue);
    }

    pub inline fn vkQueueSubmit(
        self: *Device,
        queue: c.VkQueue,
        submit_count: u32,
        submits: ?[*]const c.VkSubmitInfo,
        fence: c.VkFence,
    ) c.VkResult {
        return self.queueSubmit.?(queue, submit_count, submits, fence);
    }

    pub inline fn vkQueueWaitIdle(self: *Device, queue: c.VkQueue) c.VkResult {
        return self.queueWaitIdle.?(queue);
    }

    pub inline fn vkAllocateMemory(
        self: *Device,
        allocate_info: *const c.VkMemoryAllocateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        memory: *c.VkDeviceMemory,
    ) c.VkResult {
        return self.allocateMemory.?(self.handle, allocate_info, vk_allocator, memory);
    }

    pub inline fn vkFreeMemory(
        self: *Device,
        memory: c.VkDeviceMemory,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.freeMemory.?(self.handle, memory, vk_allocator);
    }

    pub inline fn vkMapMemory(
        self: *Device,
        memory: c.VkDeviceMemory,
        offset: c.VkDeviceSize,
        size: c.VkDeviceSize,
        flags: c.VkMemoryMapFlags,
        data: *?*anyopaque,
    ) c.VkResult {
        return self.mapMemory.?(self.handle, memory, offset, size, flags, data);
    }

    pub inline fn vkUnmapMemory(self: *Device, memory: c.VkDeviceMemory) void {
        return self.unmapMemory.?(self.handle, memory);
    }

    pub inline fn vkFlushMappedMemoryRanges(
        self: *Device,
        memory_range_count: u32,
        memory_ranges: [*]const c.VkMappedMemoryRange,
    ) c.VkResult {
        return self.flushMappedMemoryRanges.?(self.handle, memory_range_count, memory_ranges);
    }

    pub inline fn vkInvalidateMappedMemoryRanges(
        self: *Device,
        memory_range_count: u32,
        memory_ranges: [*]const c.VkMappedMemoryRange,
    ) c.VkResult {
        return self.invalidateMappedMemoryRanges.?(self.handle, memory_range_count, memory_ranges);
    }

    pub inline fn vkCreateCommandPool(
        self: *Device,
        create_info: *const c.VkCommandPoolCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        command_pool: *c.VkCommandPool,
    ) c.VkResult {
        return self.createCommandPool.?(self.handle, create_info, vk_allocator, command_pool);
    }

    pub inline fn vkDestroyCommandPool(
        self: *Device,
        command_pool: c.VkCommandPool,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        return self.destroyCommandPool.?(self.handle, command_pool, vk_allocator);
    }

    pub inline fn vkResetCommandPool(
        self: *Device,
        command_pool: c.VkCommandPool,
        flags: c.VkCommandPoolResetFlags,
    ) c.VkResult {
        return self.resetCommandPool.?(self.handle, command_pool, flags);
    }

    pub inline fn vkAllocateCommandBuffers(
        self: *Device,
        allocate_info: *const c.VkCommandBufferAllocateInfo,
        command_buffers: [*]c.VkCommandBuffer,
    ) c.VkResult {
        return self.allocateCommandBuffers.?(self.handle, allocate_info, command_buffers);
    }

    pub inline fn vkFreeCommandBuffers(
        self: *Device,
        command_pool: c.VkCommandPool,
        command_buffer_count: u32,
        command_buffers: [*]const c.VkCommandBuffer,
    ) void {
        self.freeCommandBuffers.?(self.handle, command_pool, command_buffer_count, command_buffers);
    }

    pub inline fn vkBeginCommandBuffer(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        begin_info: *const c.VkCommandBufferBeginInfo,
    ) c.VkResult {
        return self.beginCommandBuffer.?(command_buffer, begin_info);
    }

    pub inline fn vkEndCommandBuffer(self: *Device, command_buffer: c.VkCommandBuffer) c.VkResult {
        return self.endCommandBuffer.?(command_buffer);
    }

    pub inline fn vkCmdBindPipeline(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        pipeline_bind_point: c.VkPipelineBindPoint,
        pipeline: c.VkPipeline,
    ) void {
        self.cmdBindPipeline.?(command_buffer, pipeline_bind_point, pipeline);
    }

    pub inline fn vkCmdBindDescriptorSets(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        pipeline_bind_point: c.VkPipelineBindPoint,
        pipeline_layout: c.VkPipelineLayout,
        first_set: u32,
        descriptor_set_count: u32,
        descriptor_sets: [*]const c.VkDescriptorSet,
        dynamic_offset_count: u32,
        dynamic_offsets: ?[*]const u32,
    ) void {
        self.cmdBindDescriptorSets.?(
            command_buffer,
            pipeline_bind_point,
            pipeline_layout,
            first_set,
            descriptor_set_count,
            descriptor_sets,
            dynamic_offset_count,
            dynamic_offsets,
        );
    }

    pub inline fn vkCmdPushConstants(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        pipeline_layout: c.VkPipelineLayout,
        stage_flags: c.VkShaderStageFlags,
        offset: u32,
        size: u32,
        values: *const anyopaque,
    ) void {
        self.cmdPushConstants.?(command_buffer, pipeline_layout, stage_flags, offset, size, values);
    }

    pub inline fn vkCmdBindIndexBuffer(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        index_type: c.VkIndexType,
    ) void {
        self.cmdBindIndexBuffer.?(command_buffer, buffer, offset, index_type);
    }

    pub inline fn vkCmdBindVertexBuffers(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        first_binding: u32,
        binding_count: u32,
        buffers: [*]const c.VkBuffer,
        offsets: [*]const c.VkDeviceSize,
    ) void {
        self.cmdBindVertexBuffers.?(command_buffer, first_binding, binding_count, buffers, offsets);
    }

    pub inline fn vkCmdSetViewport(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        first_viewport: u32,
        viewport_count: u32,
        viewports: [*]const c.VkViewport,
    ) void {
        self.cmdSetViewport.?(command_buffer, first_viewport, viewport_count, viewports);
    }

    pub inline fn vkCmdSetScissor(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        first_scissor: u32,
        scissor_count: u32,
        scissors: [*]const c.VkRect2D,
    ) void {
        self.cmdSetScissor.?(command_buffer, first_scissor, scissor_count, scissors);
    }

    pub inline fn vkCmdSetStencilReference(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        face_mask: c.VkStencilFaceFlags,
        reference: u32,
    ) void {
        self.cmdSetStencilReference.?(command_buffer, face_mask, reference);
    }

    pub inline fn vkCmdSetBlendConstants(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        constants: [*]const f32,
    ) void {
        self.cmdSetBlendConstants.?(command_buffer, constants);
    }

    pub inline fn vkCmdBeginRenderPass(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        render_pass_begin: *const c.VkRenderPassBeginInfo,
        contents: c.VkSubpassContents,
    ) void {
        self.cmdBeginRenderPass.?(command_buffer, render_pass_begin, contents);
    }

    pub inline fn vkCmdNextSubpass(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        contents: c.VkSubpassContents,
    ) void {
        self.cmdNextSubpass.?(command_buffer, contents);
    }

    pub inline fn vkCmdEndRenderPass(self: *Device, command_buffer: c.VkCommandBuffer) void {
        self.cmdEndRenderPass.?(command_buffer);
    }

    pub inline fn vkCmdDraw(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        self.cmdDraw.?(command_buffer, vertex_count, instance_count, first_vertex, first_instance);
    }

    pub inline fn vkCmdDrawIndexed(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        self.cmdDrawIndexed.?(
            command_buffer,
            index_count,
            instance_count,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    pub inline fn vkCmdDrawIndirect(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        draw_count: u32,
        stride: u32,
    ) void {
        self.cmdDrawIndirect.?(command_buffer, buffer, offset, draw_count, stride);
    }

    pub inline fn vkCmdDrawIndexedIndirect(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        draw_count: u32,
        stride: u32,
    ) void {
        self.cmdDrawIndexedIndirect.?(command_buffer, buffer, offset, draw_count, stride);
    }

    pub inline fn vkCmdDispatch(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        group_count_x: u32,
        group_count_y: u32,
        group_count_z: u32,
    ) void {
        self.cmdDispatch.?(command_buffer, group_count_x, group_count_y, group_count_z);
    }

    pub inline fn vkCmdDispatchIndirect(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
    ) void {
        self.cmdDispatchIndirect.?(command_buffer, buffer, offset);
    }

    pub inline fn vkCmdFillBuffer(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        size: c.VkDeviceSize,
        value: u32,
    ) void {
        self.cmdFillBuffer.?(command_buffer, buffer, offset, size, value);
    }

    pub inline fn vkCmdCopyBuffer(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        source_buffer: c.VkBuffer,
        dest_buffer: c.VkBuffer,
        region_count: u32,
        regions: [*]const c.VkBufferCopy,
    ) void {
        self.cmdCopyBuffer.?(command_buffer, source_buffer, dest_buffer, region_count, regions);
    }

    pub inline fn vkCmdCopyImage(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        source_image: c.VkImage,
        source_image_layout: c.VkImageLayout,
        dest_image: c.VkImage,
        dest_image_layout: c.VkImageLayout,
        region_count: u32,
        regions: [*]const c.VkImageCopy,
    ) void {
        self.cmdCopyImage.?(
            command_buffer,
            source_image,
            source_image_layout,
            dest_image,
            dest_image_layout,
            region_count,
            regions,
        );
    }

    pub inline fn vkCmdCopyBufferToImage(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        source_buffer: c.VkBuffer,
        dest_image: c.VkImage,
        dest_image_layout: c.VkImageLayout,
        region_count: u32,
        regions: [*]const c.VkBufferImageCopy,
    ) void {
        self.cmdCopyBufferToImage.?(
            command_buffer,
            source_buffer,
            dest_image,
            dest_image_layout,
            region_count,
            regions,
        );
    }

    pub inline fn vkCmdCopyImageToBuffer(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        source_image: c.VkImage,
        source_image_layout: c.VkImageLayout,
        dest_buffer: c.VkBuffer,
        region_count: u32,
        regions: [*]const c.VkBufferImageCopy,
    ) void {
        self.cmdCopyImageToBuffer.?(
            command_buffer,
            source_image,
            source_image_layout,
            dest_buffer,
            region_count,
            regions,
        );
    }

    pub inline fn vkCmdPipelineBarrier(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        source_stage_mask: c.VkPipelineStageFlags,
        dest_stage_mask: c.VkPipelineStageFlags,
        dependency_flags: c.VkDependencyFlags,
        memory_barrier_count: u32,
        memory_barriers: ?[*]const c.VkMemoryBarrier,
        buffer_memory_barrier_count: u32,
        buffer_memory_barriers: ?[*]const c.VkBufferMemoryBarrier,
        image_memory_barrier_count: u32,
        image_memory_barriers: ?[*]const c.VkImageMemoryBarrier,
    ) void {
        self.cmdPipelineBarrier.?(
            command_buffer,
            source_stage_mask,
            dest_stage_mask,
            dependency_flags,
            memory_barrier_count,
            memory_barriers,
            buffer_memory_barrier_count,
            buffer_memory_barriers,
            image_memory_barrier_count,
            image_memory_barriers,
        );
    }

    pub inline fn vkCmdExecuteCommands(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        secondary_command_buffer_count: u32,
        secondary_command_buffers: [*]const c.VkCommandBuffer,
    ) void {
        self.cmdExecuteCommands.?(
            command_buffer,
            secondary_command_buffer_count,
            secondary_command_buffers,
        );
    }

    pub inline fn vkCreateFence(
        self: *Device,
        create_info: *const c.VkFenceCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        fence: *c.VkFence,
    ) c.VkResult {
        return self.createFence.?(self.handle, create_info, vk_allocator, fence);
    }

    pub inline fn vkDestroyFence(
        self: *Device,
        fence: c.VkFence,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyFence.?(self.handle, fence, vk_allocator);
    }

    pub inline fn vkGetFenceStatus(self: *Device, fence: c.VkFence) c.VkResult {
        return self.getFenceStatus.?(self.handle, fence);
    }

    pub inline fn vkResetFences(
        self: *Device,
        fence_count: u32,
        fences: [*]const c.VkFence,
    ) c.VkResult {
        return self.resetFences.?(self.handle, fence_count, fences);
    }

    pub inline fn vkWaitForFences(
        self: *Device,
        fence_count: u32,
        fences: [*]const c.VkFence,
        wait_all: c.VkBool32,
        timeout: u64,
    ) c.VkResult {
        return self.waitForFences.?(self.handle, fence_count, fences, wait_all, timeout);
    }

    pub inline fn vkCreateSemaphore(
        self: *Device,
        create_info: *const c.VkSemaphoreCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        semaphore: *c.VkSemaphore,
    ) c.VkResult {
        return self.createSemaphore.?(self.handle, create_info, vk_allocator, semaphore);
    }

    pub inline fn vkDestroySemaphore(
        self: *Device,
        semaphore: c.VkSemaphore,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroySemaphore.?(self.handle, semaphore, vk_allocator);
    }

    pub inline fn vkCreateBuffer(
        self: *Device,
        create_info: *const c.VkBufferCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        buffer: *c.VkBuffer,
    ) c.VkResult {
        return self.createBuffer.?(self.handle, create_info, vk_allocator, buffer);
    }

    pub inline fn vkDestroyBuffer(
        self: *Device,
        buffer: c.VkBuffer,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyBuffer.?(self.handle, buffer, vk_allocator);
    }

    pub inline fn vkGetBufferMemoryRequirements(
        self: *Device,
        buffer: c.VkBuffer,
        memory_requirements: *c.VkMemoryRequirements,
    ) void {
        self.getBufferMemoryRequirements.?(self.handle, buffer, memory_requirements);
    }

    pub inline fn vkBindBufferMemory(
        self: *Device,
        buffer: c.VkBuffer,
        memory: c.VkDeviceMemory,
        memory_offset: c.VkDeviceSize,
    ) c.VkResult {
        return self.bindBufferMemory.?(self.handle, buffer, memory, memory_offset);
    }

    pub inline fn vkCreateBufferView(
        self: *Device,
        create_info: *const c.VkBufferViewCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        buffer_view: *c.VkBufferView,
    ) c.VkResult {
        return self.createBufferView.?(self.handle, create_info, vk_allocator, buffer_view);
    }

    pub inline fn vkDestroyBufferView(
        self: *Device,
        buffer_view: c.VkBufferView,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyBufferView.?(self.handle, buffer_view, vk_allocator);
    }

    pub inline fn vkCreateImage(
        self: *Device,
        create_info: *const c.VkImageCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        image: *c.VkImage,
    ) c.VkResult {
        return self.createImage.?(self.handle, create_info, vk_allocator, image);
    }

    pub inline fn vkDestroyImage(
        self: *Device,
        image: c.VkImage,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyImage.?(self.handle, image, vk_allocator);
    }

    pub inline fn vkGetImageMemoryRequirements(
        self: *Device,
        image: c.VkImage,
        memory_requirements: *c.VkMemoryRequirements,
    ) void {
        self.getImageMemoryRequirements.?(self.handle, image, memory_requirements);
    }

    pub inline fn vkBindImageMemory(
        self: *Device,
        image: c.VkImage,
        memory: c.VkDeviceMemory,
        memory_offset: c.VkDeviceSize,
    ) c.VkResult {
        return self.bindImageMemory.?(self.handle, image, memory, memory_offset);
    }

    pub inline fn vkCreateImageView(
        self: *Device,
        create_info: *const c.VkImageViewCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        image_view: *c.VkImageView,
    ) c.VkResult {
        return self.createImageView.?(self.handle, create_info, vk_allocator, image_view);
    }

    pub inline fn vkDestroyImageView(
        self: *Device,
        image_view: c.VkImageView,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyImageView.?(self.handle, image_view, vk_allocator);
    }

    pub inline fn vkCreateSampler(
        self: *Device,
        create_info: *const c.VkSamplerCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        sampler: *c.VkSampler,
    ) c.VkResult {
        return self.createSampler.?(self.handle, create_info, vk_allocator, sampler);
    }

    pub inline fn vkDestroySampler(
        self: *Device,
        sampler: c.VkSampler,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroySampler.?(self.handle, sampler, vk_allocator);
    }

    pub inline fn vkCreateRenderPass(
        self: *Device,
        create_info: *const c.VkRenderPassCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        render_pass: *c.VkRenderPass,
    ) c.VkResult {
        return self.createRenderPass.?(self.handle, create_info, vk_allocator, render_pass);
    }

    pub inline fn vkDestroyRenderPass(
        self: *Device,
        render_pass: c.VkRenderPass,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyRenderPass.?(self.handle, render_pass, vk_allocator);
    }

    pub inline fn vkCreateFramebuffer(
        self: *Device,
        create_info: *const c.VkFramebufferCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        framebuffer: *c.VkFramebuffer,
    ) c.VkResult {
        return self.createFramebuffer.?(self.handle, create_info, vk_allocator, framebuffer);
    }

    pub inline fn vkDestroyFramebuffer(
        self: *Device,
        framebuffer: c.VkFramebuffer,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyFramebuffer.?(self.handle, framebuffer, vk_allocator);
    }

    pub inline fn vkCreateDescriptorSetLayout(
        self: *Device,
        create_info: *const c.VkDescriptorSetLayoutCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        descriptor_set_layout: *c.VkDescriptorSetLayout,
    ) c.VkResult {
        return self.createDescriptorSetLayout.?(
            self.handle,
            create_info,
            vk_allocator,
            descriptor_set_layout,
        );
    }

    pub inline fn vkDestroyDescriptorSetLayout(
        self: *Device,
        descriptor_set_layout: c.VkDescriptorSetLayout,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyDescriptorSetLayout.?(self.handle, descriptor_set_layout, vk_allocator);
    }

    pub inline fn vkCreatePipelineLayout(
        self: *Device,
        create_info: *const c.VkPipelineLayoutCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        pipeline_layout: *c.VkPipelineLayout,
    ) c.VkResult {
        return self.createPipelineLayout.?(self.handle, create_info, vk_allocator, pipeline_layout);
    }

    pub inline fn vkDestroyPipelineLayout(
        self: *Device,
        pipeline_layout: c.VkPipelineLayout,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyPipelineLayout.?(self.handle, pipeline_layout, vk_allocator);
    }

    pub inline fn vkCreateDescriptorPool(
        self: *Device,
        create_info: *const c.VkDescriptorPoolCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        descriptor_pool: *c.VkDescriptorPool,
    ) c.VkResult {
        return self.createDescriptorPool.?(self.handle, create_info, vk_allocator, descriptor_pool);
    }

    pub inline fn vkDestroyDescriptorPool(
        self: *Device,
        descriptor_pool: c.VkDescriptorPool,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyDescriptorPool.?(self.handle, descriptor_pool, vk_allocator);
    }

    pub inline fn vkResetDescriptorPool(
        self: *Device,
        descriptor_pool: c.VkDescriptorPool,
        flags: c.VkDescriptorPoolResetFlags,
    ) c.VkResult {
        return self.resetDescriptorPool.?(self.handle, descriptor_pool, flags);
    }

    pub inline fn vkAllocateDescriptorSets(
        self: *Device,
        allocate_info: *const c.VkDescriptorSetAllocateInfo,
        descriptor_sets: [*]c.VkDescriptorSet,
    ) c.VkResult {
        return self.allocateDescriptorSets.?(self.handle, allocate_info, descriptor_sets);
    }

    pub inline fn vkUpdateDescriptorSets(
        self: *Device,
        descriptor_write_count: u32,
        descriptor_writes: ?[*]const c.VkWriteDescriptorSet,
        descriptor_copy_count: u32,
        descriptor_copies: ?[*]const c.VkCopyDescriptorSet,
    ) void {
        self.updateDescriptorSets.?(
            self.handle,
            descriptor_write_count,
            descriptor_writes,
            descriptor_copy_count,
            descriptor_copies,
        );
    }

    pub inline fn vkCreateGraphicsPipelines(
        self: *Device,
        pipeline_cache: c.VkPipelineCache,
        create_info_count: u32,
        create_infos: [*]const c.VkGraphicsPipelineCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        pipelines: [*]c.VkPipeline,
    ) c.VkResult {
        return self.createGraphicsPipelines.?(
            self.handle,
            pipeline_cache,
            create_info_count,
            create_infos,
            vk_allocator,
            pipelines,
        );
    }

    pub inline fn vkCreateComputePipelines(
        self: *Device,
        pipeline_cache: c.VkPipelineCache,
        create_info_count: u32,
        create_infos: [*]const c.VkComputePipelineCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        pipelines: [*]c.VkPipeline,
    ) c.VkResult {
        return self.createComputePipelines.?(
            self.handle,
            pipeline_cache,
            create_info_count,
            create_infos,
            vk_allocator,
            pipelines,
        );
    }

    pub inline fn vkDestroyPipeline(
        self: *Device,
        pipeline: c.VkPipeline,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyPipeline.?(self.handle, pipeline, vk_allocator);
    }

    pub inline fn vkCreatePipelineCache(
        self: *Device,
        create_info: *const c.VkPipelineCacheCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        pipeline_cache: *c.VkPipelineCache,
    ) c.VkResult {
        return self.createPipelineCache.?(self.handle, create_info, vk_allocator, pipeline_cache);
    }

    pub inline fn vkDestroyPipelineCache(
        self: *Device,
        pipeline_cache: c.VkPipelineCache,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyPipelineCache.?(self.handle, pipeline_cache, vk_allocator);
    }

    pub inline fn vkCreateShaderModule(
        self: *Device,
        create_info: *const c.VkShaderModuleCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        shader_module: *c.VkShaderModule,
    ) c.VkResult {
        return self.createShaderModule.?(self.handle, create_info, vk_allocator, shader_module);
    }

    pub inline fn vkDestroyShaderModule(
        self: *Device,
        shader_module: c.VkShaderModule,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyShaderModule.?(self.handle, shader_module, vk_allocator);
    }

    pub inline fn vkCreateSwapchainKHR(
        self: *Device,
        create_info: *const c.VkSwapchainCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        swapchain: *c.VkSwapchainKHR,
    ) c.VkResult {
        return self.createSwapchain.?(self.handle, create_info, vk_allocator, swapchain);
    }

    pub inline fn vkDestroySwapchainKHR(
        self: *Device,
        swapchain: c.VkSwapchainKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroySwapchain.?(self.handle, swapchain, vk_allocator);
    }
};

pub const Queue = struct {
    handle: c.VkQueue,
    family: u32,
    index: u32,

    pub inline fn cast(impl: Impl.Queue) *Queue {
        return impl.ptr(Queue);
    }

    // TODO: Don't allocate on every call
    fn submit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        queue: Impl.Queue,
        fence: ?Impl.Fence,
        submits: []const ngl.Queue.Submit,
    ) Error!void {
        var subm_info: [1]c.VkSubmitInfo = undefined;
        var subm_infos = if (submits.len > 1) try allocator.alloc(
            c.VkSubmitInfo,
            submits.len,
        ) else &subm_info;
        defer if (subm_infos.len > 1) allocator.free(subm_infos);

        var cmd_buf: [1]c.VkCommandBuffer = undefined;
        var cmd_bufs: []c.VkCommandBuffer = undefined;
        var sema: [1]c.VkSemaphore = undefined;
        var semas: []c.VkSemaphore = undefined;
        var stage: [1]c.VkPipelineStageFlags = undefined;
        var stages: []c.VkPipelineStageFlags = undefined;
        {
            var cmd_buf_n: usize = 0;
            var sema_n: usize = 0;
            var stage_n: usize = 0;
            for (submits) |subms| {
                cmd_buf_n += subms.commands.len;
                sema_n += subms.wait.len + subms.signal.len;
                stage_n += subms.wait.len;
            }

            cmd_bufs = if (cmd_buf_n > 1) try allocator.alloc(
                c.VkCommandBuffer,
                cmd_buf_n,
            ) else &cmd_buf;
            errdefer if (cmd_buf_n > 1) allocator.free(cmd_bufs);

            semas = if (sema_n > 1) try allocator.alloc(
                c.VkSemaphore,
                sema_n,
            ) else &sema;
            errdefer if (sema_n > 1) allocator.free(semas);

            stages = if (stage_n > 1) try allocator.alloc(
                c.VkPipelineStageFlags,
                stage_n,
            ) else &stage;
        }
        defer if (cmd_bufs.len > 1) allocator.free(cmd_bufs);
        defer if (semas.len > 1) allocator.free(semas);
        defer if (stages.len > 1) allocator.free(stages);

        var cmd_bufs_ptr = cmd_bufs.ptr;
        var semas_ptr = semas.ptr;
        var stages_ptr = stages.ptr;

        for (subm_infos[0..submits.len], submits) |*info, subm| {
            info.* = .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pNext = null,
                .waitSemaphoreCount = @intCast(subm.wait.len),
                .pWaitSemaphores = undefined, // Set below
                .pWaitDstStageMask = undefined, // Set below
                .commandBufferCount = @intCast(subm.commands.len),
                .pCommandBuffers = undefined, // Set below
                .signalSemaphoreCount = @intCast(subm.signal.len),
                .pSignalSemaphores = undefined, // Set below
            };

            if (subm.commands.len > 0) {
                info.pCommandBuffers = cmd_bufs_ptr;
                for (cmd_bufs_ptr, subm.commands) |*handle, cmds|
                    handle.* = CommandBuffer.cast(cmds.command_buffer.impl).handle;
                cmd_bufs_ptr += subm.commands.len;
            } else info.pCommandBuffers = null;

            if (subm.wait.len > 0) {
                info.pWaitSemaphores = semas_ptr;
                info.pWaitDstStageMask = stages_ptr;
                for (semas_ptr, stages_ptr, subm.wait) |*handle, *mask, wsema| {
                    handle.* = Semaphore.cast(wsema.semaphore.impl).handle;
                    mask.* = conv.toVkPipelineStageFlags(.dest, wsema.stage_mask);
                }
                semas_ptr += subm.wait.len;
                stages_ptr += subm.wait.len;
            } else {
                info.pWaitSemaphores = null;
                info.pWaitDstStageMask = null;
            }

            if (subm.signal.len > 0) {
                info.pSignalSemaphores = semas_ptr;
                for (semas_ptr, subm.signal) |*handle, ssema|
                    // No signal stage mask on vanilla submission
                    handle.* = Semaphore.cast(ssema.semaphore.impl).handle;
                semas_ptr += subm.signal.len;
            } else info.pSignalSemaphores = null;
        }

        try check(Device.cast(device).vkQueueSubmit(
            cast(queue).handle,
            @intCast(submits.len), // Note `submits`
            if (submits.len > 0) subm_infos.ptr else null,
            if (fence) |x| Fence.cast(x).handle else null_handle,
        ));
    }

    fn wait(_: *anyopaque, device: Impl.Device, queue: Impl.Queue) Error!void {
        return check(Device.cast(device).vkQueueWaitIdle(cast(queue).handle));
    }
};

// TODO: Don't allocate this type on the heap
pub const Memory = struct {
    handle: c.VkDeviceMemory,

    pub inline fn cast(impl: Impl.Memory) *Memory {
        return impl.ptr(Memory);
    }

    fn map(
        _: *anyopaque,
        device: Impl.Device,
        memory: Impl.Memory,
        offset: u64,
        size: ?u64,
    ) Error![*]u8 {
        var data: ?*anyopaque = undefined;
        try check(Device.cast(device).vkMapMemory(
            cast(memory).handle,
            offset,
            size orelse c.VK_WHOLE_SIZE,
            0,
            &data,
        ));
        return @ptrCast(data);
    }

    fn unmap(_: *anyopaque, device: Impl.Device, memory: Impl.Memory) void {
        Device.cast(device).vkUnmapMemory(cast(memory).handle);
    }

    // TODO: Don't allocate on every call
    fn flushOrInvalidateMapped(
        comptime call: enum { flush, invalidate },
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        const dev = Device.cast(device);
        const mem = cast(memory);

        var mapped_range: [1]c.VkMappedMemoryRange = undefined;
        var mapped_ranges = if (offsets.len > 1) try allocator.alloc(
            c.VkMappedMemoryRange,
            offsets.len,
        ) else &mapped_range;
        defer if (mapped_ranges.len > 1) allocator.free(mapped_ranges);

        if (sizes) |szs| {
            for (mapped_ranges, offsets, szs) |*range, offset, size|
                range.* = .{
                    .sType = c.VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                    .pNext = null,
                    .memory = mem.handle,
                    .offset = offset,
                    .size = size,
                };
        } else mapped_ranges[0] = .{
            .sType = c.VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .pNext = null,
            .memory = mem.handle,
            .offset = offsets[0],
            .size = c.VK_WHOLE_SIZE,
        };

        const callable = switch (call) {
            .flush => Device.vkFlushMappedMemoryRanges,
            .invalidate => Device.vkInvalidateMappedMemoryRanges,
        };
        try check(callable(dev, @intCast(mapped_ranges.len), mapped_ranges.ptr));
    }

    fn flushMapped(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        return flushOrInvalidateMapped(.flush, allocator, device, memory, offsets, sizes);
    }

    fn invalidateMapped(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        return flushOrInvalidateMapped(.invalidate, allocator, device, memory, offsets, sizes);
    }
};

fn getFeature(
    _: *anyopaque,
    _: std.mem.Allocator,
    instance: Impl.Instance,
    device_desc: ngl.Device.Desc,
    feature: *ngl.Feature,
) Error!void {
    const inst = Instance.cast(instance);
    const phys_dev: c.VkPhysicalDevice =
        @ptrFromInt(device_desc.impl orelse return Error.InvalidArgument);

    // TODO: Maybe define this conversion in `conv.zig`
    const convSpls = struct {
        fn f(vk_flags: c.VkSampleCountFlags) ngl.SampleCount.Flags {
            var flags = ngl.SampleCount.Flags{};
            if (vk_flags & c.VK_SAMPLE_COUNT_1_BIT != 0) flags.@"1" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_2_BIT != 0) flags.@"2" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_4_BIT != 0) flags.@"4" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_8_BIT != 0) flags.@"8" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_16_BIT != 0) flags.@"16" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_32_BIT != 0) flags.@"32" = true;
            if (vk_flags & c.VK_SAMPLE_COUNT_64_BIT != 0) flags.@"64" = true;
            return flags;
        }
    }.f;

    switch (feature.*) {
        .core => |*feat| {
            const l = blk: {
                var props: c.VkPhysicalDeviceProperties = undefined;
                inst.vkGetPhysicalDeviceProperties(phys_dev, &props);
                break :blk props.limits;
            };
            const f = blk: {
                var feats: c.VkPhysicalDeviceFeatures = undefined;
                inst.vkGetPhysicalDeviceFeatures(phys_dev, &feats);
                break :blk feats;
            };
            feat.* = .{
                .memory = .{
                    .max_count = l.maxMemoryAllocationCount,
                    // TODO: Requires v1.1
                    //.max_size = 1073741824,
                    .min_map_alignment = l.minMemoryMapAlignment,
                },
                .sampler = .{
                    .max_count = l.maxSamplerAllocationCount,
                    .max_anisotropy = @intFromFloat(@min(16, @max(1, l.maxSamplerAnisotropy))),
                    // TODO: Requires v1.2
                    .address_mode_mirror_clamp_to_edge = false,
                },
                .image = .{
                    .max_dimension_1d = l.maxImageDimension1D,
                    .max_dimension_2d = l.maxImageDimension2D,
                    .max_dimension_cube = l.maxImageDimensionCube,
                    .max_dimension_3d = l.maxImageDimension3D,
                    .max_layers = l.maxImageArrayLayers,
                    .sampled_color_sample_counts = convSpls(l.sampledImageColorSampleCounts),
                    .sampled_integer_sample_counts = convSpls(l.sampledImageIntegerSampleCounts),
                    .sampled_depth_sample_counts = convSpls(l.sampledImageDepthSampleCounts),
                    .sampled_stencil_sample_counts = convSpls(l.sampledImageStencilSampleCounts),
                    .storage_sample_counts = convSpls(l.storageImageSampleCounts),
                    .cube_array = f.imageCubeArray == c.VK_TRUE,
                },
                .buffer = .{
                    // TODO: Requires v1.3
                    //.max_size = 1073741824,
                    .max_texel_elements = l.maxTexelBufferElements,
                    .min_texel_offset_alignment = l.minTexelBufferOffsetAlignment,
                },
                .descriptor = .{
                    .max_bound_sets = l.maxBoundDescriptorSets,
                    .max_samplers = l.maxDescriptorSetSamplers,
                    .max_sampled_images = l.maxDescriptorSetSampledImages,
                    .max_storage_images = l.maxDescriptorSetStorageImages,
                    .max_uniform_buffers = l.maxDescriptorSetUniformBuffers,
                    .max_storage_buffers = l.maxDescriptorSetStorageBuffers,
                    .max_input_attachments = l.maxDescriptorSetInputAttachments,
                    .max_per_stage_samplers = l.maxPerStageDescriptorSamplers,
                    .max_per_stage_sampled_images = l.maxPerStageDescriptorSampledImages,
                    .max_per_stage_storage_images = l.maxPerStageDescriptorStorageImages,
                    .max_per_stage_uniform_buffers = l.maxPerStageDescriptorUniformBuffers,
                    .max_per_stage_storage_buffers = l.maxPerStageDescriptorStorageBuffers,
                    .max_per_stage_input_attachments = l.maxPerStageDescriptorInputAttachments,
                    .max_per_stage_resources = l.maxPerStageResources,
                    .max_push_constants_size = l.maxPushConstantsSize,
                    .min_uniform_buffer_offset_alignment = l.minUniformBufferOffsetAlignment,
                    .max_uniform_buffer_range = l.maxUniformBufferRange,
                    .min_storage_buffer_offset_alignment = l.minStorageBufferOffsetAlignment,
                    .max_storage_buffer_range = l.maxStorageBufferRange,
                },
                .subpass = .{
                    .max_color_attachments = @min(
                        @as(u17, ngl.RenderPass.max_attachment_index) + 1,
                        l.maxColorAttachments,
                    ),
                },
                .frame_buffer = .{
                    .max_width = l.maxFramebufferWidth,
                    .max_height = l.maxFramebufferHeight,
                    .max_layers = l.maxFramebufferLayers,
                    .color_sample_counts = convSpls(l.framebufferColorSampleCounts),
                    // TODO: Requires v1.2
                    //.integer_sample_counts = .{ .@"1" = true },
                    .depth_sample_counts = convSpls(l.framebufferDepthSampleCounts),
                    .stencil_sample_counts = convSpls(l.framebufferStencilSampleCounts),
                    .no_attachment_sample_counts = convSpls(l.framebufferNoAttachmentsSampleCounts),
                },
                .draw = .{
                    .max_index_value = l.maxDrawIndexedIndexValue,
                    .max_indirect_count = l.maxDrawIndirectCount,
                    .indirect_first_instance = f.drawIndirectFirstInstance == c.VK_TRUE,
                },
                .primitive = .{
                    .max_bindings = l.maxVertexInputBindings,
                    .max_attributes = l.maxVertexInputAttributes,
                    .max_binding_stride = l.maxVertexInputBindingStride,
                    .max_attribute_offset = l.maxVertexInputAttributeOffset,
                },
                .viewport = .{
                    .max_width = l.maxViewportDimensions[0],
                    .max_height = l.maxViewportDimensions[1],
                    .min_bound = l.viewportBoundsRange[0],
                    .max_bound = l.viewportBoundsRange[1],
                },
                .rasterization = .{
                    .polygon_mode_line = f.fillModeNonSolid == c.VK_TRUE,
                    .depth_clamp = f.depthClamp == c.VK_TRUE,
                    .depth_bias_clamp = f.depthBiasClamp == c.VK_TRUE,
                    .alpha_to_one = f.alphaToOne == c.VK_TRUE,
                },
                .color_blend = .{
                    .independent_blend = f.independentBlend == c.VK_TRUE,
                },
                .vertex = .{
                    .max_output_components = l.maxVertexOutputComponents,
                    .stores_and_atomics = f.vertexPipelineStoresAndAtomics == c.VK_TRUE,
                },
                .fragment = .{
                    .max_input_components = l.maxFragmentInputComponents,
                    .max_output_attachments = l.maxFragmentOutputAttachments,
                    .max_combined_output_resources = l.maxFragmentCombinedOutputResources,
                    .stores_and_atomics = f.fragmentStoresAndAtomics == c.VK_TRUE,
                },
                .compute = .{
                    .max_shared_memory_size = l.maxComputeSharedMemorySize,
                    .max_group_count_x = l.maxComputeWorkGroupCount[0],
                    .max_group_count_y = l.maxComputeWorkGroupCount[1],
                    .max_group_count_z = l.maxComputeWorkGroupCount[2],
                    .max_local_invocations = l.maxComputeWorkGroupInvocations,
                    .max_local_size_x = l.maxComputeWorkGroupSize[0],
                    .max_local_size_y = l.maxComputeWorkGroupSize[1],
                    .max_local_size_z = l.maxComputeWorkGroupSize[2],
                },
            };
        },

        .presentation => |*feat| if (device_desc.feature_set.presentation) {
            feat.* = {};
        } else return Error.NotPresent,
    }
}

const vtable = Impl.VTable{
    .deinit = deinit,

    .initInstance = Instance.init,
    .listDevices = Instance.listDevices,
    .deinitInstance = Instance.deinit,

    .initDevice = Device.init,
    .getQueues = Device.getQueues,
    .getMemoryTypes = Device.getMemoryTypes,
    .allocMemory = Device.alloc,
    .freeMemory = Device.free,
    .waitDevice = Device.wait,
    .deinitDevice = Device.deinit,

    .submit = Queue.submit,
    .waitQueue = Queue.wait,

    .mapMemory = Memory.map,
    .unmapMemory = Memory.unmap,
    .flushMappedMemory = Memory.flushMapped,
    .invalidateMappedMemory = Memory.invalidateMapped,

    .getFeature = getFeature,

    .initCommandPool = @import("cmd.zig").CommandPool.init,
    .allocCommandBuffers = @import("cmd.zig").CommandPool.alloc,
    .resetCommandPool = @import("cmd.zig").CommandPool.reset,
    .freeCommandBuffers = @import("cmd.zig").CommandPool.free,
    .deinitCommandPool = @import("cmd.zig").CommandPool.deinit,

    .beginCommandBuffer = @import("cmd.zig").CommandBuffer.begin,
    .setPipeline = @import("cmd.zig").CommandBuffer.setPipeline,
    .setDescriptors = @import("cmd.zig").CommandBuffer.setDescriptors,
    .setPushConstants = @import("cmd.zig").CommandBuffer.setPushConstants,
    .setIndexBuffer = @import("cmd.zig").CommandBuffer.setIndexBuffer,
    .setVertexBuffers = @import("cmd.zig").CommandBuffer.setVertexBuffers,
    .setViewport = @import("cmd.zig").CommandBuffer.setViewport,
    .setStencilReference = @import("cmd.zig").CommandBuffer.setStencilReference,
    .setBlendConstants = @import("cmd.zig").CommandBuffer.setBlendConstants,
    .beginRenderPass = @import("cmd.zig").CommandBuffer.beginRenderPass,
    .nextSubpass = @import("cmd.zig").CommandBuffer.nextSubpass,
    .endRenderPass = @import("cmd.zig").CommandBuffer.endRenderPass,
    .draw = @import("cmd.zig").CommandBuffer.draw,
    .drawIndexed = @import("cmd.zig").CommandBuffer.drawIndexed,
    .drawIndirect = @import("cmd.zig").CommandBuffer.drawIndirect,
    .drawIndexedIndirect = @import("cmd.zig").CommandBuffer.drawIndexedIndirect,
    .dispatch = @import("cmd.zig").CommandBuffer.dispatch,
    .dispatchIndirect = @import("cmd.zig").CommandBuffer.dispatchIndirect,
    .fillBuffer = @import("cmd.zig").CommandBuffer.fillBuffer,
    .copyBuffer = @import("cmd.zig").CommandBuffer.copyBuffer,
    .copyImage = @import("cmd.zig").CommandBuffer.copyImage,
    .copyBufferToImage = @import("cmd.zig").CommandBuffer.copyBufferToImage,
    .copyImageToBuffer = @import("cmd.zig").CommandBuffer.copyImageToBuffer,
    .pipelineBarrier = @import("cmd.zig").CommandBuffer.pipelineBarrier,
    .executeCommands = @import("cmd.zig").CommandBuffer.executeCommands,
    .endCommandBuffer = @import("cmd.zig").CommandBuffer.end,

    .initFence = @import("sync.zig").Fence.init,
    .resetFences = @import("sync.zig").Fence.reset,
    .waitFences = @import("sync.zig").Fence.wait,
    .getFenceStatus = @import("sync.zig").Fence.getStatus,
    .deinitFence = @import("sync.zig").Fence.deinit,

    .initSemaphore = @import("sync.zig").Semaphore.init,
    .deinitSemaphore = @import("sync.zig").Semaphore.deinit,

    .getFormatFeatures = @import("res.zig").getFormatFeatures,

    .initBuffer = @import("res.zig").Buffer.init,
    .getMemoryRequirementsBuffer = @import("res.zig").Buffer.getMemoryRequirements,
    .bindMemoryBuffer = @import("res.zig").Buffer.bindMemory,
    .deinitBuffer = @import("res.zig").Buffer.deinit,

    .initBufferView = @import("res.zig").BufferView.init,
    .deinitBufferView = @import("res.zig").BufferView.deinit,

    .initImage = @import("res.zig").Image.init,
    .getMemoryRequirementsImage = @import("res.zig").Image.getMemoryRequirements,
    .bindMemoryImage = @import("res.zig").Image.bindMemory,
    .deinitImage = @import("res.zig").Image.deinit,

    .initImageView = @import("res.zig").ImageView.init,
    .deinitImageView = @import("res.zig").ImageView.deinit,

    .initSampler = @import("res.zig").Sampler.init,
    .deinitSampler = @import("res.zig").Sampler.deinit,

    .initRenderPass = @import("pass.zig").RenderPass.init,
    .deinitRenderPass = @import("pass.zig").RenderPass.deinit,

    .initFrameBuffer = @import("pass.zig").FrameBuffer.init,
    .deinitFrameBuffer = @import("pass.zig").FrameBuffer.deinit,

    .initDescriptorSetLayout = @import("desc.zig").DescriptorSetLayout.init,
    .deinitDescriptorSetLayout = @import("desc.zig").DescriptorSetLayout.deinit,

    .initPipelineLayout = @import("desc.zig").PipelineLayout.init,
    .deinitPipelineLayout = @import("desc.zig").PipelineLayout.deinit,

    .initDescriptorPool = @import("desc.zig").DescriptorPool.init,
    .allocDescriptorSets = @import("desc.zig").DescriptorPool.alloc,
    .resetDescriptorPool = @import("desc.zig").DescriptorPool.reset,
    .deinitDescriptorPool = @import("desc.zig").DescriptorPool.deinit,

    .writeDescriptorSets = @import("desc.zig").DescriptorSet.write,

    .initPipelinesGraphics = @import("state.zig").Pipeline.initGraphics,
    .initPipelinesCompute = @import("state.zig").Pipeline.initCompute,
    .deinitPipeline = @import("state.zig").Pipeline.deinit,

    .initPipelineCache = @import("state.zig").PipelineCache.init,
    .deinitPipelineCache = @import("state.zig").PipelineCache.deinit,

    .initSurface = @import("dpy.zig").Surface.init,
    .deinitSurface = @import("dpy.zig").Surface.deinit,

    .initSwapChain = @import("dpy.zig").SwapChain.init,
    .deinitSwapChain = @import("dpy.zig").SwapChain.deinit,
};
