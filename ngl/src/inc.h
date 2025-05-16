// Meant to be translated.

#define VK_NO_prototypes
#include <vulkan/vulkan_core.h>
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#include <windows.h>
#include <vulkan/vulkan_win32.h>
#elif defined(__linux__)
#include <dlfcn.h>
#include <wayland-client.h>
#include <xdg-shell-client.h>
#include <vulkan/vulkan_wayland.h>
#else
#error OS not supported
#endif