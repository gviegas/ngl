const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Device = @import("Device.zig");
pub const Buffer = @import("Buffer.zig");
pub const Texture = @import("Texture.zig");

pub const Error = error{
    DeviceLost,
    Internal,
    OutOfMemory,
    Validation,
    NotSupported,
};

test "ngl" {
    const allocator = std.testing.allocator;

    var device = try Device.init(allocator, .{});
    defer device.deinit();

    var buffer = try Buffer.init(&device, .{
        .size = 2048,
        .visible = false,
        .usage = .{
            .copy_src = true,
            .storage = true,
        },
    });
    defer buffer.deinit();

    var texture = try Texture.init(&device, .{
        .dimension = .@"2d",
        .format = .rgba8_unorm,
        .width = 256,
        .height = 256,
        .depth_or_layers = 1,
        .levels = 1,
        .samples = 1,
        .usage = .{
            .copy_dst = true,
            .sampled = true,
        },
    });
    defer texture.deinit();
}
