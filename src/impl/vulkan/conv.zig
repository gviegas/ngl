const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const c = @import("../c.zig");

/// Anything other than `VK_SUCCESS` produces an `Error`.
pub fn check(result: c.VkResult) Error!void {
    return switch (result) {
        c.VK_SUCCESS => {},

        c.VK_NOT_READY => Error.NotReady,

        c.VK_TIMEOUT => Error.Timeout,

        c.VK_ERROR_OUT_OF_HOST_MEMORY,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY,
        => Error.OutOfMemory,

        c.VK_ERROR_INITIALIZATION_FAILED => Error.InitializationFailed,

        c.VK_ERROR_DEVICE_LOST => Error.DeviceLost,

        c.VK_ERROR_TOO_MANY_OBJECTS => Error.TooManyObjects,

        c.VK_ERROR_FORMAT_NOT_SUPPORTED => Error.NotSupported,

        c.VK_ERROR_LAYER_NOT_PRESENT,
        c.VK_ERROR_EXTENSION_NOT_PRESENT,
        c.VK_ERROR_FEATURE_NOT_PRESENT,
        => Error.NotPresent,

        else => Error.Other,
    };
}
