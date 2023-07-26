const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Device = @import("Device.zig");
pub const Heap = @import("Heap.zig");
pub const Buffer = @import("Buffer.zig");
pub const Texture = @import("Texture.zig");
pub const TexView = @import("TexView.zig");
pub const Sampler = @import("Sampler.zig");

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

    _ = device.isHighPerformance();
    _ = device.isLowPower();
    _ = device.isFallbackDevice();

    _ = try device.heapBufferPlacement(.{
        .offset = 0,
        .size = 16 << 20,
        .usage = .{
            .copy_src = true,
        },
    });
    _ = try device.heapTexturePlacement(.{
        .offset = 0,
        .dimension = .@"2d",
        .format = .rgba8_unorm,
        .width = 2048,
        .height = 2048,
        .depth_or_layers = 16,
        .usage = .{
            .copy_dst = true,
            .sampled = true,
        },
    });

    var heap = try device.initHeap(.{
        .size = 2 << 20,
        .cpu_access = .none,
    });
    defer heap.deinit();

    var buffer = try heap.initBuffer(.{
        .offset = 0,
        .size = 2048,
        .usage = .{
            .copy_src = true,
            .storage = true,
        },
    });
    defer buffer.deinit();

    var texture = try heap.initTexture(.{
        .offset = 0,
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

    var tex_view = try texture.initView(.{
        .dimension = .@"2d",
        .format = texture.format,
        .plane = 0,
        .first_level = 0,
        .levels = 1,
        .first_layer = 0,
        .layers = 1,
    });
    defer tex_view.deinit();

    var sampler = try device.initSampler(.{
        .u_addressing = .{ .clamp_to_border = .transparent_black },
        .v_addressing = .repeat,
        .min_filter = .linear,
        .mip_filter = .nearest,
        .max_anisotropy = 16,
        .compare = null,
    });
    defer sampler.deinit();
}
