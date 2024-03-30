const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "DescriptorPool.init/deinit" {
    const dev = &context().device;

    var desc_pool = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{ .sampler = 1, .sampled_image = 1 },
    });
    desc_pool.deinit(gpa, dev);

    var desc_pool_2 = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 1,
        .pool_size = .{
            .sampler = 3,
            .sampled_image = 5,
            .uniform_buffer = 1,
            .input_attachment = 1,
        },
    });
    defer desc_pool_2.deinit(gpa, dev);

    var desc_pool_3 = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 16,
        .pool_size = .{
            .combined_image_sampler = 20,
            .uniform_buffer = 16,
            .storage_buffer = 4,
            .input_attachment = 2,
        },
    });
    defer desc_pool_3.deinit(gpa, dev);

    var desc_pool_4 = try ngl.DescriptorPool.init(gpa, dev, .{
        .max_sets = 50,
        .pool_size = .{
            .sampler = 14,
            .combined_image_sampler = 30,
            .sampled_image = 25,
            .storage_image = 4,
            .uniform_texel_buffer = 3,
            .storage_texel_buffer = 3,
            .uniform_buffer = 75,
            .storage_buffer = 8,
            .input_attachment = 12,
        },
    });
    desc_pool_4.deinit(gpa, dev);
}

test "DescriptorPool.alloc/reset" {
    const dev = &context().device;

    const stage_mask = ngl.ShaderStage.Flags{
        .vertex = true,
        .fragment = true,
        .compute = true,
    };

    var layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .sampler,
            .count = 1,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
        .{
            .binding = 1,
            .type = .sampled_image,
            .count = 1,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
        .{
            .binding = 2,
            .type = .uniform_buffer,
            .count = 1,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
    } });
    defer layt.deinit(gpa, dev);

    var layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .storage_image,
        .count = 12,
        .stage_mask = stage_mask,
        .immutable_samplers = null,
    }} });
    defer layt_2.deinit(gpa, dev);

    var layt_3 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 10,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
        .{
            .binding = 0,
            .type = .uniform_buffer,
            .count = 8,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
    } });
    defer layt_3.deinit(gpa, dev);

    const size = ngl.DescriptorPool.PoolSize{
        .sampler = 1 + 0 + 0,
        .combined_image_sampler = 0 + 0 + 10,
        .sampled_image = 1 + 0 + 0,
        .storage_image = 0 + 12 + 0,
        .uniform_texel_buffer = 0 + 0 + 0,
        .storage_texel_buffer = 0 + 0 + 0,
        .uniform_buffer = 1 + 0 + 8,
        .storage_buffer = 0 + 0 + 0,
        .input_attachment = 0 + 0 + 0,
    };

    var pool = try ngl.DescriptorPool.init(gpa, dev, .{ .max_sets = 3, .pool_size = size });
    defer pool.deinit(gpa, dev);

    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_2} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} }));

    // This isn't guaranteed to fail.
    if (pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} })) |set|
        gpa.free(set)
    else |err| switch (err) {
        ngl.Error.OutOfMemory => {},
        else => try testing.expect(false),
    }

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_2} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_2} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{ &layt, &layt_2 } }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_3} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{
        &layt,
        &layt_3,
        &layt_2,
    } }));

    var layt_4 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 3,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
        .{
            .binding = 0,
            .type = .uniform_buffer,
            .count = 3,
            .stage_mask = stage_mask,
            .immutable_samplers = null,
        },
    } });
    defer layt_4.deinit(gpa, dev);

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{
        &layt_4,
        &layt_4,
        &layt_4,
    } }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_4} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_4} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_4} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{ &layt_4, &layt_4 } }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_4} }));

    try pool.reset(dev);
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{&layt_2} }));
    gpa.free(try pool.alloc(gpa, dev, .{ .layouts = &.{
        &layt_4,
        &layt_4,
        &layt,
    } }));
}
