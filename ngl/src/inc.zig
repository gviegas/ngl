const builtin = @import("builtin");

pub usingnamespace @cImport({
    switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => @cDefine("NDEBUG", {}),
        else => {},
    }
    switch (builtin.os.tag) {
        .linux, .windows => {
            @cDefine("VK_NO_PROTOTYPES", {});
            @cInclude("vulkan/vulkan_core.h");
        },
        else => {},
    }
    switch (builtin.os.tag) {
        .linux => if (!builtin.target.isAndroid()) {
            @cInclude("dlfcn.h");
            @cInclude("wayland-client.h");
            @cInclude("xdg-shell-client.h");
            @cInclude("vulkan/vulkan_wayland.h");
        },
        .windows => {
            @cInclude("windows.h");
            @cInclude("vulkan/vulkan_win32.h");
        },
        else => @compileError("TODO"),
    }
});
