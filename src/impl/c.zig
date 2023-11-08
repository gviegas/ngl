const builtin = @import("builtin");

// TODO: Custom Vulkan header path
const vulkan_path = "vulkan/";

pub usingnamespace @cImport({
    switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => @cDefine("NDEBUG", {}),
        else => @cUndef("NDEBUG"),
    }
    switch (builtin.os.tag) {
        .linux => {
            @cDefine("VK_NO_PROTOTYPES", {});
            @cInclude(vulkan_path ++ "vulkan_core.h");
            if (!builtin.target.isAndroid()) {
                @cInclude("wayland-client.h");
                @cInclude(vulkan_path ++ "vulkan_wayland.h");
                @cInclude("xcb/xcb.h");
                @cInclude(vulkan_path ++ "vulkan_xcb.h");
            } else @cInclude(vulkan_path ++ "vulkan_android.h");
            @cInclude("dlfcn.h");
        },
        .windows => {
            @cDefine("VK_NO_PROTOTYPES", {});
            @cInclude(vulkan_path ++ "vulkan_core.h");
            @cInclude("windows.h");
            @cInclude(vulkan_path ++ "vulkan_win32.h");
        },
        else => {}, // TODO
    }
});
