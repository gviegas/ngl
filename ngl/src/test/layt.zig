const std = @import("std");

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "DescriptorSetLayout and PipelineLayout" {
    const dev = &context().device;

    var splr = try ngl.Sampler.init(gpa, dev, .{
        .normalized_coordinates = true,
        .u_address = .repeat,
        .v_address = .repeat,
        .w_address = .repeat,
        .border_color = null,
        .mag = .nearest,
        .min = .nearest,
        .mipmap = .nearest,
        .min_lod = 0,
        .max_lod = null,
        .max_anisotropy = null,
        .compare = null,
    });
    defer splr.deinit(gpa, dev);

    var set_layt = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{
        .{
            .binding = 0,
            .type = .sampler,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = null,
        },
        .{
            .binding = 1,
            .type = .sampled_image,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = null,
        },
        .{
            .binding = 2,
            .type = .uniform_buffer,
            .count = 1,
            .stage_mask = .{ .vertex = true, .fragment = true },
            .immutable_samplers = null,
        },
    } });
    defer set_layt.deinit(gpa, dev);

    var set_layt_2 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
        .binding = 0,
        .type = .combined_image_sampler,
        .count = 3,
        .stage_mask = .{ .fragment = true },
        .immutable_samplers = &.{ &splr, &splr, &splr },
    }} });
    defer set_layt_2.deinit(gpa, dev);

    var pl_layt = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{&set_layt},
        .push_constant_ranges = null,
    });
    defer pl_layt.deinit(gpa, dev);

    var pl_layt_2 = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = &.{ &set_layt_2, &set_layt },
        .push_constant_ranges = &.{.{
            .offset = 0,
            .size = 64,
            .stage_mask = .{ .vertex = true },
        }},
    });
    defer pl_layt_2.deinit(gpa, dev);

    var pl_layt_3 = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = null,
        .push_constant_ranges = &.{
            .{
                .offset = 16,
                .size = 8,
                .stage_mask = .{ .fragment = true, .compute = true },
            },
            .{
                .offset = 32,
                .size = 64,
                .stage_mask = .{ .compute = true },
            },
            .{
                .offset = 0,
                .size = 16,
                .stage_mask = .{
                    .vertex = true,
                    .fragment = true,
                    .compute = true,
                },
            },
        },
    });
    defer pl_layt_3.deinit(gpa, dev);

    // Needn't use any shader resources at all.
    var pl_layt_4 = try ngl.PipelineLayout.init(gpa, dev, .{
        .descriptor_set_layouts = null,
        .push_constant_ranges = null,
    });
    defer pl_layt_4.deinit(gpa, dev);

    {
        var set_layt_3 = try ngl.DescriptorSetLayout.init(gpa, dev, .{ .bindings = &.{.{
            .binding = 0,
            .type = .storage_image,
            .count = 1,
            .stage_mask = .{ .compute = true },
            .immutable_samplers = null,
        }} });

        var pl_layt_5 = ngl.PipelineLayout.init(gpa, dev, .{
            .descriptor_set_layouts = &.{&set_layt_3},
            .push_constant_ranges = null,
        }) catch |err| {
            set_layt_3.deinit(gpa, dev);
            return err;
        };

        // Shouldn't retain the set layouts.
        // TODO: Try doing this during command recording.
        set_layt_3.deinit(gpa, dev);
        pl_layt_5.deinit(gpa, dev);
    }
}
