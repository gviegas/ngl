const std = @import("std");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const Device = @import("init.zig").Device;
const DescriptorSetLayout = @import("desc.zig").DescriptorSetLayout;

pub const Shader = packed union {
    handle: c.VkShaderEXT,
    compat: *Compat,

    const Compat = struct {
        module: c.VkShaderModule,
        set_layouts: []const c.VkDescriptorSetLayout,
        push_constants: []const c.VkPushConstantRange,
        specialization: ?c.VkSpecializationInfo,

        fn init(
            allocator: std.mem.Allocator,
            device: *Device,
            descs: []const ngl.Shader.Desc,
            shaders: []Error!ngl.Shader,
        ) Error!void {
            for (shaders, descs) |*shader, desc| {
                var self = allocator.create(Compat) catch |err| {
                    shader.* = err;
                    continue;
                };
                // `deinit` is aware of this.
                self.* = .{
                    .module = null_handle,
                    .set_layouts = &.{},
                    .push_constants = &.{},
                    .specialization = null,
                };

                check(device.vkCreateShaderModule(&.{
                    .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .codeSize = desc.code.len,
                    .pCode = @ptrCast(desc.code.ptr),
                }, null, &self.module)) catch |err| {
                    self.deinit(allocator, device);
                    shader.* = err;
                    continue;
                };

                self.set_layouts = blk: {
                    const n = desc.set_layouts.len;
                    if (n == 0) break :blk &.{};
                    const set_layts = allocator.alloc(c.VkDescriptorSetLayout, n) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    for (set_layts, desc.set_layouts) |*dest, src|
                        dest.* = DescriptorSetLayout.cast(src.impl).handle;
                    break :blk set_layts;
                };

                self.push_constants = blk: {
                    const n = desc.push_constants.len;
                    if (n == 0) break :blk &.{};
                    const push_consts = allocator.alloc(c.VkPushConstantRange, n) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    for (push_consts, desc.push_constants) |*dest, src|
                        dest.* = .{
                            // TODO: Should be `Shader.Type.Flags`.
                            .stageFlags = conv.toVkShaderStageFlags(src.stage_mask),
                            .offset = src.offset,
                            .size = src.size,
                        };
                    break :blk push_consts;
                };

                self.specialization = blk: {
                    const spec = &(desc.specialization orelse break :blk null);
                    const const_n = spec.constants.len;
                    const data_n = spec.data.len;
                    // TODO: Validate this elsewhere.
                    if (const_n == 0 or data_n == 0) break :blk null;
                    const entries = allocator.alloc(
                        c.VkSpecializationMapEntry,
                        const_n,
                    ) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    for (entries, spec.constants) |*entry, sconst|
                        entry.* = .{
                            .constantID = sconst.id,
                            .offset = sconst.offset,
                            .size = sconst.size,
                        };
                    const data = allocator.alloc(u8, data_n) catch |err| {
                        allocator.free(entries);
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    @memcpy(data, spec.data);
                    break :blk .{
                        .mapEntryCount = @intCast(const_n),
                        .pMapEntries = entries.ptr,
                        .dataSize = data_n,
                        .pData = data.ptr,
                    };
                };

                shader.* = .{ .impl = .{ .val = @bitCast(Shader{ .compat = self }) } };
            }
        }

        fn deinit(self: *Compat, allocator: std.mem.Allocator, device: *Device) void {
            device.vkDestroyShaderModule(self.module, null);
            if (self.set_layouts.len > 0) allocator.free(self.set_layouts);
            if (self.push_constants.len > 0) allocator.free(self.push_constants);
            if (self.specialization) |x| {
                allocator.free(x.pMapEntries[0..x.mapEntryCount]);
                allocator.free(@as([*]const u8, @ptrCast(x.pData))[0..x.dataSize]);
            }
            allocator.destroy(self);
        }
    };

    // TODO
    pub inline fn compat(device: *Device) bool {
        _ = device;
        return true;
    }

    pub inline fn cast(impl: Impl.Shader) Shader {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descs: []const ngl.Shader.Desc,
        shaders: []Error!ngl.Shader,
    ) Error!void {
        const dev = Device.cast(device);

        if (compat(dev))
            try Compat.init(allocator, dev, descs, shaders)
        else
            @panic("Not yet implemented");
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        shader: Impl.Shader,
    ) void {
        const dev = Device.cast(device);
        const shd = cast(shader);

        if (compat(dev)) shd.compat.deinit(allocator, dev) else @panic("Not yet implemented");
    }
};
