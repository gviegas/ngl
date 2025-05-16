const builtin = @import("builtin");

pub usingnamespace if (builtin.os.tag == .windows and builtin.cpu.arch == .x86_64)
    @import("windows.zig")
else
    @cImport({
        switch (builtin.os.tag) {
            .linux => {
                @cDefine("VK_NO_PROTOTYPES", {});
                @cInclude("vulkan/vulkan_core.h");
                if (!builtin.abi.isAndroid()) {
                    @cInclude("dlfcn.h");
                    @cInclude("wayland-client.h");
                    @cInclude("xdg-shell-client.h");
                    @cInclude("vulkan/vulkan_wayland.h");
                }
            },
            else => @compileError("TODO"),
        }
    });
