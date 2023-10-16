const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;
const context = @import("test.zig").context;

test "Sampler.init/deinit" {
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

    var tri = try ngl.Sampler.init(gpa, dev, .{
        .normalized_coordinates = true,
        .u_address = .clamp_to_edge,
        .v_address = .clamp_to_edge,
        .w_address = .repeat,
        .border_color = null,
        .mag = .linear,
        .min = .linear,
        .mipmap = .linear,
        .min_lod = 0,
        .max_lod = null,
        .max_anisotropy = null,
        .compare = null,
    });
    tri.deinit(gpa, dev);

    var shdw = try ngl.Sampler.init(gpa, dev, .{
        .normalized_coordinates = true,
        .u_address = .clamp_to_border,
        .v_address = .clamp_to_border,
        .w_address = .clamp_to_border,
        .border_color = .opaque_white_float,
        .mag = .linear,
        .min = .linear,
        .mipmap = .nearest,
        .min_lod = 0,
        .max_lod = null,
        .max_anisotropy = null,
        .compare = .less,
    });
    shdw.deinit(gpa, dev);
}
