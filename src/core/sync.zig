const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const PipelineStage = enum {
    none,
    all_commands,
    all_graphics,
    all_transfer,
    draw_indirect,
    index_input,
    vertex_attribute_input,
    vertex_shader,
    early_fragment_tests,
    fragment_shader,
    late_fragment_tests,
    color_attachment_output,
    dispatch_indirect,
    compute_shader,
    clear,
    copy,
    blit,

    pub const Flags = ngl.Flags(PipelineStage);
};

pub const Access = enum {
    none,
    memory_read,
    memory_write,
    indirect_command_read,
    index_read,
    vertex_attribute_read,
    uniform_read,
    input_attachment_read,
    shader_sampled_read,
    shader_storage_read,
    shader_storage_write,
    color_attachment_read,
    color_attachment_write,
    depth_stencil_attachment_read,
    depth_stencil_attachment_write,
    transfer_read,
    transfer_write,

    pub const Flags = ngl.Flags(Access);
};

pub const Fence = struct {
    impl: *Impl.Fence,

    pub const Desc = struct {
        signaled: bool = false,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initFence(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitFence(allocator, device.impl, self.impl);
    }
};
