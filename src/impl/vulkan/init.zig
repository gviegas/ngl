const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(.@"ngl/impl/vulkan");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const CommandBuffer = @import("cmd.zig").CommandBuffer;
const Fence = @import("sync.zig").Fence;
const Semaphore = @import("sync.zig").Semaphore;

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

    pub inline fn cast(impl: Impl.Instance) *Instance {
        return impl.ptr(Instance);
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
    ) Error!Impl.Instance {
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

        return .{ .val = @intFromPtr(ptr) };
    }

    fn listDevices(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Impl.Instance,
    ) Error![]ngl.Device.Desc {
        const inst = cast(instance);

        var dev_n: u32 = undefined;
        try conv.check(inst.vkEnumeratePhysicalDevices(&dev_n, null));
        if (dev_n == 0) return Error.NotSupported; // TODO: Need a better error for this
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

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, instance: Impl.Instance) void {
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
    queueSubmit: c.PFN_vkQueueSubmit,
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
    createGraphicsPipelines: c.PFN_vkCreateGraphicsPipelines,
    createComputePipelines: c.PFN_vkCreateComputePipelines,
    destroyPipeline: c.PFN_vkDestroyPipeline,
    createPipelineCache: c.PFN_vkCreatePipelineCache,
    destroyPipelineCache: c.PFN_vkDestroyPipelineCache,
    createShaderModule: c.PFN_vkCreateShaderModule,
    destroyShaderModule: c.PFN_vkDestroyShaderModule,

    pub fn cast(impl: Impl.Device) *Device {
        return impl.ptr(Device);
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
        instance: Impl.Instance,
        desc: ngl.Device.Desc,
    ) Error!Impl.Device {
        const inst = Instance.cast(instance);
        const phys_dev: c.VkPhysicalDevice = @ptrCast(@alignCast(
            desc.impl orelse return Error.InvalidArgument,
        ));

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
            .queueSubmit = @ptrCast(try Device.getProc(get, dev, "vkQueueSubmit")),
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
            .createGraphicsPipelines = @ptrCast(try Device.getProc(get, dev, "vkCreateGraphicsPipelines")),
            .createComputePipelines = @ptrCast(try Device.getProc(get, dev, "vkCreateComputePipelines")),
            .destroyPipeline = @ptrCast(try Device.getProc(get, dev, "vkDestroyPipeline")),
            .createPipelineCache = @ptrCast(try Device.getProc(get, dev, "vkCreatePipelineCache")),
            .destroyPipelineCache = @ptrCast(try Device.getProc(get, dev, "vkDestroyPipelineCache")),
            .createShaderModule = @ptrCast(try Device.getProc(get, dev, "vkCreateShaderModule")),
            .destroyShaderModule = @ptrCast(try Device.getProc(get, dev, "vkDestroyShaderModule")),
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
        try conv.check(dev.vkAllocateMemory(&.{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = desc.size,
            .memoryTypeIndex = desc.mem_type_index,
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

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, device: Impl.Device) void {
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

    pub inline fn vkQueueSubmit(
        self: *Device,
        queue: c.VkQueue,
        submit_count: u32,
        submits: ?[*]const c.VkSubmitInfo,
        fence: c.VkFence,
    ) c.VkResult {
        return self.queueSubmit.?(queue, submit_count, submits, fence);
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
};

pub const Queue = struct {
    handle: c.VkQueue,
    family: u32,
    index: u32,

    pub inline fn cast(impl: Impl.Queue) *Queue {
        return impl.ptr(Queue);
    }

    // TODO: Don't allocate on every call
    pub fn submit(
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
        defer if (cmd_buf.len > 1) allocator.free(cmd_bufs);
        defer if (semas.len > 1) allocator.free(semas);
        defer if (stages.len > 1) allocator.free(stages);

        var cmd_bufs_ptr = cmd_bufs.ptr;
        var semas_ptr = semas.ptr;
        var stages_ptr = stages.ptr;

        for (subm_infos, submits) |*info, subm| {
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
                for (semas_ptr, stages_ptr, subm.wait) |*handle, *mask, wait| {
                    handle.* = Semaphore.cast(wait.semaphore.impl).handle;
                    mask.* = conv.toVkPipelineStageFlags(wait.stage_mask);
                }
                semas_ptr += subm.wait.len;
                stages_ptr += subm.wait.len;
            } else {
                info.pWaitSemaphores = null;
                info.pWaitDstStageMask = null;
            }

            if (subm.signal.len > 0) {
                info.pSignalSemaphores = semas_ptr;
                for (semas_ptr, subm.signal) |*handle, signal|
                    // No signal stage mask on vanilla submission
                    handle.* = Semaphore.cast(signal.semaphore.impl).handle;
                semas_ptr += subm.signal.len;
            } else info.pSignalSemaphores = null;
        }

        try conv.check(Device.cast(device).vkQueueSubmit(
            cast(queue).handle,
            @intCast(submits.len), // Note `submits`
            if (submits.len > 0) subm_infos.ptr else null,
            if (fence) |x| Fence.cast(x).handle else null,
        ));
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
        offset: usize,
        size: ?usize,
    ) Error![*]u8 {
        var data: ?*anyopaque = undefined;
        try conv.check(Device.cast(device).vkMapMemory(
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
        offsets: []const usize,
        sizes: ?[]const usize,
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
        try conv.check(callable(dev, @intCast(mapped_ranges.len), mapped_ranges.ptr));
    }

    fn flushMapped(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const usize,
        sizes: ?[]const usize,
    ) Error!void {
        return flushOrInvalidateMapped(.flush, allocator, device, memory, offsets, sizes);
    }

    fn invalidateMapped(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const usize,
        sizes: ?[]const usize,
    ) Error!void {
        return flushOrInvalidateMapped(.invalidate, allocator, device, memory, offsets, sizes);
    }
};

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
    .deinitDevice = Device.deinit,

    .submit = Queue.submit,

    .mapMemory = Memory.map,
    .unmapMemory = Memory.unmap,
    .flushMappedMemory = Memory.flushMapped,
    .invalidateMappedMemory = Memory.invalidateMapped,

    .initCommandPool = @import("cmd.zig").CommandPool.init,
    .allocCommandBuffers = @import("cmd.zig").CommandPool.alloc,
    .resetCommandPool = @import("cmd.zig").CommandPool.reset,
    .freeCommandBuffers = @import("cmd.zig").CommandPool.free,
    .deinitCommandPool = @import("cmd.zig").CommandPool.deinit,

    .initFence = @import("sync.zig").Fence.init,
    .resetFences = @import("sync.zig").Fence.reset,
    .waitFences = @import("sync.zig").Fence.wait,
    .getFenceStatus = @import("sync.zig").Fence.getStatus,
    .deinitFence = @import("sync.zig").Fence.deinit,

    .initSemaphore = @import("sync.zig").Semaphore.init,
    .deinitSemaphore = @import("sync.zig").Semaphore.deinit,

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

    .initPipelinesGraphics = @import("state.zig").Pipeline.initGraphics,
    .initPipelinesCompute = @import("state.zig").Pipeline.initCompute,
    .deinitPipeline = @import("state.zig").Pipeline.deinit,

    .initPipelineCache = @import("state.zig").PipelineCache.init,
    .deinitPipelineCache = @import("state.zig").PipelineCache.deinit,
};
