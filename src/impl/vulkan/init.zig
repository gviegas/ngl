const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");

var libvulkan: ?*anyopaque = null;
var getInstanceProcAddr: c.PFN_vkGetInstanceProcAddr = null;

// NOTE: Procs from any version greater than 1.0 are allowed to be null
// after initialization.

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
// This wrapper can be called regardless of API version.
inline fn vkEnumerateInstanceVersion(version: *u32) c.VkResult {
    if (enumerateInstanceVersion) |fp| return fp(version);
    version.* = c.VK_API_VERSION_1_0;
    return c.VK_SUCCESS;
}

// The returned proc is guaranteed to be non-null.
// Use for global procs only.
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
    createDevice: c.PFN_vkCreateDevice,
    enumerateDeviceExtensionProperties: c.PFN_vkEnumerateDeviceExtensionProperties,

    pub inline fn cast(impl: *Impl.Instance) *Instance {
        return @ptrCast(@alignCast(impl));
    }

    // The returned proc is guaranteed to be non-null.
    pub fn getProc(instance: c.VkInstance, name: [:0]const u8) Error!c.PFN_vkVoidFunction {
        std.debug.assert(getInstanceProcAddr != null);
        return if (getInstanceProcAddr.?(instance, name)) |fp| fp else Error.InitializationFailed;
    }

    fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        desc: ngl.Instance.Desc,
    ) Error!*Impl.Instance {
        std.debug.assert(createInstance != null);
        std.debug.assert(enumerateInstanceLayerProperties != null);
        std.debug.assert(enumerateInstanceExtensionProperties != null);

        // TODO
        _ = desc;

        // TODO: App info; extensions
        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = null,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = 0,
            .ppEnabledExtensionNames = null,
        };
        var inst: c.VkInstance = undefined;
        try conv.check(vkCreateInstance(&create_info, null, &inst));

        // TODO: Destroy inst on failure

        var ptr = try allocator.create(Instance);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .handle = inst,
            .destroyInstance = @ptrCast(try Instance.getProc(inst, "vkDestroyInstance")),
            .enumeratePhysicalDevices = @ptrCast(try Instance.getProc(inst, "vkEnumeratePhysicalDevices")),
            .getPhysicalDeviceProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceProperties")),
            .getPhysicalDeviceQueueFamilyProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceQueueFamilyProperties")),
            .createDevice = @ptrCast(try Instance.getProc(inst, "vkCreateDevice")),
            .enumerateDeviceExtensionProperties = @ptrCast(try Instance.getProc(inst, "vkEnumerateDeviceExtensionProperties")),
        };

        return @ptrCast(ptr);
    }

    fn listDevices(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        instance: *Impl.Instance,
    ) Error![]ngl.Device.Desc {
        const inst = Instance.cast(instance);

        var dev_n: u32 = undefined;
        try conv.check(inst.vkEnumeratePhysicalDevices(&dev_n, null));
        if (dev_n == 0) return Error.NotSupported; // TODO: Need better error
        var devs = try allocator.alloc(c.VkPhysicalDevice, dev_n);
        defer allocator.free(devs);
        try conv.check(inst.vkEnumeratePhysicalDevices(&dev_n, devs.ptr));

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
                        .impl = @ptrFromInt(fam), // XXX
                    };
                    break;
                }
            } else return Error.InitializationFailed; // TODO: This should never happen

            // TODO: Limits; features; extensions

            desc.* = .{
                .type = switch (prop.deviceType) {
                    c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => .discrete_gpu,
                    c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => .integrated_gpu,
                    c.VK_PHYSICAL_DEVICE_TYPE_CPU => .cpu,
                    else => .other,
                },
                .queues = .{ main_queue, null, null, null },
                .impl = dev,
            };
        }

        return descs;
    }

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, instance: *Impl.Instance) void {
        const inst = Instance.cast(instance);
        // TODO: Need to gate destruction until all devices
        // and instance-level objects have been destroyed
        inst.vkDestroyInstance(null);
        allocator.destroy(inst);
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
};

pub const Device = struct {
    handle: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    queues: [ngl.Queue.max]Queue,
    queue_n: u8,

    getDeviceProcAddr: c.PFN_vkGetDeviceProcAddr,

    // v1.0
    destroyDevice: c.PFN_vkDestroyDevice,
    getDeviceQueue: c.PFN_vkGetDeviceQueue,

    pub fn cast(impl: *Impl.Device) *Device {
        return @ptrCast(@alignCast(impl));
    }

    // The returned proc is guaranteed to be non-null.
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
        instance: *Impl.Instance,
        desc: ngl.Device.Desc,
    ) Error!*Impl.Device {
        const inst = Instance.cast(instance);
        const phys_dev: c.VkPhysicalDevice = @ptrCast(desc.impl orelse return Error.InvalidArgument);

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
                    .queueFamilyIndex = @intCast(@intFromPtr(q.impl)), // XXX
                    .queueCount = 1,
                    .pQueuePriorities = &queue_prios[n],
                };
                n += 1;
            }
            if (n == 0) return Error.InvalidArgument;
            break :blk n;
        };

        var create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = queue_n,
            .pQueueCreateInfos = &queue_infos,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = 0, // TODO
            .ppEnabledExtensionNames = null, // TODO
            .pEnabledFeatures = null, // TODO
        };
        var dev: c.VkDevice = undefined;
        try conv.check(inst.vkCreateDevice(phys_dev, &create_info, null, &dev));

        // TODO: Destroy dev on failure

        const get: c.PFN_vkGetDeviceProcAddr = @ptrCast(try Instance.getProc(
            inst.handle,
            "vkGetDeviceProcAddr",
        ));

        var ptr = try allocator.create(Device);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .handle = dev,
            .physical_device = phys_dev,
            .queues = undefined,
            .queue_n = 0,
            .getDeviceProcAddr = get,
            .destroyDevice = @ptrCast(try Device.getProc(get, dev, "vkDestroyDevice")),
            .getDeviceQueue = @ptrCast(try Device.getProc(get, dev, "vkGetDeviceQueue")),
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

        return @ptrCast(ptr);
    }

    fn getQueues(
        _: *anyopaque,
        allocation: *[ngl.Queue.max]Impl.Queue,
        device: *Impl.Device,
    ) []Impl.Queue {
        const dev = Device.cast(device);
        for (0..dev.queue_n) |i| allocation[i] = .{ device, i };
        return allocation[0..dev.queue_n];
    }

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, device: *Impl.Device) void {
        const dev = Device.cast(device);
        // TODO: Need to gate destruction until all
        // device-level objects have been destroyed
        dev.vkDestroyDevice(null);
        allocator.destroy(dev);
    }

    // Wrappers --------------------------------------------

    pub inline fn vkDestroyDevice(self: *Device, vk_allocator: ?*c.VkAllocationCallbacks) void {
        self.destroyDevice.?(self.handle, vk_allocator);
    }

    pub inline fn vkGetDeviceQueue(
        self: *Device,
        queue_family: u32,
        queue_index: u32,
        queue: *c.VkQueue,
    ) void {
        self.getDeviceQueue.?(self.handle, queue_family, queue_index, queue);
    }
};

pub const Queue = struct {
    handle: c.VkQueue,
    family: u32,
    index: u32,
};

const vtable = Impl.VTable{
    .deinit = deinit,

    .initInstance = Instance.init,
    .listDevices = Instance.listDevices,
    .deinitInstance = Instance.deinit,

    .initDevice = Device.init,
    .getQueues = Device.getQueues,
    .deinitDevice = Device.deinit,
};
