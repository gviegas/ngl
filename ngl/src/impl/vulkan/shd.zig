const std = @import("std");

//const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
//const conv = @import("conv.zig");
//const null_handle = conv.null_handle;
//const check = conv.check;
//const Device = @import("init.zig").Device;

// TODO
pub const Shader = packed struct {
    handle: void,

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descs: []const ngl.Shader.Desc,
        shaders: []Error!ngl.Shader,
    ) Error!void {
        _ = allocator;
        _ = device;
        _ = descs;
        _ = shaders;
        @panic("Not yet implemented");
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        shader: Impl.Shader,
    ) void {
        _ = allocator;
        _ = device;
        _ = shader;
        @panic("Not yet implemented");
    }
};
