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
        name: union(enum) {
            array: switch (@sizeOf(usize)) {
                8 => [22:0]u8,
                else => [10:0]u8,
            },
            slice: [:0]const u8,
        },
        // TODO: Currently, the only use of `set_layouts` and
        // `push_constants` is in `pipeline_layout`'s creation.
        set_layouts: []const c.VkDescriptorSetLayout,
        push_constants: []const c.VkPushConstantRange,
        // Will be `null_handle` for fragment shaders.
        // TODO: Consider caching this, or change the API so
        // it's passed in the description.
        pipeline_layout: c.VkPipelineLayout,
        specialization: ?c.VkSpecializationInfo,
        // Will be `null_handle` for non-compute shaders.
        // TODO: Use an union to save some space.
        pipeline: c.VkPipeline,

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
                    .name = .{ .array = undefined },
                    .set_layouts = &.{},
                    .push_constants = &.{},
                    .pipeline_layout = null_handle,
                    .specialization = null,
                    .pipeline = null_handle,
                };

                self.module = blk: {
                    var mod: c.VkShaderModule = undefined;
                    check(device.vkCreateShaderModule(&.{
                        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .codeSize = desc.code.len,
                        .pCode = @ptrCast(desc.code.ptr),
                    }, null, &mod)) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    break :blk mod;
                };

                self.name = blk: {
                    if (desc.name.len <= self.name.array.len) {
                        var name: @TypeOf(self.name.array) = undefined;
                        @memcpy(name[0..desc.name.len], desc.name);
                        @memset(name[desc.name.len..], 0);
                        break :blk .{ .array = name };
                    }
                    const name = allocator.allocSentinel(u8, desc.name.len, 0) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    @memcpy(name, desc.name);
                    break :blk .{ .slice = name };
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

                self.pipeline_layout = blk: {
                    if (desc.type == .fragment) break :blk null_handle;
                    var pl_layt: c.VkPipelineLayout = undefined;
                    check(device.vkCreatePipelineLayout(&.{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .setLayoutCount = @intCast(self.set_layouts.len),
                        .pSetLayouts = if (self.set_layouts.len > 0)
                            self.set_layouts.ptr
                        else
                            null,
                        .pushConstantRangeCount = @intCast(self.push_constants.len),
                        .pPushConstantRanges = if (self.push_constants.len > 0)
                            self.push_constants.ptr
                        else
                            null,
                    }, null, &pl_layt)) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    break :blk pl_layt;
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

                self.pipeline = blk: {
                    if (desc.type != .compute) break :blk null_handle;
                    var pl: [1]c.VkPipeline = undefined;
                    // TODO: Use `VkPipelineCache`.
                    check(device.vkCreateComputePipelines(null_handle, 1, &.{.{
                        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .stage = .{
                            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                            .pNext = null,
                            .flags = 0,
                            .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
                            .module = self.module,
                            .pName = switch (self.name) {
                                .array => |*x| x.ptr,
                                .slice => |*x| x.ptr,
                            },
                            .pSpecializationInfo = if (self.specialization) |*x| x else null,
                        },
                        .layout = self.pipeline_layout,
                        .basePipelineHandle = null_handle,
                        .basePipelineIndex = -1,
                    }}, null, &pl)) catch |err| {
                        self.deinit(allocator, device);
                        shader.* = err;
                        continue;
                    };
                    break :blk pl[0];
                };

                shader.* = .{ .impl = .{ .val = @bitCast(Shader{ .compat = self }) } };
            }
        }

        fn deinit(self: *Compat, allocator: std.mem.Allocator, device: *Device) void {
            device.vkDestroyShaderModule(self.module, null);
            switch (self.name) {
                .array => {},
                .slice => |s| allocator.free(s),
            }
            if (self.set_layouts.len > 0) allocator.free(self.set_layouts);
            if (self.push_constants.len > 0) allocator.free(self.push_constants);
            device.vkDestroyPipelineLayout(self.pipeline_layout, null);
            if (self.specialization) |x| {
                allocator.free(x.pMapEntries[0..x.mapEntryCount]);
                allocator.free(@as([*]const u8, @ptrCast(x.pData))[0..x.dataSize]);
            }
            device.vkDestroyPipeline(self.pipeline, null);
            allocator.destroy(self);
        }
    };

    pub fn compat(device: *Device) bool {
        return !device.hasShaderObject();
    }

    pub fn cast(impl: Impl.Shader) Shader {
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
