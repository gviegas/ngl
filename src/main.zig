pub const Device = @import("Device.zig");
pub const Heap = @import("Heap.zig");
pub const Buffer = @import("Buffer.zig");
pub const Texture = @import("Texture.zig");
pub const TexView = @import("TexView.zig");
pub const Sampler = @import("Sampler.zig");
pub const DescLayout = @import("DescLayout.zig");
pub const DescPool = @import("DescPool.zig");
pub const DescSet = @import("DescSet.zig");
pub const ShaderCode = @import("ShaderCode.zig");
pub const PsLayout = @import("PsLayout.zig");
pub const Pipeline = @import("Pipeline.zig");
pub const CmdPool = @import("CmdPool.zig");
pub const CmdBuffer = @import("CmdBuffer.zig");

pub const Error = error{
    DeviceLost,
    Internal,
    OutOfMemory,
    Validation,
    NotSupported,
};

test "ngl" {
    const allocator = @import("std").testing.allocator;

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

    var desc_layout = try device.initDescLayout(.{
        .entries = &[4]DescLayout.Entry{
            .{
                .binding = 2,
                .descriptor = .dynamic_uniform_buffer,
                .count = 1,
                .visibility = .{ .vertex = true, .fragment = true },
            },
            .{
                .binding = 0,
                .descriptor = .sampled_texture,
                .count = 3,
                .visibility = .{ .fragment = true },
            },
            .{
                .binding = 1,
                .descriptor = .sampler,
                .count = 2,
                .visibility = .{ .fragment = true },
            },
            .{
                .binding = 3,
                .descriptor = .storage_texture,
                .count = 1,
                .visibility = .{ .compute = true },
            },
        },
    });
    defer desc_layout.deinit();

    var desc_pool = try device.initDescPool(.{
        .max_sets = 75,
        .size = .{
            .sampled_texture = 225,
            .sampler = 150,
            .dynamic_uniform_buffer = 300,
            .storage_texture = 12,
        },
    });
    defer desc_pool.deinit();

    var desc_sets = try desc_pool.allocSets(allocator, &[2]DescSet.Config{ .{
        .layout = &desc_layout,
        .count = 15,
    }, .{
        .layout = &desc_layout,
        .count = 1,
    } });
    defer {
        for (desc_sets) |*set| {
            set.free();
        }
        allocator.free(desc_sets);
    }

    var shader_code = try device.initShaderCode(.{ .code = "" });
    defer shader_code.deinit();

    var ps_layout = try device.initPsLayout(.{
        .desc_layouts = &[1]*DescLayout{&desc_layout},
        .constants = &[1]PsLayout.Constant{.{
            .offset = 0,
            .size = 4,
            .visibility = .{ .vertex = true },
        }},
    });
    defer ps_layout.deinit();

    var render = try device.initPipeline(.{
        .layout = &ps_layout,
        .state = .{ .render = &Pipeline.RenderPs{
            .vs = .{ .code = &shader_code },
            .fs = null,
            .input = &.{},
            .raster = null,
            .ds = null,
            .blend = null,
            .color_formats = &.{},
            .ds_format = null,
        } },
    });
    defer render.deinit();

    var compute = try device.initPipeline(.{
        .layout = &ps_layout,
        .state = .{ .compute = &Pipeline.ComputePs{
            .cs = .{ .code = &shader_code },
        } },
    });
    defer compute.deinit();

    var cmd_pool = try device.initCmdPool(.{});
    defer cmd_pool.deinit();

    var cmd_buffers = try cmd_pool.allocBuffers(allocator, &[3]CmdBuffer.Config{
        .{ .kind = .direct },
        .{ .kind = .indirect },
        .{ .kind = .indirect },
    });
    defer {
        for (cmd_buffers) |*cbuf| {
            cbuf.free();
        }
        allocator.free(cmd_buffers);
    }
}
