const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(.@"ngl/impl/vulkan");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const CommandBuffer = @import("cmd.zig").CommandBuffer;
const Fence = @import("sync.zig").Fence;
const Semaphore = @import("sync.zig").Semaphore;
const SwapChain = @import("dpy.zig").SwapChain;

var libvulkan: ?*anyopaque = null;
var getInstanceProcAddr: c.PFN_vkGetInstanceProcAddr = null;

// NOTE: Procs from any version greater than 1.0, as well as extensions,
// are allowed to be null after initialization.

// v1.0.
var createInstance: c.PFN_vkCreateInstance = null;
inline fn vkCreateInstance(
    create_info: *const c.VkInstanceCreateInfo,
    vk_allocator: ?*const c.VkAllocationCallbacks,
    instance: *c.VkInstance,
) c.VkResult {
    return createInstance.?(create_info, vk_allocator, instance);
}

// v1.0.
var enumerateInstanceLayerProperties: c.PFN_vkEnumerateInstanceLayerProperties = null;
inline fn vkEnumerateInstanceLayerProperties(
    property_count: *u32,
    properties: ?[*]c.VkLayerProperties,
) c.VkResult {
    return enumerateInstanceLayerProperties.?(property_count, properties);
}

// v1.0.
var enumerateInstanceExtensionProperties: c.PFN_vkEnumerateInstanceExtensionProperties = null;
inline fn vkEnumerateInstanceExtensionProperties(
    layer_name: ?[*:0]const u8,
    property_count: *u32,
    properties: ?[*]c.VkExtensionProperties,
) c.VkResult {
    return enumerateInstanceExtensionProperties.?(layer_name, property_count, properties);
}

// v1.1.
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

var global_instance: ?Instance = null;

/// The minimum version we can support.
pub const supported_version = c.VK_API_VERSION_1_0;
/// The version we prefer to use.
pub const preferred_version = c.VK_API_VERSION_1_3;

pub fn init(allocator: std.mem.Allocator) Error!Impl {
    const sym = "vkGetInstanceProcAddr";

    const setCommon = struct {
        fn set(alloc: std.mem.Allocator) Error!void {
            createInstance = @ptrCast(try getProc("vkCreateInstance"));
            enumerateInstanceLayerProperties = @ptrCast(try getProc("vkEnumerateInstanceLayerProperties"));
            enumerateInstanceExtensionProperties = @ptrCast(try getProc("vkEnumerateInstanceExtensionProperties"));
            enumerateInstanceVersion = @ptrCast(getProc("vkEnumerateInstanceVersion") catch null);
            global_instance = try Instance.init(alloc);
        }
    }.set;

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
        try setCommon(allocator);
    }

    if (builtin.os.tag == .windows) {
        // TODO
        @compileError("Not yet implemented");
    }

    return .{
        .ptr = undefined,
        .vtable = &vtable,
    };
}

fn deinit(_: *anyopaque, _: std.mem.Allocator) void {
    if (global_instance) |*inst| {
        inst.deinit();
        global_instance = null;
    }
    if (libvulkan) |handle| {
        if (builtin.os.tag != .windows) {
            _ = std.c.dlclose(handle);
        } else {
            // TODO
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

const Extension = struct {
    names: std.AutoHashMapUnmanaged(Name, void) = .{},
    allocator: std.mem.Allocator,

    const Name = [c.VK_MAX_EXTENSION_NAME_SIZE]u8;

    fn normalizeName(name: *Name) void {
        if (name[0] == 0) {
            log.warn("Empty extension name", .{});
            return;
        }
        // We'll compare fixed-size arrays, not NTSs.
        var i = name.len - 1;
        while (i > 0 and name[i] != 0) : (i -= 1)
            name[i] = 0;
    }

    fn init(allocator: std.mem.Allocator) Extension {
        return .{ .allocator = allocator };
    }

    fn putAllInstance(self: *Extension, layer: [:0]const u8) !void {
        var n: u32 = undefined;
        try check(vkEnumerateInstanceExtensionProperties(layer, &n, null));
        if (n == 0) return;
        const props = try self.allocator.alloc(c.VkExtensionProperties, n);
        defer self.allocator.free(props);
        try check(vkEnumerateInstanceExtensionProperties(layer, &n, props.ptr));

        for (props) |*prop| {
            normalizeName(&prop.extensionName);
            try self.names.put(self.allocator, prop.extensionName, {});
        }
    }

    fn putAllDevice(self: *Extension, device: c.VkPhysicalDevice) !void {
        const inst = Instance.get();

        var n: u32 = undefined;
        try check(inst.vkEnumerateDeviceExtensionProperties(device, null, &n, null));
        if (n == 0) return;
        const props = try self.allocator.alloc(c.VkExtensionProperties, n);
        defer self.allocator.free(props);
        try check(inst.vkEnumerateDeviceExtensionProperties(device, null, &n, props.ptr));

        for (props) |*prop| {
            normalizeName(&prop.extensionName);
            try self.names.put(self.allocator, prop.extensionName, {});
        }
    }

    /// Call `putAll*` before this method as appropriate.
    // TODO: Consider using a custom context to speed up comparisons.
    fn contains(self: Extension, name: []const u8) bool {
        var nm: Name = undefined;
        if (name.len > nm.len) return false;
        @memcpy(nm[0..name.len], name);
        @memset(nm[name.len..nm.len], 0);
        return self.names.contains(nm);
    }

    fn clearRetainingCapacity(self: *Extension) void {
        self.names.clearRetainingCapacity();
    }

    fn deinit(self: *Extension) void {
        self.names.deinit(self.allocator);
        self.* = undefined;
    }
};

const Feature = struct {
    options: Options,
    features_2: c.VkPhysicalDeviceFeatures2,
    @"1.1": c.VkPhysicalDeviceVulkan11Features,
    @"1.2": c.VkPhysicalDeviceVulkan12Features,
    @"1.3": c.VkPhysicalDeviceVulkan13Features,

    const Options = packed struct {
        @"1.1": bool,
        @"1.2": bool,
        @"1.3": bool,
    };

    /// The caller must ensure that `options` is valid for the
    /// instance/device versions.
    fn get(device: c.VkPhysicalDevice, options: Options) Feature {
        const inst = Instance.get();

        var self = Feature{
            .options = options,
            .features_2 = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                .pNext = null,
                .features = undefined,
            },
            .@"1.1" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
                .pNext = null,
            },
            .@"1.2" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
                .pNext = null,
            },
            .@"1.3" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
                .pNext = null,
            },
        };

        if (options.@"1.1") {
            self.@"1.1".pNext = self.features_2.pNext;
            self.features_2.pNext = &self.@"1.1";
        }
        if (options.@"1.2") {
            self.@"1.2".pNext = self.features_2.pNext;
            self.features_2.pNext = &self.@"1.2";
        }
        if (options.@"1.3") {
            self.@"1.3".pNext = self.features_2.pNext;
            self.features_2.pNext = &self.@"1.3";
        }

        if (self.features_2.pNext != null) {
            if (inst.getPhysicalDeviceFeatures2 == null) @panic("Invalid call to Feature.get");
            inst.vkGetPhysicalDeviceFeatures2(device, &self.features_2);
        } else inst.vkGetPhysicalDeviceFeatures(device, &self.features_2.features);

        return self;
    }

    /// Gets all core features up to `version`, inclusive.
    // TODO: Make this aware of available extensions (or maybe add
    // a separate method for such).
    fn getVersion(device: c.VkPhysicalDevice, version: u32) Feature {
        const options = Options{
            .@"1.1" = version >= c.VK_API_VERSION_1_2, // See below.
            .@"1.2" = version >= c.VK_API_VERSION_1_2,
            .@"1.3" = version >= c.VK_API_VERSION_1_3,
        };

        if (!options.@"1.1" and version >= c.VK_API_VERSION_1_1) {
            // TODO: VkPhysicalDeviceVulkan11Features requires v1.2.
            log.warn("TODO: Handle Feature.getVersion for v1.1", .{});
        }

        return get(device, options);
    }

    /// This method will disable features that aren't needed,
    /// while leaving desired features unchanged.
    // TODO: Expose/enable more features.
    fn set(self: *Feature) void {
        const @"1.0" = &self.features_2.features;
        @"1.0".robustBufferAccess = c.VK_FALSE;
        @"1.0".geometryShader = c.VK_FALSE;
        @"1.0".tessellationShader = c.VK_FALSE;
        @"1.0".sampleRateShading = c.VK_FALSE;
        @"1.0".dualSrcBlend = c.VK_FALSE;
        @"1.0".logicOp = c.VK_FALSE;
        @"1.0".depthBounds = c.VK_FALSE;
        @"1.0".wideLines = c.VK_FALSE;
        @"1.0".largePoints = c.VK_FALSE;
        @"1.0".pipelineStatisticsQuery = c.VK_FALSE;
        @"1.0".shaderTessellationAndGeometryPointSize = c.VK_FALSE;
        @"1.0".shaderImageGatherExtended = c.VK_FALSE;
        @"1.0".shaderStorageImageExtendedFormats = c.VK_FALSE;
        @"1.0".shaderStorageImageReadWithoutFormat = c.VK_FALSE;
        @"1.0".shaderStorageImageWriteWithoutFormat = c.VK_FALSE;
        @"1.0".shaderUniformBufferArrayDynamicIndexing = c.VK_FALSE;
        @"1.0".shaderSampledImageArrayDynamicIndexing = c.VK_FALSE;
        @"1.0".shaderStorageBufferArrayDynamicIndexing = c.VK_FALSE;
        @"1.0".shaderStorageImageArrayDynamicIndexing = c.VK_FALSE;
        @"1.0".shaderClipDistance = c.VK_FALSE;
        @"1.0".shaderCullDistance = c.VK_FALSE;
        @"1.0".shaderFloat64 = c.VK_FALSE;
        @"1.0".shaderInt64 = c.VK_FALSE;
        @"1.0".shaderInt16 = c.VK_FALSE;
        @"1.0".shaderResourceResidency = c.VK_FALSE;
        @"1.0".shaderResourceMinLod = c.VK_FALSE;
        @"1.0".sparseBinding = c.VK_FALSE;
        @"1.0".sparseResidencyBuffer = c.VK_FALSE;
        @"1.0".sparseResidencyImage2D = c.VK_FALSE;
        @"1.0".sparseResidencyImage3D = c.VK_FALSE;
        @"1.0".sparseResidency2Samples = c.VK_FALSE;
        @"1.0".sparseResidency4Samples = c.VK_FALSE;
        @"1.0".sparseResidency8Samples = c.VK_FALSE;
        @"1.0".sparseResidency16Samples = c.VK_FALSE;
        @"1.0".sparseResidencyAliased = c.VK_FALSE;
        @"1.0".variableMultisampleRate = c.VK_FALSE;

        if (self.options.@"1.1") {
            const @"1.1" = &self.@"1.1";
            @"1.1".storageBuffer16BitAccess = c.VK_FALSE;
            @"1.1".uniformAndStorageBuffer16BitAccess = c.VK_FALSE;
            @"1.1".storagePushConstant16 = c.VK_FALSE;
            @"1.1".storageInputOutput16 = c.VK_FALSE;
            @"1.1".multiview = c.VK_FALSE;
            @"1.1".multiviewGeometryShader = c.VK_FALSE;
            @"1.1".multiviewTessellationShader = c.VK_FALSE;
            @"1.1".variablePointersStorageBuffer = c.VK_FALSE;
            @"1.1".variablePointers = c.VK_FALSE;
            @"1.1".protectedMemory = c.VK_FALSE;
            @"1.1".samplerYcbcrConversion = c.VK_FALSE;
            @"1.1".shaderDrawParameters = c.VK_FALSE;
        }

        if (self.options.@"1.2") {
            const @"1.2" = &self.@"1.2";
            @"1.2".drawIndirectCount = c.VK_FALSE;
            @"1.2".storageBuffer8BitAccess = c.VK_FALSE;
            @"1.2".uniformAndStorageBuffer8BitAccess = c.VK_FALSE;
            @"1.2".storagePushConstant8 = c.VK_FALSE;
            @"1.2".shaderBufferInt64Atomics = c.VK_FALSE;
            @"1.2".shaderSharedInt64Atomics = c.VK_FALSE;
            @"1.2".shaderFloat16 = c.VK_FALSE;
            @"1.2".shaderInt8 = c.VK_FALSE;
            @"1.2".descriptorIndexing = c.VK_FALSE;
            @"1.2".shaderInputAttachmentArrayDynamicIndexing = c.VK_FALSE;
            @"1.2".shaderUniformTexelBufferArrayDynamicIndexing = c.VK_FALSE;
            @"1.2".shaderStorageTexelBufferArrayDynamicIndexing = c.VK_FALSE;
            @"1.2".shaderUniformBufferArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderSampledImageArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderStorageBufferArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderStorageImageArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderInputAttachmentArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderUniformTexelBufferArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".shaderStorageTexelBufferArrayNonUniformIndexing = c.VK_FALSE;
            @"1.2".descriptorBindingUniformBufferUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingSampledImageUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingStorageImageUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingStorageBufferUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingUniformTexelBufferUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingStorageTexelBufferUpdateAfterBind = c.VK_FALSE;
            @"1.2".descriptorBindingUpdateUnusedWhilePending = c.VK_FALSE;
            @"1.2".descriptorBindingPartiallyBound = c.VK_FALSE;
            @"1.2".descriptorBindingVariableDescriptorCount = c.VK_FALSE;
            @"1.2".runtimeDescriptorArray = c.VK_FALSE;
            @"1.2".samplerFilterMinmax = c.VK_FALSE;
            @"1.2".scalarBlockLayout = c.VK_FALSE;
            @"1.2".imagelessFramebuffer = c.VK_FALSE;
            @"1.2".uniformBufferStandardLayout = c.VK_FALSE;
            @"1.2".shaderSubgroupExtendedTypes = c.VK_FALSE;
            @"1.2".separateDepthStencilLayouts = c.VK_FALSE;
            @"1.2".hostQueryReset = c.VK_FALSE;
            @"1.2".timelineSemaphore = c.VK_FALSE;
            @"1.2".bufferDeviceAddress = c.VK_FALSE;
            @"1.2".bufferDeviceAddressCaptureReplay = c.VK_FALSE;
            @"1.2".bufferDeviceAddressMultiDevice = c.VK_FALSE;
            @"1.2".vulkanMemoryModel = c.VK_FALSE;
            @"1.2".vulkanMemoryModelDeviceScope = c.VK_FALSE;
            @"1.2".vulkanMemoryModelAvailabilityVisibilityChains = c.VK_FALSE;
            @"1.2".shaderOutputViewportIndex = c.VK_FALSE;
            @"1.2".shaderOutputLayer = c.VK_FALSE;
            @"1.2".subgroupBroadcastDynamicId = c.VK_FALSE;
        }

        if (self.options.@"1.3") {
            const @"1.3" = &self.@"1.3";
            @"1.3".robustImageAccess = c.VK_FALSE;
            @"1.3".inlineUniformBlock = c.VK_FALSE;
            @"1.3".descriptorBindingInlineUniformBlockUpdateAfterBind = c.VK_FALSE;
            @"1.3".pipelineCreationCacheControl = c.VK_FALSE;
            @"1.3".privateData = c.VK_FALSE;
            @"1.3".shaderDemoteToHelperInvocation = c.VK_FALSE;
            @"1.3".shaderTerminateInvocation = c.VK_FALSE;
            @"1.3".subgroupSizeControl = c.VK_FALSE;
            @"1.3".computeFullSubgroups = c.VK_FALSE;
            @"1.3".textureCompressionASTC_HDR = c.VK_FALSE;
            @"1.3".shaderZeroInitializeWorkgroupMemory = c.VK_FALSE;
            @"1.3".shaderIntegerDotProduct = c.VK_FALSE;
        }
    }

    /// Updates `create_info` such that it references the data in `self`.
    /// Note that this uses self-references.
    fn ref(self: *Feature, create_info: *c.VkDeviceCreateInfo) void {
        if (self.features_2.pNext != null) {
            self.features_2.pNext = @constCast(create_info.pNext);
            if (self.options.@"1.1") {
                self.@"1.1".pNext = self.features_2.pNext;
                self.features_2.pNext = &self.@"1.1";
            }
            if (self.options.@"1.2") {
                self.@"1.2".pNext = self.features_2.pNext;
                self.features_2.pNext = &self.@"1.2";
            }
            if (self.options.@"1.3") {
                self.@"1.3".pNext = self.features_2.pNext;
                self.features_2.pNext = &self.@"1.3";
            }
            create_info.pNext = &self.features_2;
            create_info.pEnabledFeatures = null;
        } else create_info.pEnabledFeatures = &self.features_2.features;
    }
};

const Property = struct {
    options: Options,
    properties_2: c.VkPhysicalDeviceProperties2,
    @"1.1": c.VkPhysicalDeviceVulkan11Properties,
    @"1.2": c.VkPhysicalDeviceVulkan12Properties,
    @"1.3": c.VkPhysicalDeviceVulkan13Properties,

    const Options = packed struct {
        @"1.1": bool,
        @"1.2": bool,
        @"1.3": bool,
    };

    /// The caller must ensure that `options` is valid for the
    /// instance/device versions.
    fn get(device: c.VkPhysicalDevice, options: Options) Property {
        const inst = Instance.get();

        var self = Property{
            .options = options,
            .properties_2 = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
                .pNext = null,
                .properties = undefined,
            },
            .@"1.1" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES,
                .pNext = null,
            },
            .@"1.2" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES,
                .pNext = null,
            },
            .@"1.3" = .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES,
                .pNext = null,
            },
        };

        if (options.@"1.1") {
            self.@"1.1".pNext = self.properties_2.pNext;
            self.properties_2.pNext = &self.@"1.1";
        }
        if (options.@"1.2") {
            self.@"1.2".pNext = self.properties_2.pNext;
            self.properties_2.pNext = &self.@"1.2";
        }
        if (options.@"1.3") {
            self.@"1.3".pNext = self.properties_2.pNext;
            self.properties_2.pNext = &self.@"1.3";
        }

        if (self.properties_2.pNext != null) {
            if (inst.getPhysicalDeviceProperties2 == null) @panic("Invalid call to Property.get");
            inst.vkGetPhysicalDeviceProperties2(device, &self.properties_2);
        } else inst.vkGetPhysicalDeviceProperties(device, &self.properties_2.properties);

        return self;
    }

    /// Gets all core properties up to `version`, inclusive.
    // TODO: Make this aware of available extensions (or maybe add
    // a separate method for such).
    fn getVersion(device: c.VkPhysicalDevice, version: u32) Property {
        const options = Options{
            .@"1.1" = version >= c.VK_API_VERSION_1_2, // See below.
            .@"1.2" = version >= c.VK_API_VERSION_1_2,
            .@"1.3" = version >= c.VK_API_VERSION_1_3,
        };

        if (!options.@"1.1" and version >= c.VK_API_VERSION_1_1) {
            // TODO: VkPhysicalDeviceVulkan11Properties requires v1.2.
            log.warn("TODO: Handle Property.getVersion for v1.1", .{});
        }

        return get(device, options);
    }
};

pub const Instance = struct {
    handle: c.VkInstance,
    version: u32,

    // v1.0.
    destroyInstance: c.PFN_vkDestroyInstance,
    enumeratePhysicalDevices: c.PFN_vkEnumeratePhysicalDevices,
    getPhysicalDeviceProperties: c.PFN_vkGetPhysicalDeviceProperties,
    getPhysicalDeviceQueueFamilyProperties: c.PFN_vkGetPhysicalDeviceQueueFamilyProperties,
    getPhysicalDeviceMemoryProperties: c.PFN_vkGetPhysicalDeviceMemoryProperties,
    getPhysicalDeviceFormatProperties: c.PFN_vkGetPhysicalDeviceFormatProperties,
    getPhysicalDeviceImageFormatProperties: c.PFN_vkGetPhysicalDeviceImageFormatProperties,
    getPhysicalDeviceFeatures: c.PFN_vkGetPhysicalDeviceFeatures,
    createDevice: c.PFN_vkCreateDevice,
    enumerateDeviceExtensionProperties: c.PFN_vkEnumerateDeviceExtensionProperties,
    // v1.1.
    getPhysicalDeviceProperties2: c.PFN_vkGetPhysicalDeviceProperties2,
    getPhysicalDeviceFeatures2: c.PFN_vkGetPhysicalDeviceFeatures2,
    // VK_KHR_surface.
    destroySurface: c.PFN_vkDestroySurfaceKHR,
    getPhysicalDeviceSurfaceSupport: c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR,
    getPhysicalDeviceSurfaceCapabilities: c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR,
    getPhysicalDeviceSurfaceFormats: c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR,
    getPhysicalDeviceSurfacePresentModes: c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR,
    // VK_KHR_android_surface.
    createAndroidSurface: if (builtin.target.isAndroid())
        c.PFN_vkCreateAndroidSurfaceKHR
    else
        void,
    // VK_KHR_wayland_surface.
    createWaylandSurface: if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c.PFN_vkCreateWaylandSurfaceKHR
    else
        void,
    // VK_KHR_win32_surface.
    createWin32Surface: if (builtin.os.tag == .windows)
        c.PFN_vkCreateWin32SurfaceKHR
    else
        void,
    // VK_KHR_xcb_surface.
    createXcbSurface: if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c.PFN_vkCreateXcbSurfaceKHR
    else
        void,

    /// Only valid after global `init` succeeds.
    pub inline fn get() *Instance {
        return &global_instance.?;
    }

    /// The returned proc is guaranteed to be non-null.
    pub fn getProc(instance: c.VkInstance, name: [:0]const u8) Error!c.PFN_vkVoidFunction {
        std.debug.assert(getInstanceProcAddr != null);
        return if (getInstanceProcAddr.?(instance, name)) |fp| fp else Error.InitializationFailed;
    }

    fn init(allocator: std.mem.Allocator) Error!Instance {
        if (global_instance) |_| @panic("Instance exists");

        var ext = Extension.init(allocator);
        defer ext.deinit();
        try ext.putAllInstance("");
        var ext_names = std.ArrayList([*:0]const u8).init(allocator);
        defer ext_names.deinit();

        // TODO: Provide a way to disable presentation.
        const presentation = true;

        if (presentation) {
            const surface_ext = [1][:0]const u8{"VK_KHR_surface"};
            const platform_exts = switch (builtin.os.tag) {
                .linux => if (builtin.target.isAndroid())
                    [1][:0]const u8{"VK_KHR_android_surface"}
                else
                    [2][:0]const u8{ "VK_KHR_wayland_surface", "VK_KHR_xcb_surface" },
                .windows => [1][:0]const u8{"VK_KHR_win32_surface"},
                else => @compileError("OS not supported"),
            };
            // TODO: Consider succeeding if at least one of the
            // surface extensions is available.
            for (surface_ext ++ platform_exts) |x| {
                if (ext.contains(x)) {
                    try ext_names.append(x);
                } else return Error.NotSupported;
            }
        }

        var ver: u32 = undefined;
        if (vkEnumerateInstanceVersion(&ver) != c.VK_SUCCESS)
            ver = c.VK_API_VERSION_1_0;
        // An 1.0 instance won't support devices with different versions,
        // so don't bother continuing if we need anything higher than that.
        if (ver < c.VK_VERSION_1_1 and supported_version >= c.VK_VERSION_1_1)
            return Error.NotSupported;

        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &.{
                .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pNext = null,
                .pApplicationName = ngl.options.app_name,
                .applicationVersion = ngl.options.app_version orelse 0,
                .pEngineName = ngl.options.engine_name,
                .engineVersion = ngl.options.engine_version orelse 0,
                .apiVersion = if (ver >= c.VK_API_VERSION_1_1)
                    preferred_version
                else
                    c.VK_API_VERSION_1_0,
            },
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

        return .{
            .handle = inst,
            .version = ver,

            .destroyInstance = @ptrCast(try Instance.getProc(inst, "vkDestroyInstance")),
            .enumeratePhysicalDevices = @ptrCast(try Instance.getProc(inst, "vkEnumeratePhysicalDevices")),
            .getPhysicalDeviceProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceProperties")),
            .getPhysicalDeviceQueueFamilyProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceQueueFamilyProperties")),
            .getPhysicalDeviceMemoryProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceMemoryProperties")),
            .getPhysicalDeviceFormatProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceFormatProperties")),
            .getPhysicalDeviceImageFormatProperties = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceImageFormatProperties")),
            .getPhysicalDeviceFeatures = @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceFeatures")),
            .createDevice = @ptrCast(try Instance.getProc(inst, "vkCreateDevice")),
            .enumerateDeviceExtensionProperties = @ptrCast(try Instance.getProc(inst, "vkEnumerateDeviceExtensionProperties")),

            .getPhysicalDeviceProperties2 = if (ver >= c.VK_API_VERSION_1_1)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceProperties2"))
            else
                null,
            .getPhysicalDeviceFeatures2 = if (ver >= c.VK_API_VERSION_1_1)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceFeatures2"))
            else
                null,

            .destroySurface = if (presentation)
                @ptrCast(try Instance.getProc(inst, "vkDestroySurfaceKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceSupport = if (presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceSupportKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceCapabilities = if (presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))
            else
                null,
            .getPhysicalDeviceSurfaceFormats = if (presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfaceFormatsKHR"))
            else
                null,
            .getPhysicalDeviceSurfacePresentModes = if (presentation)
                @ptrCast(try Instance.getProc(inst, "vkGetPhysicalDeviceSurfacePresentModesKHR"))
            else
                null,

            .createAndroidSurface = if (builtin.target.isAndroid())
                if (presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateAndroidSurfaceKHR"))
                else
                    null
            else {},

            .createWaylandSurface = if (builtin.os.tag == .linux and !builtin.target.isAndroid())
                if (presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateWaylandSurfaceKHR"))
                else
                    null
            else {},

            .createWin32Surface = if (builtin.os.tag == .windows)
                if (presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateWin32SurfaceKHR"))
                else
                    null
            else {},

            .createXcbSurface = if (builtin.os.tag == .linux and !builtin.target.isAndroid())
                if (presentation)
                    @ptrCast(try Instance.getProc(inst, "vkCreateXcbSurfaceKHR"))
                else
                    null
            else {},
        };
    }

    fn deinit(self: *Instance) void {
        // NOTE: This assumes that all instance-level objects
        // have been destroyed.
        self.vkDestroyInstance(null);
    }

    // Wrappers --------------------------------------------

    inline fn vkDestroyInstance(
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

    pub inline fn vkGetPhysicalDeviceImageFormatProperties(
        self: *Instance,
        device: c.VkPhysicalDevice,
        format: c.VkFormat,
        @"type": c.VkImageType,
        tiling: c.VkImageTiling,
        usage: c.VkImageUsageFlags,
        flags: c.VkImageCreateFlags,
        properties: *c.VkImageFormatProperties,
    ) c.VkResult {
        return self.getPhysicalDeviceImageFormatProperties.?(
            device,
            format,
            @"type",
            tiling,
            usage,
            flags,
            properties,
        );
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

    pub inline fn vkGetPhysicalDeviceProperties2(
        self: *Instance,
        device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceProperties2,
    ) void {
        self.getPhysicalDeviceProperties2.?(device, properties);
    }

    pub inline fn vkGetPhysicalDeviceFeatures2(
        self: *Instance,
        device: c.VkPhysicalDevice,
        features: *c.VkPhysicalDeviceFeatures2,
    ) void {
        self.getPhysicalDeviceFeatures2.?(device, features);
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

fn getGpus(_: *anyopaque, allocator: std.mem.Allocator) Error![]ngl.Gpu {
    // `ngl.getGpus` calls `Impl.init`, which calls `init`.
    const inst = Instance.get();

    var dev_n: u32 = undefined;
    try check(inst.vkEnumeratePhysicalDevices(&dev_n, null));
    if (dev_n == 0)
        return Error.NotSupported;
    const devs = try allocator.alloc(c.VkPhysicalDevice, dev_n);
    defer allocator.free(devs);
    try check(inst.vkEnumeratePhysicalDevices(&dev_n, devs.ptr));

    const gpus = try allocator.alloc(ngl.Gpu, dev_n);
    errdefer allocator.free(gpus);

    var queue_props = std.ArrayList(c.VkQueueFamilyProperties).init(allocator);
    defer queue_props.deinit();

    var ext = Extension.init(allocator);
    defer ext.deinit();

    var gpu_n: usize = 0;
    for (devs) |dev| {
        var prop: c.VkPhysicalDeviceProperties = undefined;
        inst.vkGetPhysicalDeviceProperties(dev, &prop);

        if (prop.apiVersion < supported_version)
            continue;

        var n: u32 = undefined;
        inst.vkGetPhysicalDeviceQueueFamilyProperties(dev, &n, null);
        try queue_props.resize(n);
        inst.vkGetPhysicalDeviceQueueFamilyProperties(dev, &n, queue_props.items.ptr);

        // Graphics/compute/transfer.
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
                    .image_transfer_granularity = .one,
                    .impl = .{
                        .impl = fam,
                        .info = .{ qp.timestampValidBits, 0, 0, 0 },
                    },
                };
                break;
            }
        } else continue;

        // Transfer-only.
        var xfer_queue: ?ngl.Queue.Desc = null;
        for (queue_props.items, 0..n) |qp, fam| {
            const mask =
                c.VK_QUEUE_GRAPHICS_BIT |
                c.VK_QUEUE_COMPUTE_BIT |
                c.VK_QUEUE_TRANSFER_BIT;
            const gran = [3]u32{
                qp.minImageTransferGranularity.width,
                qp.minImageTransferGranularity.height,
                qp.minImageTransferGranularity.depth,
            };
            if (qp.queueFlags & mask == c.VK_QUEUE_TRANSFER_BIT) {
                xfer_queue = .{
                    .capabilities = .{ .transfer = true },
                    .priority = .default,
                    .image_transfer_granularity = if (std.mem.eql(u32, &gran, &.{ 1, 1, 1 }))
                        .one
                    else
                        .whole_level,
                    .impl = .{
                        .impl = fam,
                        .info = .{ qp.timestampValidBits, 0, 0, 0 },
                    },
                };
                break;
            }
        }

        // TODO: Remove/update this conditional when adding more features
        // that need to query available extensions.
        if (inst.destroySurface != null) {
            ext.clearRetainingCapacity();
            try ext.putAllDevice(dev);
        }

        if (@typeInfo(ngl.Feature).Union.fields.len > 2)
            @compileError("Set new feature(s)");

        gpus[gpu_n] = .{
            .impl = .{ .val = @bitCast(Gpu{ .handle = dev }) },
            .info = .{ prop.apiVersion, 0, 0, 0 },
            .type = switch (prop.deviceType) {
                c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => .discrete,
                c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => .integrated,
                c.VK_PHYSICAL_DEVICE_TYPE_CPU => .cpu,
                else => .other,
            },
            .queues = .{ main_queue, xfer_queue, null, null },
            .feature_set = .{
                .core = true,
                // Don't expose this feature if the instance was created
                // with presentation disabled, regardless of whether or not
                // the device can support it.
                .presentation = if (inst.destroySurface != null)
                    ext.contains("VK_KHR_swapchain")
                else
                    false,
            },
        };
        gpu_n += 1;
    }

    return if (gpu_n > 0) gpus[0..gpu_n] else Error.NotSupported;
}

pub const Gpu = packed struct {
    handle: c.VkPhysicalDevice,

    pub inline fn cast(impl: Impl.Gpu) Gpu {
        return @bitCast(impl.val);
    }
};

pub const Device = struct {
    handle: c.VkDevice,
    version: u32,
    queues: [ngl.Queue.max]Queue,
    queue_n: u8,
    timestamp_period: f32,

    gpu: Gpu, // TODO: See if this can be removed.

    getDeviceProcAddr: c.PFN_vkGetDeviceProcAddr,

    // v1.0.
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
    cmdSetDepthBias: c.PFN_vkCmdSetDepthBias,
    cmdSetStencilCompareMask: c.PFN_vkCmdSetStencilCompareMask,
    cmdSetStencilWriteMask: c.PFN_vkCmdSetStencilWriteMask,
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
    cmdResetQueryPool: c.PFN_vkCmdResetQueryPool,
    cmdBeginQuery: c.PFN_vkCmdBeginQuery,
    cmdEndQuery: c.PFN_vkCmdEndQuery,
    cmdWriteTimestamp: c.PFN_vkCmdWriteTimestamp,
    cmdCopyQueryPoolResults: c.PFN_vkCmdCopyQueryPoolResults,
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
    getImageSubresourceLayout: c.PFN_vkGetImageSubresourceLayout,
    getImageMemoryRequirements: c.PFN_vkGetImageMemoryRequirements,
    bindImageMemory: c.PFN_vkBindImageMemory,
    createImageView: c.PFN_vkCreateImageView,
    destroyImageView: c.PFN_vkDestroyImageView,
    createSampler: c.PFN_vkCreateSampler,
    destroySampler: c.PFN_vkDestroySampler,
    createRenderPass: c.PFN_vkCreateRenderPass,
    destroyRenderPass: c.PFN_vkDestroyRenderPass,
    getRenderAreaGranularity: c.PFN_vkGetRenderAreaGranularity,
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
    createQueryPool: c.PFN_vkCreateQueryPool,
    destroyQueryPool: c.PFN_vkDestroyQueryPool,
    // v1.3.
    cmdBeginRendering: c.PFN_vkCmdBeginRendering,
    cmdEndRendering: c.PFN_vkCmdEndRendering,
    // VK_KHR_swapchain.
    queuePresent: c.PFN_vkQueuePresentKHR,
    createSwapchain: c.PFN_vkCreateSwapchainKHR,
    getSwapchainImages: c.PFN_vkGetSwapchainImagesKHR,
    acquireNextImage: c.PFN_vkAcquireNextImageKHR,
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

    fn init(_: *anyopaque, allocator: std.mem.Allocator, gpu: ngl.Gpu) Error!Impl.Device {
        const inst = Instance.get();
        const phys_dev = Gpu.cast(gpu.impl).handle;

        var queue_infos: [ngl.Queue.max]c.VkDeviceQueueCreateInfo = undefined;
        var queue_prios: [ngl.Queue.max]f32 = undefined;
        const queue_n = blk: {
            var n: u32 = 0;
            for (gpu.queues) |queue| {
                const q = queue orelse continue;
                const fam: u32 = if (q.impl) |x| @intCast(x.impl) else return Error.InvalidArgument;
                // Don't distinguish between default and high priority.
                queue_prios[n] = if (q.priority == .low) 0 else 1;
                queue_infos[n] = .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .queueFamilyIndex = fam,
                    .queueCount = 1,
                    .pQueuePriorities = &queue_prios[n],
                };
                n += 1;
            }
            if (n == 0) return Error.InvalidArgument;
            break :blk n;
        };

        // If the instance version is 1.0, then we can't use anything
        // newer than that for the device.
        // Otherwise, we need to abide by what was requested during
        // instance creation.
        const ver = if (inst.version < c.VK_API_VERSION_1_1)
            c.VK_API_VERSION_1_0
        else if (gpu.info[0] & ~@as(u32, 0xfff) > preferred_version)
            preferred_version
        else
            gpu.info[0];

        // TODO: Check other extensions.
        var ext = Extension.init(allocator);
        defer ext.deinit();
        try ext.putAllDevice(phys_dev);
        var ext_names = std.ArrayList([*:0]const u8).init(allocator);
        defer ext_names.deinit();

        if (gpu.feature_set.presentation) {
            if (inst.destroySurface == null) return Error.InvalidArgument;
            const swapchain_ext = "VK_KHR_swapchain";
            if (ext.contains(swapchain_ext)) {
                try ext_names.append(swapchain_ext);
            } else return Error.NotSupported;
        }

        var feat = Feature.getVersion(phys_dev, @intCast(ver));
        feat.set();

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
            .pEnabledFeatures = null,
        };
        feat.ref(&create_info);
        var dev: c.VkDevice = undefined;
        try check(inst.vkCreateDevice(phys_dev, &create_info, null, &dev));
        errdefer if (Instance.getProc(inst.handle, "vkDestroyDevice")) |x| {
            if (@as(c.PFN_vkDestroyDevice, @ptrCast(x))) |f| f(dev, null);
        } else |_| {};

        var dev_props: c.VkPhysicalDeviceProperties = undefined;
        inst.vkGetPhysicalDeviceProperties(phys_dev, &dev_props);
        const tms_period: f32 = dev_props.limits.timestampPeriod;

        const get: c.PFN_vkGetDeviceProcAddr = @ptrCast(try Instance.getProc(
            inst.handle,
            "vkGetDeviceProcAddr",
        ));

        var ptr = try allocator.create(Device);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .handle = dev,
            .version = @intCast(ver),
            .queues = undefined,
            .queue_n = 0,
            .timestamp_period = tms_period,

            .gpu = Gpu.cast(gpu.impl),

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
            .cmdSetDepthBias = @ptrCast(try Device.getProc(get, dev, "vkCmdSetDepthBias")),
            .cmdSetStencilCompareMask = @ptrCast(try Device.getProc(get, dev, "vkCmdSetStencilCompareMask")),
            .cmdSetStencilWriteMask = @ptrCast(try Device.getProc(get, dev, "vkCmdSetStencilWriteMask")),
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
            .cmdResetQueryPool = @ptrCast(try Device.getProc(get, dev, "vkCmdResetQueryPool")),
            .cmdBeginQuery = @ptrCast(try Device.getProc(get, dev, "vkCmdBeginQuery")),
            .cmdEndQuery = @ptrCast(try Device.getProc(get, dev, "vkCmdEndQuery")),
            .cmdWriteTimestamp = @ptrCast(try Device.getProc(get, dev, "vkCmdWriteTimestamp")),
            .cmdCopyQueryPoolResults = @ptrCast(try Device.getProc(get, dev, "vkCmdCopyQueryPoolResults")),
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
            .getImageSubresourceLayout = @ptrCast(try Device.getProc(get, dev, "vkGetImageSubresourceLayout")),
            .getImageMemoryRequirements = @ptrCast(try Device.getProc(get, dev, "vkGetImageMemoryRequirements")),
            .bindImageMemory = @ptrCast(try Device.getProc(get, dev, "vkBindImageMemory")),
            .createImageView = @ptrCast(try Device.getProc(get, dev, "vkCreateImageView")),
            .destroyImageView = @ptrCast(try Device.getProc(get, dev, "vkDestroyImageView")),
            .createSampler = @ptrCast(try Device.getProc(get, dev, "vkCreateSampler")),
            .destroySampler = @ptrCast(try Device.getProc(get, dev, "vkDestroySampler")),
            .createRenderPass = @ptrCast(try Device.getProc(get, dev, "vkCreateRenderPass")),
            .destroyRenderPass = @ptrCast(try Device.getProc(get, dev, "vkDestroyRenderPass")),
            .getRenderAreaGranularity = @ptrCast(try Device.getProc(get, dev, "vkGetRenderAreaGranularity")),
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
            .createQueryPool = @ptrCast(try Device.getProc(get, dev, "vkCreateQueryPool")),
            .destroyQueryPool = @ptrCast(try Device.getProc(get, dev, "vkDestroyQueryPool")),

            .cmdBeginRendering = if (ver >= c.VK_API_VERSION_1_3)
                @ptrCast(try Device.getProc(get, dev, "vkCmdBeginRendering"))
            else
                null,
            .cmdEndRendering = if (ver >= c.VK_API_VERSION_1_3)
                @ptrCast(try Device.getProc(get, dev, "vkCmdEndRendering"))
            else
                null,

            .queuePresent = if (gpu.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkQueuePresentKHR"))
            else
                null,
            .createSwapchain = if (gpu.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkCreateSwapchainKHR"))
            else
                null,
            .getSwapchainImages = if (gpu.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkGetSwapchainImagesKHR"))
            else
                null,
            .acquireNextImage = if (gpu.feature_set.presentation)
                @ptrCast(try Device.getProc(get, dev, "vkAcquireNextImageKHR"))
            else
                null,
            .destroySwapchain = if (gpu.feature_set.presentation)
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

        var props: c.VkPhysicalDeviceMemoryProperties = undefined;
        Instance.get().vkGetPhysicalDeviceMemoryProperties(dev.gpu.handle, &props);
        const mask: u32 =
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT |
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
            c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT |
            c.VK_MEMORY_PROPERTY_HOST_CACHED_BIT |
            c.VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT;

        for (0..props.memoryTypeCount) |i| {
            const flags = props.memoryTypes[i].propertyFlags;
            const heap: u4 = @intCast(props.memoryTypes[i].heapIndex);
            // TODO: Handle this somehow.
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
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Memory.Desc,
    ) Error!Impl.Memory {
        var mem: c.VkDeviceMemory = undefined;
        try check(cast(device).vkAllocateMemory(&.{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = desc.size,
            .memoryTypeIndex = desc.type_index,
        }, null, &mem));

        return .{ .val = @bitCast(Memory{ .handle = mem }) };
    }

    fn free(_: *anyopaque, _: std.mem.Allocator, device: Impl.Device, memory: Impl.Memory) void {
        cast(device).vkFreeMemory(Memory.cast(memory).handle, null);
    }

    fn wait(_: *anyopaque, device: Impl.Device) Error!void {
        try check(cast(device).vkDeviceWaitIdle());
    }

    fn deinit(_: *anyopaque, allocator: std.mem.Allocator, device: Impl.Device) void {
        const dev = cast(device);
        // NOTE: This assumes that all device-level objects
        // have been destroyed.
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

    pub inline fn vkCmdSetDepthBias(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        constant_factor: f32,
        clamp: f32,
        slope_factor: f32,
    ) void {
        self.cmdSetDepthBias.?(command_buffer, constant_factor, clamp, slope_factor);
    }

    pub inline fn vkCmdSetStencilCompareMask(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        face_mask: c.VkStencilFaceFlags,
        compare_mask: u32,
    ) void {
        self.cmdSetStencilCompareMask.?(command_buffer, face_mask, compare_mask);
    }

    pub inline fn vkCmdSetStencilWriteMask(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        face_mask: c.VkStencilFaceFlags,
        write_mask: u32,
    ) void {
        self.cmdSetStencilWriteMask.?(command_buffer, face_mask, write_mask);
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

    pub inline fn vkCmdResetQueryPool(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        query_pool: c.VkQueryPool,
        first_query: u32,
        query_count: u32,
    ) void {
        self.cmdResetQueryPool.?(command_buffer, query_pool, first_query, query_count);
    }

    pub inline fn vkCmdBeginQuery(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        query_pool: c.VkQueryPool,
        query: u32,
        flags: c.VkQueryControlFlags,
    ) void {
        self.cmdBeginQuery.?(command_buffer, query_pool, query, flags);
    }

    pub inline fn vkCmdEndQuery(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        query_pool: c.VkQueryPool,
        query: u32,
    ) void {
        self.cmdEndQuery.?(command_buffer, query_pool, query);
    }

    pub inline fn vkCmdWriteTimestamp(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        pipeline_stage: c.VkPipelineStageFlagBits,
        query_pool: c.VkQueryPool,
        query: u32,
    ) void {
        self.cmdWriteTimestamp.?(command_buffer, pipeline_stage, query_pool, query);
    }

    pub inline fn vkCmdCopyQueryPoolResults(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        query_pool: c.VkQueryPool,
        first_query: u32,
        query_count: u32,
        dest_buffer: c.VkBuffer,
        dest_offset: u64,
        stride: u64,
        flags: c.VkQueryResultFlags,
    ) void {
        self.cmdCopyQueryPoolResults.?(
            command_buffer,
            query_pool,
            first_query,
            query_count,
            dest_buffer,
            dest_offset,
            stride,
            flags,
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

    pub inline fn vkGetImageSubresourceLayout(
        self: *Device,
        image: c.VkImage,
        subresource: *const c.VkImageSubresource,
        layout: *c.VkSubresourceLayout,
    ) void {
        self.getImageSubresourceLayout.?(self.handle, image, subresource, layout);
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

    pub inline fn vkGetRenderAreaGranularity(
        self: *Device,
        render_pass: c.VkRenderPass,
        granularity: *c.VkExtent2D,
    ) void {
        self.getRenderAreaGranularity.?(self.handle, render_pass, granularity);
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

    pub inline fn vkCreateQueryPool(
        self: *Device,
        create_info: *const c.VkQueryPoolCreateInfo,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        query_pool: *c.VkQueryPool,
    ) c.VkResult {
        return self.createQueryPool.?(self.handle, create_info, vk_allocator, query_pool);
    }

    pub inline fn vkDestroyQueryPool(
        self: *Device,
        query_pool: c.VkQueryPool,
        vk_allocator: ?*const c.VkAllocationCallbacks,
    ) void {
        self.destroyQueryPool.?(self.handle, query_pool, vk_allocator);
    }

    pub inline fn vkCmdBeginRendering(
        self: *Device,
        command_buffer: c.VkCommandBuffer,
        rendering_info: *const c.VkRenderingInfo,
    ) void {
        self.cmdBeginRendering.?(command_buffer, rendering_info);
    }

    pub inline fn vkCmdEndRendering(self: *Device, command_buffer: c.VkCommandBuffer) void {
        self.cmdEndRendering.?(command_buffer);
    }

    pub inline fn vkQueuePresentKHR(
        self: *Device,
        queue: c.VkQueue,
        present_info: *const c.VkPresentInfoKHR,
    ) c.VkResult {
        return self.queuePresent.?(queue, present_info);
    }

    pub inline fn vkCreateSwapchainKHR(
        self: *Device,
        create_info: *const c.VkSwapchainCreateInfoKHR,
        vk_allocator: ?*const c.VkAllocationCallbacks,
        swapchain: *c.VkSwapchainKHR,
    ) c.VkResult {
        return self.createSwapchain.?(self.handle, create_info, vk_allocator, swapchain);
    }

    pub inline fn vkGetSwapchainImagesKHR(
        self: *Device,
        swapchain: c.VkSwapchainKHR,
        image_count: *u32,
        images: ?[*]c.VkImage,
    ) c.VkResult {
        return self.getSwapchainImages.?(self.handle, swapchain, image_count, images);
    }

    pub inline fn vkAcquireNextImageKHR(
        self: *Device,
        swapchain: c.VkSwapchainKHR,
        timeout: u64,
        semaphore: c.VkSemaphore,
        fence: c.VkFence,
        image_index: *u32,
    ) c.VkResult {
        return self.acquireNextImage.?(
            self.handle,
            swapchain,
            timeout,
            semaphore,
            fence,
            image_index,
        );
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
                    // No signal stage mask on vanilla submission.
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

    // TODO: Don't allocate on every call
    fn present(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        queue: Impl.Queue,
        wait_semaphores: []const *ngl.Semaphore,
        presents: []const ngl.Queue.Present,
    ) Error!void {
        std.debug.assert(presents.len > 0);

        const n = 8;
        var stk_semas: [n]c.VkSemaphore = undefined;
        var stk_scs: [n]c.VkSwapchainKHR = undefined;
        var stk_inds: [n]u32 = undefined;

        const semas = if (wait_semaphores.len > n)
            try allocator.alloc(c.VkSemaphore, wait_semaphores.len)
        else
            stk_semas[0..wait_semaphores.len];
        defer if (wait_semaphores.len > n) allocator.free(semas);
        for (semas, wait_semaphores) |*handle, sema|
            handle.* = Semaphore.cast(sema.impl).handle;

        var scs: []c.VkSwapchainKHR = undefined;
        var inds: []u32 = undefined;
        if (presents.len > n) {
            scs = try allocator.alloc(c.VkSwapchainKHR, presents.len);
            inds = allocator.alloc(u32, presents.len) catch |err| {
                allocator.free(scs);
                return err;
            };
        } else {
            scs = stk_scs[0..presents.len];
            inds = stk_inds[0..presents.len];
        }
        defer if (presents.len > n) {
            allocator.free(scs);
            allocator.free(inds);
        };
        for (scs, inds, presents) |*sc, *idx, pres| {
            sc.* = SwapChain.cast(pres.swap_chain.impl).handle;
            idx.* = pres.image_index;
        }

        try check(Device.cast(device).vkQueuePresentKHR(Queue.cast(queue).handle, &.{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = @intCast(wait_semaphores.len),
            .pWaitSemaphores = if (wait_semaphores.len > 0) semas.ptr else null,
            .swapchainCount = @intCast(presents.len),
            .pSwapchains = scs.ptr,
            .pImageIndices = inds.ptr,
            .pResults = null,
        }));
    }

    fn wait(_: *anyopaque, device: Impl.Device, queue: Impl.Queue) Error!void {
        try check(Device.cast(device).vkQueueWaitIdle(cast(queue).handle));
    }
};

pub const Memory = packed struct {
    handle: c.VkDeviceMemory,

    pub inline fn cast(impl: Impl.Memory) Memory {
        return @bitCast(impl.val);
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
        try flushOrInvalidateMapped(.flush, allocator, device, memory, offsets, sizes);
    }

    fn invalidateMapped(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        memory: Impl.Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        try flushOrInvalidateMapped(.invalidate, allocator, device, memory, offsets, sizes);
    }
};

fn getFeature(
    _: *anyopaque,
    _: std.mem.Allocator,
    gpu: ngl.Gpu,
    feature: *ngl.Feature,
) Error!void {
    const inst = Instance.get();
    const phys_dev = Gpu.cast(gpu.impl).handle;

    const convSpls = conv.fromVkSampleCountFlags;

    switch (feature.*) {
        .core => |*feat| {
            const prop = blk: {
                // TODO: Improve this.
                var prop = Property.getVersion(phys_dev, c.VK_API_VERSION_1_0);
                if (inst.version >= c.VK_API_VERSION_1_1 and
                    prop.properties_2.properties.apiVersion >= c.VK_API_VERSION_1_2)
                {
                    prop = Property.getVersion(phys_dev, prop.properties_2.properties.apiVersion);
                }
                break :blk prop;
            };
            const ver = prop.properties_2.properties.apiVersion;
            const l = &prop.properties_2.properties.limits;

            const ft = blk: {
                // TODO: Make sure to update the options as needed.
                var ft = Feature.get(phys_dev, .{
                    .@"1.1" = false,
                    .@"1.2" = ver >= c.VK_API_VERSION_1_2,
                    .@"1.3" = false,
                });
                // TODO: This is unnecessary.
                ft.set();
                break :blk ft;
            };
            const f = &ft.features_2.features;

            var mem_max_size: u64 = 1073741824;
            var fb_int_spl_cnts = ngl.SampleCount.Flags{ .@"1" = true };
            var splr_mirror_clamp_to_edge = false;
            var buf_max_size: u64 = 1073741824;

            if (ver >= c.VK_API_VERSION_1_2) {
                mem_max_size = prop.@"1.1".maxMemoryAllocationSize;

                // Certain devices may lie about MS support
                // for signed integer formats.
                // TODO: It seems that this has been fixed.
                var x: c.VkImageFormatProperties = undefined;
                const r = inst.vkGetPhysicalDeviceImageFormatProperties(
                    phys_dev,
                    c.VK_FORMAT_R8_SINT,
                    c.VK_IMAGE_TYPE_2D,
                    c.VK_IMAGE_TILING_OPTIMAL,
                    c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
                    0,
                    &x,
                );
                const mask = prop.@"1.2".framebufferIntegerColorSampleCounts;
                if (r != c.VK_SUCCESS or x.sampleCounts & mask != mask)
                    // Use the default (no MS).
                    log.warn("Feature.core.frame_buffer.integer_sample_counts workaround", .{})
                else
                    fb_int_spl_cnts = convSpls(mask);

                splr_mirror_clamp_to_edge = ft.@"1.2".samplerMirrorClampToEdge == c.VK_TRUE;
            }

            if (ver >= c.VK_API_VERSION_1_3)
                buf_max_size = prop.@"1.3".maxBufferSize;

            feat.* = .{
                .memory = .{
                    .max_count = l.maxMemoryAllocationCount,
                    .max_size = mem_max_size,
                    .min_map_alignment = l.minMemoryMapAlignment,
                },
                .sampler = .{
                    .max_count = l.maxSamplerAllocationCount,
                    .max_anisotropy = @intFromFloat(@min(16, @max(1, l.maxSamplerAnisotropy))),
                    .address_mode_mirror_clamp_to_edge = splr_mirror_clamp_to_edge,
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
                    .max_size = buf_max_size,
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
                    .integer_sample_counts = fb_int_spl_cnts,
                    .depth_sample_counts = convSpls(l.framebufferDepthSampleCounts),
                    .stencil_sample_counts = convSpls(l.framebufferStencilSampleCounts),
                    .no_attachment_sample_counts = convSpls(l.framebufferNoAttachmentsSampleCounts),
                },
                .draw = .{
                    .max_index_value = l.maxDrawIndexedIndexValue,
                    .indirect_command = true,
                    .indexed_indirect_command = true,
                    .max_indirect_count = l.maxDrawIndirectCount,
                    .indirect_first_instance = f.drawIndirectFirstInstance == c.VK_TRUE,
                },
                .dispatch = .{
                    .indirect_command = true,
                },
                .primitive = .{
                    .max_bindings = l.maxVertexInputBindings,
                    .max_attributes = l.maxVertexInputAttributes,
                    .max_binding_stride = l.maxVertexInputBindingStride,
                    .max_attribute_offset = l.maxVertexInputAttributeOffset,
                },
                .viewport = .{
                    .max_count = l.maxViewports,
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
                .query = .{
                    .occlusion_precise = f.occlusionQueryPrecise == c.VK_TRUE,
                    .timestamp = blk: {
                        if (l.timestampPeriod == 0)
                            break :blk [_]bool{false} ** ngl.Queue.max;
                        var supported: [ngl.Queue.max]bool = undefined;
                        for (gpu.queues, 0..) |queue, i| {
                            const q = queue orelse {
                                supported[i] = false;
                                continue;
                            };
                            supported[i] = if (q.impl) |x| x.info[0] != 0 else false;
                        }
                        break :blk supported;
                    },
                    .inherited = f.inheritedQueries == c.VK_TRUE,
                },
            };
        },

        .presentation => |*feat| if (gpu.feature_set.presentation) {
            feat.* = {};
        } else return Error.NotSupported,
    }
}

const vtable = Impl.VTable{
    .deinit = deinit,

    .getGpus = getGpus,

    .initDevice = Device.init,
    .getQueues = Device.getQueues,
    .getMemoryTypes = Device.getMemoryTypes,
    .allocMemory = Device.alloc,
    .freeMemory = Device.free,
    .waitDevice = Device.wait,
    .deinitDevice = Device.deinit,

    .submit = Queue.submit,
    .present = Queue.present,
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
    .setShaders = @import("cmd.zig").CommandBuffer.setShaders,
    .setDescriptors = @import("cmd.zig").CommandBuffer.setDescriptors,
    .setPushConstants = @import("cmd.zig").CommandBuffer.setPushConstants,
    .setVertexInput = @import("cmd.zig").CommandBuffer.setVertexInput,
    .setPrimitiveTopology = @import("cmd.zig").CommandBuffer.setPrimitiveTopology,
    .setIndexBuffer = @import("cmd.zig").CommandBuffer.setIndexBuffer,
    .setVertexBuffers = @import("cmd.zig").CommandBuffer.setVertexBuffers,
    .setViewports = @import("cmd.zig").CommandBuffer.setViewports,
    .setScissorRects = @import("cmd.zig").CommandBuffer.setScissorRects,
    .setPolygonMode = @import("cmd.zig").CommandBuffer.setPolygonMode,
    .setCullMode = @import("cmd.zig").CommandBuffer.setCullMode,
    .setFrontFace = @import("cmd.zig").CommandBuffer.setFrontFace,
    .setSampleCount = @import("cmd.zig").CommandBuffer.setSampleCount,
    .setSampleMask = @import("cmd.zig").CommandBuffer.setSampleMask,
    .setDepthBias = @import("cmd.zig").CommandBuffer.setDepthBias,
    .setDepthTestEnable = @import("cmd.zig").CommandBuffer.setDepthTestEnable,
    .setDepthCompareOp = @import("cmd.zig").CommandBuffer.setDepthCompareOp,
    .setDepthWriteEnable = @import("cmd.zig").CommandBuffer.setDepthWriteEnable,
    .setStencilTestEnable = @import("cmd.zig").CommandBuffer.setStencilTestEnable,
    .setStencilOp = @import("cmd.zig").CommandBuffer.setStencilOp,
    .setStencilReadMask = @import("cmd.zig").CommandBuffer.setStencilReadMask,
    .setStencilWriteMask = @import("cmd.zig").CommandBuffer.setStencilWriteMask,
    .setStencilReference = @import("cmd.zig").CommandBuffer.setStencilReference,
    .setBlendConstants = @import("cmd.zig").CommandBuffer.setBlendConstants,
    .beginRenderPass = @import("cmd.zig").CommandBuffer.beginRenderPass,
    .nextSubpass = @import("cmd.zig").CommandBuffer.nextSubpass,
    .endRenderPass = @import("cmd.zig").CommandBuffer.endRenderPass,
    .beginRendering = @import("cmd.zig").CommandBuffer.beginRendering,
    .endRendering = @import("cmd.zig").CommandBuffer.endRendering,
    .draw = @import("cmd.zig").CommandBuffer.draw,
    .drawIndexed = @import("cmd.zig").CommandBuffer.drawIndexed,
    .drawIndirect = @import("cmd.zig").CommandBuffer.drawIndirect,
    .drawIndexedIndirect = @import("cmd.zig").CommandBuffer.drawIndexedIndirect,
    .dispatch = @import("cmd.zig").CommandBuffer.dispatch,
    .dispatchIndirect = @import("cmd.zig").CommandBuffer.dispatchIndirect,
    .clearBuffer = @import("cmd.zig").CommandBuffer.clearBuffer,
    .copyBuffer = @import("cmd.zig").CommandBuffer.copyBuffer,
    .copyImage = @import("cmd.zig").CommandBuffer.copyImage,
    .copyBufferToImage = @import("cmd.zig").CommandBuffer.copyBufferToImage,
    .copyImageToBuffer = @import("cmd.zig").CommandBuffer.copyImageToBuffer,
    .resetQueryPool = @import("cmd.zig").CommandBuffer.resetQueryPool,
    .beginQuery = @import("cmd.zig").CommandBuffer.beginQuery,
    .endQuery = @import("cmd.zig").CommandBuffer.endQuery,
    .writeTimestamp = @import("cmd.zig").CommandBuffer.writeTimestamp,
    .copyQueryPoolResults = @import("cmd.zig").CommandBuffer.copyQueryPoolResults,
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
    .bindBuffer = @import("res.zig").Buffer.bind,
    .deinitBuffer = @import("res.zig").Buffer.deinit,

    .initBufferView = @import("res.zig").BufferView.init,
    .deinitBufferView = @import("res.zig").BufferView.deinit,

    .initImage = @import("res.zig").Image.init,
    .getImageCapabilities = @import("res.zig").Image.getCapabilities,
    .getImageDataLayout = @import("res.zig").Image.getDataLayout,
    .getMemoryRequirementsImage = @import("res.zig").Image.getMemoryRequirements,
    .bindImage = @import("res.zig").Image.bind,
    .deinitImage = @import("res.zig").Image.deinit,

    .initImageView = @import("res.zig").ImageView.init,
    .deinitImageView = @import("res.zig").ImageView.deinit,

    .initSampler = @import("res.zig").Sampler.init,
    .deinitSampler = @import("res.zig").Sampler.deinit,

    .initRenderPass = @import("pass.zig").RenderPass.init,
    .getRenderAreaGranularity = @import("pass.zig").RenderPass.getRenderAreaGranularity,
    .deinitRenderPass = @import("pass.zig").RenderPass.deinit,

    .initFrameBuffer = @import("pass.zig").FrameBuffer.init,
    .deinitFrameBuffer = @import("pass.zig").FrameBuffer.deinit,

    .initShader = @import("shd.zig").Shader.init,
    .deinitShader = @import("shd.zig").Shader.deinit,

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

    .getQueryLayout = @import("query.zig").getQueryLayout,

    .initQueryPool = @import("query.zig").QueryPool.init,
    .deinitQueryPool = @import("query.zig").QueryPool.deinit,

    .resolveQueryOcclusion = @import("query.zig").resolveQueryOcclusion,
    .resolveQueryTimestamp = @import("query.zig").resolveQueryTimestamp,

    .initSurface = @import("dpy.zig").Surface.init,
    .isSurfaceCompatible = @import("dpy.zig").Surface.isCompatible,
    .getSurfacePresentModes = @import("dpy.zig").Surface.getPresentModes,
    .getSurfaceFormats = @import("dpy.zig").Surface.getFormats,
    .getSurfaceCapabilities = @import("dpy.zig").Surface.getCapabilities,
    .deinitSurface = @import("dpy.zig").Surface.deinit,

    .initSwapChain = @import("dpy.zig").SwapChain.init,
    .getSwapChainImages = @import("dpy.zig").SwapChain.getImages,
    .nextSwapChainImage = @import("dpy.zig").SwapChain.nextImage,
    .deinitSwapChain = @import("dpy.zig").SwapChain.deinit,
};
