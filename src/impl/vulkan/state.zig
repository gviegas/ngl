const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const Device = @import("init.zig").Device;

pub const Pipeline = struct {
    handle: c.VkPipeline,

    pub inline fn cast(impl: *Impl.Pipeline) *Pipeline {
        return @ptrCast(@alignCast(impl));
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline: *Impl.Pipeline,
        _: ngl.Pipeline.Type,
    ) void {
        const dev = Device.cast(device);
        const pl = cast(pipeline);
        dev.vkDestroyPipeline(pl.handle, null);
        allocator.destroy(pl);
    }
};
