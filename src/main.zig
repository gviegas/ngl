const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Device = @import("Device.zig");
pub const Buffer = @import("Buffer.zig");
pub const Texture = @import("Texture.zig");
pub const TexView = @import("TexView.zig");

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

    var tex_view = try TexView.init(&texture, .{
        .dimension = .@"2d",
        .format = texture.format,
        .plane = 0,
        .first_level = 0,
        .levels = 1,
        .first_layer = 0,
        .layers = 1,
    });
    defer tex_view.deinit();
}
