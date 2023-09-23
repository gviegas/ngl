const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;

pub const RenderPass = struct {
    handle: c.VkRenderPass,

    pub inline fn cast(impl: *Impl.RenderPass) *RenderPass {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.RenderPass.Desc,
    ) Error!*Impl.RenderPass {
        const dev = Device.cast(device);

        var ptr = try allocator.create(RenderPass);
        errdefer allocator.destroy(ptr);

        // TODO
        _ = desc;
        _ = dev;

        var rp: c.VkRenderPass = undefined;
        //try conv.check(dev.vkCreateRenderPass(&.{
        //    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        //    .pNext = null,
        //    .flags = 0,
        //}, null, &rp));

        ptr.* = .{ .handle = rp };
        //return @ptrCast(ptr);
        return Error.Other;
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        render_pass: *Impl.RenderPass,
    ) void {
        const dev = Device.cast(device);
        const rp = cast(render_pass);
        dev.vkDestroyRenderPass(rp.handle, null);
        allocator.destroy(rp);
    }
};
