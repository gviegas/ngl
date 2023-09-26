const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(.@"ngl/impl/vulkan");

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
    getPhysicalDeviceMemoryProperties: c.PFN_vkGetPhysicalDeviceMemoryProperties,
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
            .getPhysicalDeviceMemoryProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceMemoryProperties")),
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
        const inst = cast(instance);

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
        const inst = cast(instance);
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

    pub inline fn vkGetPhysicalDeviceMemoryProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.getPhysicalDeviceMemoryProperties.?(device, properties);
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
    instance: *Instance,
    physical_device: c.VkPhysicalDevice,
    handle: c.VkDevice,
    queues: [ngl.Queue.max]Queue,
    queue_n: u8,

    getDeviceProcAddr: c.PFN_vkGetDeviceProcAddr,

    // v1.0
    destroyDevice: c.PFN_vkDestroyDevice,
    getDeviceQueue: c.PFN_vkGetDeviceQueue,
    createCommandPool: c.PFN_vkCreateCommandPool,
    destroyCommandPool: c.PFN_vkDestroyCommandPool,
    allocateCommandBuffers: c.PFN_vkAllocateCommandBuffers,
    freeCommandBuffers: c.PFN_vkFreeCommandBuffers,
    createFence: c.PFN_vkCreateFence,
    destroyFence: c.PFN_vkDestroyFence,
    createSemaphore: c.PFN_vkCreateSemaphore,
    destroySemaphore: c.PFN_vkDestroySemaphore,
    createBuffer: c.PFN_vkCreateBuffer,
    destroyBuffer: c.PFN_vkDestroyBuffer,
    createBufferView: c.PFN_vkCreateBufferView,
    destroyBufferView: c.PFN_vkDestroyBufferView,
    createImage: c.PFN_vkCreateImage,
    destroyImage: c.PFN_vkDestroyImage,
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
            .instance = inst,
            .physical_device = phys_dev,
            .handle = dev,
            .queues = undefined,
            .queue_n = 0,
            .getDeviceProcAddr = get,
            .destroyDevice = @ptrCast(try Device.getProc(get, dev, "vkDestroyDevice")),
            .getDeviceQueue = @ptrCast(try Device.getProc(get, dev, "vkGetDeviceQueue")),
            .createCommandPool = @ptrCast(try Device.getProc(get, dev, "vkCreateCommandPool")),
            .destroyCommandPool = @ptrCast(try Device.getProc(get, dev, "vkDestroyCommandPool")),
            .allocateCommandBuffers = @ptrCast(try Device.getProc(get, dev, "vkAllocateCommandBuffers")),
            .freeCommandBuffers = @ptrCast(try Device.getProc(get, dev, "vkFreeCommandBuffers")),
            .createFence = @ptrCast(try Device.getProc(get, dev, "vkCreateFence")),
            .destroyFence = @ptrCast(try Device.getProc(get, dev, "vkDestroyFence")),
            .createSemaphore = @ptrCast(try Device.getProc(get, dev, "vkCreateSemaphore")),
            .destroySemaphore = @ptrCast(try Device.getProc(get, dev, "vkDestroySemaphore")),
            .createBuffer = @ptrCast(try Device.getProc(get, dev, "vkCreateBuffer")),
            .destroyBuffer = @ptrCast(try Device.getProc(get, dev, "vkDestroyBuffer")),
            .createBufferView = @ptrCast(try Device.getProc(get, dev, "vkCreateBufferView")),
            .destroyBufferView = @ptrCast(try Device.getProc(get, dev, "vkDestroyBufferView")),
            .createImage = @ptrCast(try Device.getProc(get, dev, "vkCreateImage")),
            .destroyImage = @ptrCast(try Device.getProc(get, dev, "vkDestroyImage")),
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
        allocation: *[ngl.Queue.max]*Impl.Queue,
        device: *Impl.Device,
    ) []*Impl.Queue {
        const dev = cast(device);
        for (0..dev.queue_n) |i| allocation[i] = @ptrCast(&dev.queues[i]);
        return allocation[0..dev.queue_n];
    }

    fn getMemoryTypes(
        _: *anyopaque,
        allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
        device: *Impl.Device,
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
            const heap: u8 = @intCast(props.memoryTypes[i].heapIndex);
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

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, device: *Impl.Device) void {
        const dev = cast(device);
        // TODO: Need to gate destruction until all
        // device-level objects have been destroyed
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

    pub inline fn vkGetDeviceQueue(
        self: *Device,
        queue_family: u32,
        queue_index: u32,
        queue: *c.VkQueue,
    ) void {
        self.getDeviceQueue.?(self.handle, queue_family, queue_index, queue);
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
};

pub const Queue = struct {
    handle: c.VkQueue,
    family: u32,
    index: u32,

    pub inline fn cast(impl: *Impl.Queue) *Queue {
        return @ptrCast(@alignCast(impl));
    }
};

// TODO
pub const Memory = struct {};

const vtable = Impl.VTable{
    .deinit = deinit,

    .initInstance = Instance.init,
    .listDevices = Instance.listDevices,
    .deinitInstance = Instance.deinit,

    .initDevice = Device.init,
    .getQueues = Device.getQueues,
    .getMemoryTypes = Device.getMemoryTypes,
    .deinitDevice = Device.deinit,

    .initCommandPool = @import("cmd.zig").CommandPool.init,
    .allocCommandBuffers = @import("cmd.zig").CommandPool.alloc,
    .freeCommandBuffers = @import("cmd.zig").CommandPool.free,
    .deinitCommandPool = @import("cmd.zig").CommandPool.deinit,

    .initFence = @import("sync.zig").Fence.init,
    .deinitFence = @import("sync.zig").Fence.deinit,

    .initSemaphore = @import("sync.zig").Semaphore.init,
    .deinitSemaphore = @import("sync.zig").Semaphore.deinit,

    .initBuffer = @import("res.zig").Buffer.init,
    .deinitBuffer = @import("res.zig").Buffer.deinit,

    .initBufferView = @import("res.zig").BufferView.init,
    .deinitBufferView = @import("res.zig").BufferView.deinit,

    .initImage = @import("res.zig").Image.init,
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
};
