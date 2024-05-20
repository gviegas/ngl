const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../../inc.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const Device = @import("init.zig").Device;
const Buffer = @import("res.zig").Buffer;
const BufferView = @import("res.zig").BufferView;
const ImageView = @import("res.zig").ImageView;
const Sampler = @import("res.zig").Sampler;

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
                            .stageFlags = conv.toVkShaderStageFlags(src.shader_mask),
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

pub const ShaderLayout = packed struct {
    handle: c.VkPipelineLayout,

    pub fn cast(impl: Impl.ShaderLayout) ShaderLayout {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.ShaderLayout.Desc,
    ) Error!Impl.ShaderLayout {
        const set_layt_n: u32 = @intCast(desc.set_layouts.len);
        const set_layts: []c.VkDescriptorSetLayout = blk: {
            if (set_layt_n == 0) break :blk &.{};
            const s = try allocator.alloc(c.VkDescriptorSetLayout, set_layt_n);
            for (s, desc.set_layouts) |*handle, set_layt|
                handle.* = DescriptorSetLayout.cast(set_layt.impl).handle;
            break :blk s;
        };
        defer if (set_layt_n > 0) allocator.free(set_layts);

        const push_const_n: u32 = @intCast(desc.push_constants.len);
        const push_consts: []c.VkPushConstantRange = blk: {
            if (push_const_n == 0) break :blk &.{};
            const s = try allocator.alloc(c.VkPushConstantRange, push_const_n);
            for (s, desc.push_constants) |*vk_push_const, push_const|
                vk_push_const.* = .{
                    .stageFlags = conv.toVkShaderStageFlags(push_const.shader_mask),
                    .offset = push_const.offset,
                    .size = push_const.size,
                };
            break :blk s;
        };
        defer if (push_const_n > 0) allocator.free(push_consts);

        var pl_layt: c.VkPipelineLayout = undefined;
        try check(Device.cast(device).vkCreatePipelineLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = set_layt_n,
            .pSetLayouts = if (set_layts.len > 0) set_layts.ptr else null,
            .pushConstantRangeCount = push_const_n,
            .pPushConstantRanges = if (push_consts.len > 0) push_consts.ptr else null,
        }, null, &pl_layt));

        return .{ .val = @bitCast(ShaderLayout{ .handle = pl_layt }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        shader_layout: Impl.ShaderLayout,
    ) void {
        Device.cast(device).vkDestroyPipelineLayout(cast(shader_layout).handle, null);
    }
};

pub const DescriptorSetLayout = packed struct {
    handle: c.VkDescriptorSetLayout,

    pub fn cast(impl: Impl.DescriptorSetLayout) DescriptorSetLayout {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!Impl.DescriptorSetLayout {
        const bind_n: u32 = @intCast(desc.bindings.len);
        var binds: []c.VkDescriptorSetLayoutBinding = &.{};
        var splrs: []c.VkSampler = &.{};
        if (bind_n > 0) {
            binds = try allocator.alloc(c.VkDescriptorSetLayoutBinding, bind_n);
            errdefer allocator.free(binds);
            var splr_n: usize = 0;
            for (desc.bindings) |bind|
                splr_n += bind.immutable_samplers.len;
            var splrs_ptr: [*]c.VkSampler = undefined;
            if (splr_n > 0) {
                splrs = try allocator.alloc(c.VkSampler, splr_n);
                splrs_ptr = splrs.ptr;
            }
            for (binds, desc.bindings) |*vk_bind, bind|
                vk_bind.* = .{
                    .binding = bind.binding,
                    .descriptorType = conv.toVkDescriptorType(bind.type),
                    .descriptorCount = bind.count,
                    .stageFlags = conv.toVkShaderStageFlags(bind.shader_mask),
                    .pImmutableSamplers = blk: {
                        const n = bind.immutable_samplers.len;
                        if (n == 0) break :blk null;
                        for (splrs_ptr[0..n], bind.immutable_samplers) |*vk_splr, splr|
                            vk_splr.* = Sampler.cast(splr.impl).handle;
                        splrs_ptr += n;
                        break :blk splrs_ptr - n;
                    },
                };
        }
        defer if (binds.len > 0) allocator.free(binds);
        defer if (splrs.len > 0) allocator.free(splrs);

        var set_layt: c.VkDescriptorSetLayout = undefined;
        try check(Device.cast(device).vkCreateDescriptorSetLayout(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = bind_n,
            .pBindings = if (bind_n > 0) binds.ptr else null,
        }, null, &set_layt));

        return .{ .val = @bitCast(DescriptorSetLayout{ .handle = set_layt }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        descriptor_set_layout: Impl.DescriptorSetLayout,
    ) void {
        Device.cast(device).vkDestroyDescriptorSetLayout(cast(descriptor_set_layout).handle, null);
    }
};

pub const DescriptorPool = packed struct {
    handle: c.VkDescriptorPool,

    pub fn cast(impl: Impl.DescriptorPool) DescriptorPool {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!Impl.DescriptorPool {
        const max_type = @typeInfo(ngl.DescriptorType).Enum.fields.len;
        var pool_sizes: [max_type]c.VkDescriptorPoolSize = undefined;
        const pool_size_n = blk: {
            var n: u32 = 0;
            inline for (@typeInfo(ngl.DescriptorPool.PoolSize).Struct.fields) |f| {
                const size = @field(desc.pool_size, f.name);
                if (size > 0) {
                    pool_sizes[n] = .{
                        .type = conv.toVkDescriptorType(@field(ngl.DescriptorType, f.name)),
                        .descriptorCount = size,
                    };
                    n += 1;
                }
            }
            break :blk n;
        };

        var desc_pool: c.VkDescriptorPool = undefined;
        try check(Device.cast(device).vkCreateDescriptorPool(&.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .maxSets = desc.max_sets,
            .poolSizeCount = pool_size_n,
            .pPoolSizes = if (pool_size_n > 0) pool_sizes[0..].ptr else null,
        }, null, &desc_pool));

        return .{ .val = @bitCast(DescriptorPool{ .handle = desc_pool }) };
    }

    pub fn alloc(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void {
        const set_layts = try allocator.alloc(c.VkDescriptorSetLayout, desc.layouts.len);
        defer allocator.free(set_layts);
        for (set_layts, desc.layouts) |*handle, layout|
            handle.* = DescriptorSetLayout.cast(layout.impl).handle;

        const handles = try allocator.alloc(c.VkDescriptorSet, desc.layouts.len);
        defer allocator.free(handles);

        const alloc_info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = cast(descriptor_pool).handle,
            .descriptorSetCount = @intCast(set_layts.len),
            .pSetLayouts = set_layts.ptr,
        };

        try check(Device.cast(device).vkAllocateDescriptorSets(&alloc_info, handles.ptr));

        for (descriptor_sets, handles) |*set, handle|
            set.impl = .{ .val = @bitCast(DescriptorSet{ .handle = handle }) };
    }

    pub fn reset(
        _: *anyopaque,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
    ) Error!void {
        // Unused in v1.3.
        const flags: c.VkDescriptorPoolResetFlags = 0;
        try check(Device.cast(device).vkResetDescriptorPool(cast(descriptor_pool).handle, flags));
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        descriptor_pool: Impl.DescriptorPool,
    ) void {
        Device.cast(device).vkDestroyDescriptorPool(cast(descriptor_pool).handle, null);
    }
};

pub const DescriptorSet = packed struct {
    handle: c.VkDescriptorSet,

    pub fn cast(impl: Impl.DescriptorSet) DescriptorSet {
        return @bitCast(impl.val);
    }

    pub fn write(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        writes: []const ngl.DescriptorSet.Write,
    ) Error!void {
        const desc_set_writes = try allocator.alloc(c.VkWriteDescriptorSet, writes.len);
        defer allocator.free(desc_set_writes);

        var img_infos: []c.VkDescriptorImageInfo = undefined;
        var buf_infos: []c.VkDescriptorBufferInfo = undefined;
        var buf_views: []c.VkBufferView = undefined;
        {
            var img_info_n: usize = 0;
            var buf_info_n: usize = 0;
            var buf_view_n: usize = 0;
            for (writes) |w| {
                switch (w.contents) {
                    .sampler => |x| img_info_n += x.len,
                    .combined_image_sampler => |x| img_info_n += x.len,
                    .sampled_image,
                    .storage_image,
                    //.input_attachment,
                    => |x| img_info_n += x.len,

                    .uniform_texel_buffer,
                    .storage_texel_buffer,
                    => |x| buf_view_n += x.len,

                    .uniform_buffer,
                    .storage_buffer,
                    => |x| buf_info_n += x.len,
                }
            }

            img_infos = if (img_info_n > 0) try allocator.alloc(
                c.VkDescriptorImageInfo,
                img_info_n,
            ) else &.{};
            errdefer if (img_infos.len > 0) allocator.free(img_infos);

            buf_infos = if (buf_info_n > 0) try allocator.alloc(
                c.VkDescriptorBufferInfo,
                buf_info_n,
            ) else &.{};
            errdefer if (buf_infos.len > 0) allocator.free(buf_infos);

            buf_views = if (buf_view_n > 0) try allocator.alloc(
                c.VkBufferView,
                buf_view_n,
            ) else &.{};
        }
        defer if (img_infos.len > 0) allocator.free(img_infos);
        defer if (buf_infos.len > 0) allocator.free(buf_infos);
        defer if (buf_views.len > 0) allocator.free(buf_views);

        var img_infos_ptr = img_infos.ptr;
        var buf_infos_ptr = buf_infos.ptr;
        var buf_views_ptr = buf_views.ptr;

        for (desc_set_writes, writes) |*dsw, w| {
            dsw.* = .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = cast(w.descriptor_set.impl).handle,
                .dstBinding = w.binding,
                .dstArrayElement = w.element,
                .descriptorCount = undefined, // Set below.
                .descriptorType = conv.toVkDescriptorType(w.contents),
                .pImageInfo = undefined, // Set below.
                .pBufferInfo = undefined, // Set below.
                .pTexelBufferView = undefined, // Set below.
            };

            switch (w.contents) {
                .sampler => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, splr|
                        info.* = .{
                            .sampler = Sampler.cast(splr.impl).handle,
                            .imageView = null_handle,
                            .imageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                        };
                    img_infos_ptr += x.len;
                },

                .combined_image_sampler => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, img_splr|
                        info.* = .{
                            .sampler = if (img_splr.sampler) |s|
                                Sampler.cast(s.impl).handle
                            else
                                null_handle,
                            .imageView = ImageView.cast(img_splr.view.impl).handle,
                            .imageLayout = conv.toVkImageLayout(img_splr.layout),
                        };
                    img_infos_ptr += x.len;
                },

                .sampled_image,
                .storage_image,
                //.input_attachment,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = img_infos_ptr;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = null;
                    for (img_infos_ptr, x) |*info, image|
                        info.* = .{
                            .sampler = null_handle,
                            .imageView = ImageView.cast(image.view.impl).handle,
                            .imageLayout = conv.toVkImageLayout(image.layout),
                        };
                    img_infos_ptr += x.len;
                },

                .uniform_texel_buffer,
                .storage_texel_buffer,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = null;
                    dsw.pBufferInfo = null;
                    dsw.pTexelBufferView = buf_views_ptr;
                    for (buf_views_ptr, x) |*handle, view|
                        handle.* = BufferView.cast(view.impl).handle;
                    buf_views_ptr += x.len;
                },

                .uniform_buffer,
                .storage_buffer,
                => |x| {
                    dsw.descriptorCount = @intCast(x.len);
                    dsw.pImageInfo = null;
                    dsw.pBufferInfo = buf_infos_ptr;
                    dsw.pTexelBufferView = null;
                    for (buf_infos_ptr, x) |*info, buf|
                        info.* = .{
                            .buffer = Buffer.cast(buf.buffer.impl).handle,
                            .offset = buf.offset,
                            .range = buf.range,
                        };
                    buf_infos_ptr += x.len;
                },
            }
        }

        Device.cast(device).vkUpdateDescriptorSets(
            @intCast(desc_set_writes.len),
            desc_set_writes.ptr,
            0,
            null,
        );
    }
};
