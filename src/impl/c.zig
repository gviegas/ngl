const builtin = @import("builtin");

pub usingnamespace @cImport({
    switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => @cDefine("NDEBUG", {}),
        else => @cUndef("NDEBUG"),
    }
    switch (builtin.os.tag) {
        .linux => {
            @cDefine("VK_NO_PROTOTYPES", {});
            if (!builtin.target.isAndroid()) {
                @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", {});
                @cDefine("VK_USE_PLATFORM_XCB_KHR", {});
            } else @cDefine("VK_USE_PLATFORM_ANDROID_KHR", {});
            // TODO: Custom Vulkan header path
            @cInclude("vulkan/vulkan.h");
            @cInclude("dlfcn.h");
        },
        .windows => {
            @cDefine("VK_NO_PROTOTYPES", {});
            @cDefine("VK_USE_PLATFORM_WIN32_KHR", {});
            // TODO: Custom Vulkan header path
            @cInclude("vulkan/vulkan.h");
        },
        else => {}, // TODO
    }
});
