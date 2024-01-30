#if defined(__linux__) || defined(_WIN32) || defined(__ANDROID__)
# define VK_NO_PROTOTYPES
# include <vulkan/vulkan_core.h>
#else
# error Not supported
#endif

#if defined(__ANDROID__)
#elif defined(__linux__)
# include <wayland-client.h>
# include <vulkan/vulkan_wayland.h>
# include <xcb/xcb.h>
# include <vulkan/vulkan_xcb.h>
# include <dlfcn.h>
#elif defined(_WIN32)
# include <windows.h>
# include <vulkan/vulkan_win32.h>
#endif
