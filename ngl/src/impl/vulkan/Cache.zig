const std = @import("std");
const builtin = @import("builtin");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const dyn = @import("../common/dyn.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const log = @import("init.zig").log;
const Device = @import("init.zig").Device;
const Dynamic = @import("cmd.zig").Dynamic;
const Shader = @import("shd.zig").Shader;
const ImageView = @import("res.zig").ImageView;

state: State = .{},
rendering: Rendering = .{},

fn ValueWithStamp(comptime T: type) type {
    return struct { T, u64 };
}

const State = struct {
    hash_map: std.HashMapUnmanaged(Key, Value, Context, 80) = .{},
    mutex: std.Thread.Mutex = .{},

    const Key = Dynamic;
    const Value = ValueWithStamp(c.VkPipeline);

    // It suffices that the pipeline be compatible with
    // the render pass instance.
    // Note that this is required even when using
    // dynamic rendering.
    // TODO: Try to refine this.
    const rendering_subset_mask = dyn.RenderingMask{
        .color_format = true,
        .color_samples = true,
        .depth_format = true,
        .depth_samples = true,
        .stencil_format = true,
        .stencil_samples = true,
        .view_mask = true,
    };

    const Context = struct {
        pub fn hash(_: @This(), d: Key) u64 {
            var hasher = std.hash.Wyhash.init(0);
            d.state.hash(&hasher);
            d.rendering.hashSubset(rendering_subset_mask, &hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), d: Key, e: Key) bool {
            return d.state.eql(e.state) and
                d.rendering.eqlSubset(rendering_subset_mask, e.rendering);
        }
    };

    fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
        var iter = self.hash_map.iterator();
        while (iter.next()) |kv| {
            kv.key_ptr.clear(allocator, device);
            device.vkDestroyPipeline(kv.value_ptr[0], null);
        }
        self.hash_map.deinit(allocator);
    }
};

const Rendering = struct {
    hash_map: std.HashMapUnmanaged(Key, Value, Context, 80) = .{},
    mutex: std.Thread.Mutex = .{},

    const Key = dyn.Rendering(Dynamic.rendering_mask);
    const Value = ValueWithStamp(c.VkRenderPass);

    const subset_mask = dyn.RenderingMask{
        .color_format = true,
        .color_samples = true,
        .color_layout = true,
        .color_op = true,
        .color_resolve_layout = true,
        .color_resolve_mode = true,
        .depth_format = true,
        .depth_samples = true,
        .depth_layout = true,
        .depth_op = true,
        .depth_resolve_layout = true,
        .depth_resolve_mode = true,
        .stencil_format = true,
        .stencil_samples = true,
        .stencil_layout = true,
        .stencil_op = true,
        .stencil_resolve_layout = true,
        .stencil_resolve_mode = true,
        .view_mask = true,
    };

    const Context = struct {
        pub fn hash(_: @This(), r: Key) u64 {
            var hasher = std.hash.Wyhash.init(0);
            r.hashSubset(subset_mask, &hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), r: Key, s: Key) bool {
            return r.eqlSubset(subset_mask, s);
        }
    };

    fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
        var iter = self.hash_map.iterator();
        while (iter.next()) |kv| {
            kv.key_ptr.clear(allocator);
            device.vkDestroyRenderPass(kv.value_ptr[0], null);
        }
        self.hash_map.deinit(allocator);
    }
};

// We won't cache this for the time being.
const Fbo = struct {
    const Key = dyn.Rendering(Dynamic.rendering_mask);

    const subset_mask = dyn.RenderingMask{
        .color_view = true,
        .color_resolve_view = true,
        .depth_view = true,
        .depth_resolve_view = true,
        .stencil_view = true,
        .stencil_resolve_view = true,
        .render_area_size = true,
        .layers = true,
    };
};

pub fn getPrimitivePipeline(
    self: *@This(),
    allocator: std.mem.Allocator,
    device: *Device,
    key: State.Key,
) Error!c.VkPipeline {
    self.state.mutex.lock();
    defer self.state.mutex.unlock();

    if (self.state.hash_map.get(key)) |val| return val[0];

    const pl = try createPrimitivePipeline(
        allocator,
        device,
        key,
        if (!device.hasDynamicRendering())
            try self.getRenderPass(allocator, device, key.rendering)
        else
            null_handle,
    );
    errdefer device.vkDestroyPipeline(pl, null);
    try self.state.hash_map.putNoClobber(allocator, try key.clone(allocator), .{ pl, 1 });
    return pl;
}

pub fn getRenderPass(
    self: *@This(),
    allocator: std.mem.Allocator,
    device: *Device,
    key: Rendering.Key,
) Error!c.VkRenderPass {
    self.rendering.mutex.lock();
    defer self.rendering.mutex.unlock();

    if (self.rendering.hash_map.get(key)) |val| return val[0];

    const rp = try createRenderPass(allocator, device, key);
    errdefer device.vkDestroyRenderPass(rp, null);
    try self.rendering.hash_map.putNoClobber(allocator, try key.clone(allocator), .{ rp, 1 });
    return rp;
}

pub fn createPrimitivePipeline(
    allocator: std.mem.Allocator,
    device: *Device,
    key: State.Key,
    render_pass: c.VkRenderPass,
) Error!c.VkPipeline {
    if (!builtin.is_test and device.isFullyDynamic()) unreachable;

    const state = &key.state;

    var layout: c.VkPipelineLayout = undefined;
    var stages_array: [2]c.VkPipelineShaderStageCreateInfo = undefined;
    const stages = blk: {
        const vert = Shader.cast(state.shaders.shader.vertex).compat;
        layout = vert.pipeline_layout;
        stages_array[0] = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert.module,
            .pName = switch (vert.name) {
                .array => |*x| x.ptr,
                .slice => |*x| x.ptr,
            },
            .pSpecializationInfo = if (vert.specialization) |*x| x else null,
        };
        const frag = if (state.shaders.shader.fragment.val != 0)
            Shader.cast(state.shaders.shader.fragment).compat
        else
            break :blk stages_array[0..1];
        stages_array[1] = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag.module,
            .pName = switch (frag.name) {
                .array => |*x| x.ptr,
                .slice => |*x| x.ptr,
            },
            .pSpecializationInfo = if (frag.specialization) |*x| x else null,
        };
        break :blk stages_array[0..2];
    };

    var input_binds: []c.VkVertexInputBindingDescription = &.{};
    var input_attrs: []c.VkVertexInputAttributeDescription = &.{};
    const input_bind_n = state.vertex_input.bindings.items.len;
    const input_attr_n = state.vertex_input.attributes.items.len;
    if (input_bind_n > 0 and input_attr_n > 0) {
        input_binds = try allocator.alloc(@TypeOf(input_binds[0]), input_bind_n);
        errdefer allocator.free(input_binds);
        input_attrs = try allocator.alloc(@TypeOf(input_attrs[0]), input_attr_n);
        errdefer allocator.free(input_attrs);
        for (state.vertex_input.bindings.items, input_binds) |bind, *desc|
            desc.* = .{
                .binding = bind.binding,
                .stride = bind.stride,
                .inputRate = conv.toVkVertexInputRate(bind.step_rate),
            };
        for (state.vertex_input.attributes.items, input_attrs) |attr, *desc|
            desc.* = .{
                .location = attr.location,
                .binding = attr.binding,
                .format = try conv.toVkFormat(attr.format),
                .offset = attr.offset,
            };
    }
    defer {
        if (input_bind_n > 0) allocator.free(input_binds);
        if (input_attr_n > 0) allocator.free(input_attrs);
    }
    const vert_input = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = @intCast(input_bind_n),
        .pVertexBindingDescriptions = if (input_bind_n > 0) input_binds.ptr else null,
        .vertexAttributeDescriptionCount = @intCast(input_attr_n),
        .pVertexAttributeDescriptions = if (input_attr_n > 0) input_attrs.ptr else null,
    };

    const ia = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = conv.toVkPrimitiveTopology(state.primitive_topology.topology),
        // TODO: Add a command for this.
        .primitiveRestartEnable = c.VK_FALSE,
    };

    // BUG: Need dynamic state for viewport/scissor rect count.
    const vport = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const raster = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        // TODO: Add a command for this.
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = if (state.rasterization_enable.enable) c.VK_FALSE else c.VK_TRUE,
        .polygonMode = conv.toVkPolygonMode(state.polygon_mode.polygon_mode),
        .cullMode = conv.toVkCullModeFlags(state.cull_mode.cull_mode),
        .frontFace = conv.toVkFrontFace(state.front_face.front_face),
        .depthBiasEnable = if (state.depth_bias_enable.enable) c.VK_TRUE else c.VK_FALSE,
        .depthBiasConstantFactor = 0,
        .depthBiasClamp = 0,
        .depthBiasSlopeFactor = 0,
        .lineWidth = 1,
    };

    if (@TypeOf(state.sample_mask.sample_mask) != u64) unreachable;
    const spl_mask = [2]c.VkSampleMask{
        @truncate(state.sample_mask.sample_mask),
        @truncate(state.sample_mask.sample_mask >> 32),
    };
    const ms = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = conv.toVkSampleCount(state.sample_count.sample_count),
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 0,
        .pSampleMask = &spl_mask,
        .alphaToCoverageEnable = c.VK_FALSE,
        // TODO: Add a command for this.
        .alphaToOneEnable = c.VK_FALSE,
    };

    const toVkStencilOpState = struct {
        fn do(from: @TypeOf(state.stencil_op).Op) c.VkStencilOpState {
            return .{
                .failOp = conv.toVkStencilOp(from.fail_op),
                .passOp = conv.toVkStencilOp(from.pass_op),
                .depthFailOp = conv.toVkStencilOp(from.depth_fail_op),
                .compareOp = conv.toVkCompareOp(from.compare_op),
                .compareMask = 0,
                .writeMask = 0,
                .reference = 0,
            };
        }
    }.do;
    const ds = c.VkPipelineDepthStencilStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthTestEnable = if (state.depth_test_enable.enable) c.VK_TRUE else c.VK_FALSE,
        .depthWriteEnable = if (state.depth_write_enable.enable) c.VK_TRUE else c.VK_FALSE,
        .depthCompareOp = if (state.depth_test_enable.enable)
            conv.toVkCompareOp(state.depth_compare_op.compare_op)
        else
            c.VK_COMPARE_OP_NEVER,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = if (state.stencil_test_enable.enable) c.VK_TRUE else c.VK_FALSE,
        .front = toVkStencilOpState(if (state.stencil_test_enable.enable)
            state.stencil_op.front
        else
            .{}),
        .back = toVkStencilOpState(if (state.stencil_test_enable.enable)
            state.stencil_op.back
        else
            .{}),
        .minDepthBounds = 0,
        .maxDepthBounds = 0,
    };

    const rendering = &key.rendering;

    const col_n = blk: {
        var n: u32 = 0;
        for (rendering.color_view.views) |view| {
            if (view.val == 0) break;
            n += 1;
        }
        break :blk n;
    };

    var attachs: [ngl.Cmd.max_color_attachment]c.VkPipelineColorBlendAttachmentState = undefined;
    for (
        attachs[0..col_n],
        state.color_blend_enable.enable[0..col_n],
        state.color_blend.blend[0..col_n],
        state.color_write.write_masks[0..col_n],
    ) |*attach, enable, blend, write_mask|
        attach.* = if (enable) .{
            .blendEnable = c.VK_TRUE,
            .srcColorBlendFactor = conv.toVkBlendFactor(blend.color_source_factor),
            .dstColorBlendFactor = conv.toVkBlendFactor(blend.color_dest_factor),
            .colorBlendOp = conv.toVkBlendOp(blend.color_op),
            .srcAlphaBlendFactor = conv.toVkBlendFactor(blend.alpha_source_factor),
            .dstAlphaBlendFactor = conv.toVkBlendFactor(blend.alpha_dest_factor),
            .alphaBlendOp = conv.toVkBlendOp(blend.alpha_op),
            .colorWriteMask = conv.toVkColorComponentFlags(write_mask),
        } else .{
            .blendEnable = c.VK_FALSE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = c.VK_BLEND_OP_ADD,
            .colorWriteMask = conv.toVkColorComponentFlags(write_mask),
        };
    const col_blend = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_NO_OP,
        .attachmentCount = col_n,
        .pAttachments = if (col_n > 0) &attachs else null,
        .blendConstants = .{ 0, 0, 0, 0 },
    };

    const dyn_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
        //c.VK_DYNAMIC_STATE_LINE_WIDTH, // Not exposed.
        c.VK_DYNAMIC_STATE_DEPTH_BIAS,
        c.VK_DYNAMIC_STATE_BLEND_CONSTANTS,
        //c.VK_DYNAMIC_STATE_DEPTH_BOUNDS, // Not exposed.
        c.VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK,
        c.VK_DYNAMIC_STATE_STENCIL_WRITE_MASK,
        c.VK_DYNAMIC_STATE_STENCIL_REFERENCE,
    };
    const dynamic = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = dyn_states.len,
        .pDynamicStates = &dyn_states,
    };

    const has_dynamic_rendering = device.hasDynamicRendering();
    var rend: c.VkPipelineRenderingCreateInfo = undefined;
    var col_fmts: [ngl.Cmd.max_color_attachment]c.VkFormat = undefined;
    if (has_dynamic_rendering) {
        for (rendering.color_format.formats[0..col_n], col_fmts[0..col_n]) |from, *to|
            to.* = try conv.toVkFormat(from);
        const dep_fmt = if (rendering.depth_format.format == .unknown)
            @as(c.VkFormat, c.VK_FORMAT_UNDEFINED)
        else
            try conv.toVkFormat(rendering.depth_format.format);
        const sten_fmt = blk: {
            if (rendering.stencil_format.format == .unknown)
                break :blk @as(c.VkFormat, c.VK_FORMAT_UNDEFINED);
            if (rendering.stencil_format.format == rendering.depth_format.format)
                break :blk dep_fmt;
            break :blk try conv.toVkFormat(rendering.stencil_format.format);
        };
        rend = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .pNext = null,
            .viewMask = rendering.view_mask.view_mask,
            .colorAttachmentCount = col_n,
            .pColorAttachmentFormats = if (col_n > 0) &col_fmts else null,
            .depthAttachmentFormat = dep_fmt,
            .stencilAttachmentFormat = sten_fmt,
        };
    }

    const create_info = [1]c.VkGraphicsPipelineCreateInfo{.{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = if (has_dynamic_rendering) &rend else null,
        .flags = 0,
        .stageCount = @intCast(stages.len),
        .pStages = stages.ptr,
        .pVertexInputState = &vert_input,
        .pInputAssemblyState = &ia,
        .pTessellationState = null,
        .pViewportState = &vport,
        .pRasterizationState = &raster,
        .pMultisampleState = &ms,
        .pDepthStencilState = &ds,
        .pColorBlendState = &col_blend,
        .pDynamicState = &dynamic,
        .layout = layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null_handle,
        .basePipelineIndex = -1,
    }};

    if (builtin.is_test)
        validatePrimitivePipeline(key, create_info[0]) catch return Error.Other;

    // TODO: Use `VkPipelineCache`.
    var pl: [1]c.VkPipeline = undefined;
    try check(device.vkCreateGraphicsPipelines(null_handle, 1, &create_info, null, &pl));
    return pl[0];
}

pub fn createRenderPass(
    _: std.mem.Allocator,
    device: *Device,
    key: Rendering.Key,
) Error!c.VkRenderPass {
    if (!builtin.is_test and device.hasDynamicRendering()) unreachable;

    const max_attach = ngl.Cmd.max_color_attachment * 2 + 2;
    var attachs = [_]c.VkAttachmentDescription{undefined} ** max_attach;
    var refs = [_]c.VkAttachmentReference{undefined} ** max_attach;

    // In case we decide to increase `Cmd.max_color_attachment`.
    if (@sizeOf(@TypeOf(attachs)) + @sizeOf(@TypeOf(refs)) >= 4096)
        @compileError("May want to allocate these in the heap");

    var attach_i: u32 = 0;

    // Only for references.
    const col_rv_off = ngl.Cmd.max_color_attachment;
    const ds_off = col_rv_off + ngl.Cmd.max_color_attachment;
    const ds_rv_off = ds_off + 1;

    const col_n = for (0..ngl.Cmd.max_color_attachment) |i| {
        if (key.color_format.formats[i] == .unknown)
            break i;

        const layt = conv.toVkImageLayout(key.color_layout.layouts[i]);
        attachs[attach_i] = .{
            .flags = 0,
            .format = try conv.toVkFormat(key.color_format.formats[i]),
            .samples = conv.toVkSampleCount(key.color_samples.sample_counts[i]),
            .loadOp = conv.toVkAttachmentLoadOp(key.color_op.load[i]),
            .storeOp = conv.toVkAttachmentStoreOp(key.color_op.store[i]),
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = layt,
            .finalLayout = layt,
        };
        refs[i] = .{
            .attachment = attach_i,
            .layout = layt,
        };
        attach_i += 1;

        if (key.color_resolve_layout.layouts[i] == .unknown) {
            refs[col_rv_off + i] = .{
                .attachment = c.VK_ATTACHMENT_UNUSED,
                .layout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            };
            continue;
        }

        const rv_layt = conv.toVkImageLayout(key.color_resolve_layout.layouts[i]);
        attachs[attach_i] = attachs[attach_i - 1];
        attachs[attach_i].samples = c.VK_SAMPLE_COUNT_1_BIT;
        attachs[attach_i].initialLayout = rv_layt;
        attachs[attach_i].finalLayout = rv_layt;
        refs[col_rv_off + i] = .{
            .attachment = attach_i,
            .layout = rv_layt,
        };
        attach_i += 1;
    } else ngl.Cmd.max_color_attachment;

    const ds: struct {
        format: ngl.Format,
        samples: ngl.SampleCount,
        layout: ngl.Image.Layout,
        rv_layout: ngl.Image.Layout,
    } = if (key.depth_format.format != .unknown) .{
        .format = key.depth_format.format,
        .samples = key.depth_samples.sample_count,
        .layout = key.depth_layout.layout,
        .rv_layout = key.depth_resolve_layout.layout,
    } else .{
        .format = key.stencil_format.format,
        .samples = key.stencil_samples.sample_count,
        .layout = key.stencil_layout.layout,
        .rv_layout = key.stencil_resolve_layout.layout,
    };

    if (ds.format != .unknown) {
        const layt = conv.toVkImageLayout(ds.layout);
        attachs[attach_i] = .{
            .flags = 0,
            .format = try conv.toVkFormat(ds.format),
            .samples = conv.toVkSampleCount(ds.samples),
            .loadOp = conv.toVkAttachmentLoadOp(key.depth_op.load),
            .storeOp = conv.toVkAttachmentStoreOp(key.depth_op.store),
            .stencilLoadOp = conv.toVkAttachmentLoadOp(key.stencil_op.load),
            .stencilStoreOp = conv.toVkAttachmentStoreOp(key.stencil_op.store),
            .initialLayout = layt,
            .finalLayout = layt,
        };
        refs[ds_off] = .{
            .attachment = attach_i,
            .layout = layt,
        };
        attach_i += 1;

        if (ds.rv_layout != .unknown) {
            const rv_layt = conv.toVkImageLayout(ds.rv_layout);
            attachs[attach_i] = attachs[attach_i - 1];
            attachs[attach_i].samples = c.VK_SAMPLE_COUNT_1_BIT;
            attachs[attach_i].initialLayout = rv_layt;
            attachs[attach_i].finalLayout = rv_layt;
            refs[ds_rv_off] = .{
                .attachment = attach_i,
                .layout = rv_layt,
            };
            attach_i += 1;
        }
    }

    // TODO: Depth/stencil resolve & resolve modes.
    if (ds.rv_layout != .unknown) {
        log.warn("Depth/stencil resolve not yet implemented", .{});
        return Error.NotSupported;
    }

    const create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = attach_i,
        .pAttachments = if (attach_i > 0) &attachs else null,
        .subpassCount = 1,
        .pSubpasses = &.{
            .flags = 0,
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .colorAttachmentCount = @intCast(col_n),
            .pColorAttachments = if (col_n != 0) &refs else null,
            .pResolveAttachments = if (col_n != 0) &refs[col_rv_off] else null,
            .pDepthStencilAttachment = if (ds.format != .unknown) &refs[ds_off] else null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
        },
        .dependencyCount = 0,
        .pDependencies = null,
    };

    if (builtin.is_test)
        validateRenderPass(key, create_info) catch return Error.Other;

    var rp: c.VkRenderPass = undefined;
    try check(device.vkCreateRenderPass(&create_info, null, &rp));
    return rp;
}

pub fn createFramebuffer(
    _: std.mem.Allocator,
    device: *Device,
    key: Fbo.Key,
    render_pass: c.VkRenderPass,
) Error!c.VkFramebuffer {
    if (!builtin.is_test and device.hasDynamicRendering()) unreachable;

    const max_attach = ngl.Cmd.max_color_attachment * 2 + 2;
    var attachs = [_]c.VkImageView{undefined} ** max_attach;

    var attach_i: u32 = 0;

    for (0..ngl.Cmd.max_color_attachment) |i| {
        if (key.color_format.formats[i] == .unknown)
            break;

        attachs[attach_i] = ImageView.cast(key.color_view.views[i]).handle;
        attach_i += 1;

        if (key.color_resolve_layout.layouts[i] != .unknown) {
            attachs[attach_i] = ImageView.cast(key.color_resolve_view.views[i]).handle;
            attach_i += 1;
        }
    }

    const ds: struct {
        view: c.VkImageView,
        rv_view: c.VkImageView,
    } = if (key.depth_format.format != .unknown) .{
        .view = ImageView.cast(key.depth_view.view).handle,
        .rv_view = if (key.depth_resolve_layout.layout != .unknown)
            ImageView.cast(key.depth_resolve_view.view).handle
        else
            null_handle,
    } else if (key.stencil_format.format != .unknown) .{
        .view = ImageView.cast(key.stencil_view.view).handle,
        .rv_view = if (key.stencil_resolve_layout.layout != .unknown)
            ImageView.cast(key.stencil_resolve_view.view).handle
        else
            null_handle,
    } else .{
        .view = null_handle,
        .rv_view = null_handle,
    };

    if (ds.view != null_handle) {
        attachs[attach_i] = ds.view;
        attach_i += 1;

        if (ds.rv_view != null_handle) {
            attachs[attach_i] = ds.rv_view;
            attach_i += 1;
        }
    }

    // TODO: Implement support for this in `createRenderPass`.
    if (ds.rv_view != null_handle) {
        log.warn("Depth/stencil resolve not yet implemented", .{});
        return Error.NotSupported;
    }

    const create_info = c.VkFramebufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .renderPass = render_pass,
        .attachmentCount = attach_i,
        .pAttachments = if (attach_i > 0) &attachs else null,
        .width = key.render_area_size.width,
        .height = key.render_area_size.height,
        .layers = key.layers.layers,
    };

    if (builtin.is_test)
        validateFramebuffer(key, create_info) catch return Error.Other;

    var fb: c.VkFramebuffer = undefined;
    try check(device.vkCreateFramebuffer(&create_info, null, &fb));
    return fb;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator, device: *Device) void {
    self.state.deinit(allocator, device);
    self.rendering.deinit(allocator, device);
}

const testing = std.testing;
const context = @import("../../test/test.zig").context;

test "Cache" {
    const dev = Device.cast(context().device.impl);

    var cache = @This(){};
    defer cache.deinit(testing.allocator, dev);

    var d = Dynamic.init();
    defer d.clear(testing.allocator, dev);

    try cache.state.hash_map.put(testing.allocator, d, .{ null_handle, 1 });
    try testing.expect(cache.state.hash_map.contains(d));

    try cache.rendering.hash_map.put(testing.allocator, d.rendering, .{ null_handle, 2 });
    try testing.expect(cache.rendering.hash_map.contains(d.rendering));

    // Make sure `Cmd.Rendering` has no default values
    // on fields we need to check.
    var views = [_]ngl.ImageView{
        .{
            .impl = .{ .val = 0xbaba },
            .format = .rgba8_unorm,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0xbee },
            .format = .rgba8_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0xb00 },
            .format = .d24_unorm_s8_uint,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0xdeedee },
            .format = .d24_unorm_s8_uint,
            .samples = .@"1",
        },
    };
    const rend = ngl.Cmd.Rendering{
        .colors = &.{.{
            .view = &views[0],
            .layout = .color_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = .{
                .view = &views[1],
                .layout = .color_attachment_optimal,
                .mode = .min,
            },
        }},
        .depth = .{
            .view = &views[2],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ 0, undefined } },
            .resolve = .{
                .view = &views[3],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .min,
            },
        },
        .stencil = .{
            .view = &views[2],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ undefined, 0x80 } },
            .resolve = .{
                .view = &views[3],
                .layout = .depth_stencil_attachment_optimal,
                .mode = .min,
            },
        },
        .render_area = .{ .width = 1, .height = 1 },
        .layers = 0,
        .view_mask = 0x1,
    };

    inline for (@typeInfo(@TypeOf(Dynamic.rendering_mask)).Struct.fields) |field| {
        if (!@field(Dynamic.rendering_mask, field.name)) continue;

        @field(d.rendering, field.name).set(rend);

        if (@field(State.rendering_subset_mask, field.name))
            try testing.expect(!cache.state.hash_map.contains(d))
        else
            try testing.expect(cache.state.hash_map.contains(d));

        if (@field(Rendering.subset_mask, field.name))
            try testing.expect(!cache.rendering.hash_map.contains(d.rendering))
        else
            try testing.expect(cache.rendering.hash_map.contains(d.rendering));

        d.clear(null, dev);
        try testing.expect(cache.state.hash_map.contains(d));
        try testing.expect(cache.rendering.hash_map.contains(d.rendering));
    }
}

test getPrimitivePipeline {
    const dev = Device.cast(context().device.impl);

    var cache = @This(){};
    defer cache.deinit(testing.allocator, dev);

    var key = Dynamic.init();
    defer key.clear(testing.allocator, dev);

    const expectRenderPassCount = struct {
        fn do(device: *const Device, rendering: Rendering, count: usize) !void {
            try testing.expectEqual(
                rendering.hash_map.count(),
                if (device.hasDynamicRendering()) 0 else count,
            );
        }
    }.do;

    var set_layt = try ngl.DescriptorSetLayout.init(testing.allocator, &context().device, .{
        .bindings = &.{.{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = null,
        }},
    });
    defer set_layt.deinit(testing.allocator, &context().device);
    const push_consts = [1]ngl.PushConstantRange{.{
        .offset = 0,
        .size = 64,
        .stage_mask = .{ .vertex = true },
    }};
    const shaders = try ngl.Shader.init(testing.allocator, &context().device, &.{
        .{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = &vert_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &push_consts,
            .specialization = null,
            .link = true,
        },
        .{
            .type = .fragment,
            .next = .{},
            .code = &frag_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &push_consts,
            .specialization = null,
            .link = true,
        },
    });
    defer testing.allocator.free(shaders);
    defer for (shaders) |*shd|
        if (shd.*) |*x|
            x.deinit(testing.allocator, &context().device)
        else |_| {};
    var vert_shd = if (shaders[0]) |vs| vs else |err| return err;
    var frag_shd = if (shaders[1]) |fs| fs else |err| return err;
    key.state.shaders.set(&.{ .vertex, .fragment }, &.{ &vert_shd, &frag_shd });

    try key.state.vertex_input.set(
        testing.allocator,
        &.{.{
            .binding = 0,
            .stride = 20,
            .step_rate = .vertex,
        }},
        &.{
            .{
                .location = 0,
                .binding = 0,
                .format = .rgb32_sfloat,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 0,
                .format = .rg32_sfloat,
                .offset = 0,
            },
        },
    );
    key.state.primitive_topology.set(.triangle_strip);

    key.state.rasterization_enable.set(true);
    key.state.polygon_mode.set(.fill);
    key.state.cull_mode.set(.none);
    key.state.front_face.set(.clockwise);
    key.state.sample_count.set(.@"1");
    key.state.sample_mask.set(0x1);

    key.state.depth_bias_enable.set(false);
    key.state.depth_test_enable.set(true);
    key.state.depth_compare_op.set(.less_equal);
    key.state.depth_write_enable.set(true);
    key.state.stencil_test_enable.set(false);

    key.state.color_blend_enable.set(0, &.{false});
    key.state.color_write.set(0, &.{.all});

    var view = ngl.ImageView{
        .impl = .{ .val = 1 },
        .format = .rgba8_unorm,
        .samples = .@"1",
    };
    var view2 = ngl.ImageView{
        .impl = .{ .val = 2 },
        .format = .d16_unorm,
        .samples = .@"1",
    };
    var col_attach = [1]ngl.Cmd.Rendering.Attachment{.{
        .view = &view,
        .layout = .color_attachment_optimal,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .color_f32 = .{ 0, 0, 0, 1 } },
        .resolve = null,
    }};
    const dep_attach = ngl.Cmd.Rendering.Attachment{
        .view = &view2,
        .layout = .depth_stencil_attachment_optimal,
        .load_op = .clear,
        .store_op = .dont_care,
        .clear_value = .{ .depth_stencil = .{ 1, undefined } },
        .resolve = null,
    };
    var rend = ngl.Cmd.Rendering{
        .colors = &col_attach,
        .depth = dep_attach,
        .stencil = null,
        .render_area = .{ .width = 1600, .height = 900 },
        .layers = 1,
    };
    key.rendering.set(rend);

    const pl = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 1);
    try testing.expect(cache.state.hash_map.get(key).?[0] == pl);
    try expectRenderPassCount(dev, cache.rendering, 1);

    if (!key.state.depth_test_enable.enable) unreachable;
    key.state.depth_test_enable.set(false);
    const pl2 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 2);
    try expectRenderPassCount(dev, cache.rendering, 1);
    if (pl2 == pl) log.warn("Identical handles for different pipelines", .{});

    if (key.state.depth_test_enable.enable) unreachable;
    key.state.depth_test_enable.set(true);
    const pl3 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 2);
    try expectRenderPassCount(dev, cache.rendering, 1);
    try testing.expect(pl3 == pl);

    rend.render_area.width /= 2;
    rend.render_area.height /= 2;
    key.rendering.set(rend);
    const pl4 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 2);
    try expectRenderPassCount(dev, cache.rendering, 1);
    try testing.expect(pl4 == pl);

    var view3 = ngl.ImageView{
        .impl = view.impl,
        .format = .rgba16_sfloat,
        .samples = view.samples,
    };
    if (view3.format == view.format) unreachable;
    col_attach[0].view = &view3;
    key.rendering.set(rend);
    const pl5 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 3);
    try expectRenderPassCount(dev, cache.rendering, 2);
    if (pl5 == pl4) log.warn("Identical handles for different pipelines", .{});

    var view4 = ngl.ImageView{
        .impl = .{ .val = view2.impl.val + 1 },
        .format = view2.format,
        .samples = view2.samples,
    };
    rend.depth.?.view = &view4;
    const pl6 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 3);
    try expectRenderPassCount(dev, cache.rendering, 2);
    try testing.expect(pl6 == pl5);

    if (key.state.sample_count.sample_count != .@"1" or
        view.samples != .@"1" or
        view2.samples != .@"1")
    {
        unreachable;
    }
    var view5 = ngl.ImageView{
        .impl = view.impl,
        .format = view.format,
        .samples = .@"4",
    };
    var view6 = ngl.ImageView{
        .impl = view2.impl,
        .format = view2.format,
        .samples = .@"4",
    };
    col_attach[0].view = &view5;
    rend.depth.?.view = &view6;
    key.state.sample_count.set(.@"4");
    key.rendering.set(rend);
    const pl7 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 4);
    try expectRenderPassCount(dev, cache.rendering, 3);
    if (pl7 == pl) log.warn("Identical handles for different pipelines", .{});

    key.state.sample_mask.set(~key.state.sample_mask.sample_mask);
    const pl8 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 5);
    try expectRenderPassCount(dev, cache.rendering, 3);
    if (pl8 == pl7) log.warn("Identical handles for different pipelines", .{});

    rend.depth = null;
    key.rendering.set(rend);
    const pl9 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 6);
    try expectRenderPassCount(dev, cache.rendering, 4);
    if (pl9 == pl8) log.warn("Identical handles for different pipelines", .{});

    col_attach[0].view = &view;
    rend.depth = dep_attach;
    key.state.sample_count.set(view.samples);
    key.state.sample_mask.set(~key.state.sample_mask.sample_mask);
    key.rendering.set(rend);
    const pl10 = try cache.getPrimitivePipeline(testing.allocator, dev, key);
    try testing.expect(cache.state.hash_map.count() == 6);
    try expectRenderPassCount(dev, cache.rendering, 4);
    try testing.expect(pl10 == pl);
}

test getRenderPass {
    const dev = Device.cast(context().device.impl);

    var cache = @This(){};
    defer cache.deinit(testing.allocator, dev);

    var d = Dynamic.init();
    defer d.clear(testing.allocator, dev);
    const key = &d.rendering;

    key.set(.{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1184, .height = 666 },
        .layers = 1,
    });
    const rp = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 1);
    try testing.expect(cache.rendering.hash_map.get(key.*).?[0] == rp);

    const rp2 = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 1);
    try testing.expect(rp2 == rp);

    if (Rendering.subset_mask.render_area_size) unreachable;
    key.set(.{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1024, .height = 1024 },
        .layers = 1,
    });
    const rp3 = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 1);
    try testing.expect(rp3 == rp);

    var view = ngl.ImageView{
        .impl = .{ .val = 1 },
        .format = .rgba8_unorm,
        .samples = .@"1",
    };
    key.set(.{
        .colors = &.{.{
            .view = &view,
            .layout = .color_attachment_optimal,
            .load_op = .dont_care,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1184, .height = 666 },
        .layers = 1,
    });
    const rp4 = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 2);
    if (rp4 == rp) log.warn("Identical handles for different render passes", .{});

    if (Rendering.subset_mask.color_view) unreachable;
    var view2 = ngl.ImageView{
        .impl = .{ .val = view.impl.val + 1 },
        .format = view.format,
        .samples = view.samples,
    };
    key.set(.{
        .colors = &.{.{
            .view = &view2,
            .layout = .color_attachment_optimal,
            .load_op = .dont_care,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1184, .height = 666 },
        .layers = 1,
    });
    const rp5 = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 2);
    try testing.expect(rp5 == rp4);

    var view3 = ngl.ImageView{
        .impl = .{ .val = view.impl.val },
        .format = .a2bgr10_unorm,
        .samples = view.samples,
    };
    if (view3.format == view.format) unreachable;
    key.set(.{
        .colors = &.{.{
            .view = &view3,
            .layout = .color_attachment_optimal,
            .load_op = .dont_care,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 1184, .height = 666 },
        .layers = 1,
    });
    const rp6 = try cache.getRenderPass(testing.allocator, dev, key.*);
    try testing.expect(cache.rendering.hash_map.count() == 3);
    if (rp6 == rp4) log.warn("Identical handles for different render passes", .{});
}

fn validatePrimitivePipeline(key: State.Key, create_info: c.VkGraphicsPipelineCreateInfo) !void {
    if (!builtin.is_test) @compileError("For testing only");

    const state = &key.state;

    const stages = create_info.pStages orelse return error.NullPtr;
    const stage_n = create_info.stageCount;
    try testing.expect(stage_n > 0 and stage_n < 3);

    const vert_shd = Shader.cast(state.shaders.shader.vertex).compat;
    try testing.expect(vert_shd.module == stages[0].module);
    try testing.expectEqual(switch (vert_shd.name) {
        .array => |*x| x.ptr,
        .slice => |*x| x.ptr,
    }, stages[0].pName);
    try testing.expectEqual(
        if (vert_shd.specialization) |*x| x else null,
        stages[0].pSpecializationInfo,
    );

    if (state.shaders.shader.fragment.val != 0) {
        try testing.expect(stage_n == 2);
        const frag_shd = Shader.cast(state.shaders.shader.fragment).compat;
        try testing.expect(frag_shd.module == stages[1].module);
        try testing.expectEqual(switch (frag_shd.name) {
            .array => |*x| x.ptr,
            .slice => |*x| x.ptr,
        }, stages[1].pName);
        try testing.expectEqual(
            if (frag_shd.specialization) |*x| x else null,
            stages[1].pSpecializationInfo,
        );
        // The following two checks are required
        // for pipeline layout compatibility.
        try testing.expectEqualDeep(vert_shd.set_layouts, frag_shd.set_layouts);
        try testing.expectEqualDeep(vert_shd.push_constants, frag_shd.push_constants);
    } else try testing.expect(stage_n == 1);

    const vert_input = create_info.pVertexInputState orelse return error.NullPtr;
    try testing.expect(
        state.vertex_input.bindings.items.len == vert_input.*.vertexBindingDescriptionCount,
    );
    try testing.expect(
        state.vertex_input.attributes.items.len == vert_input.*.vertexAttributeDescriptionCount,
    );
    for (
        state.vertex_input.bindings.items,
        vert_input.*.pVertexBindingDescriptions,
    ) |bind, desc| {
        try testing.expect(bind.binding == desc.binding);
        try testing.expect(bind.stride == desc.stride);
        try testing.expect(conv.toVkVertexInputRate(bind.step_rate) == desc.inputRate);
    }
    for (
        state.vertex_input.attributes.items,
        vert_input.*.pVertexAttributeDescriptions,
    ) |attr, desc| {
        try testing.expect(attr.location == desc.location);
        try testing.expect(attr.binding == desc.binding);
        try testing.expect(try conv.toVkFormat(attr.format) == desc.format);
        try testing.expect(attr.offset == desc.offset);
    }

    const ia = create_info.pInputAssemblyState orelse return error.NullPtr;
    try testing.expect(
        conv.toVkPrimitiveTopology(state.primitive_topology.topology) == ia.*.topology,
    );

    if (create_info.pTessellationState != null) return error.NonnullPtr;

    const vport = create_info.pViewportState orelse return error.NullPtr;
    // TODO: Test counts when dynamic state for them is added.
    try testing.expect(vport.*.pViewports == null);
    try testing.expect(vport.*.pScissors == null);

    const raster = create_info.pRasterizationState orelse return error.NullPtr;
    const raster_enable = raster.*.rasterizerDiscardEnable == c.VK_FALSE;
    const dep_bias_enable = raster.*.depthBiasEnable == c.VK_TRUE;
    try testing.expect(state.rasterization_enable.enable == raster_enable);
    try testing.expect(
        conv.toVkPolygonMode(state.polygon_mode.polygon_mode) == raster.*.polygonMode,
    );
    try testing.expect(conv.toVkCullModeFlags(state.cull_mode.cull_mode) == raster.*.cullMode);
    try testing.expect(conv.toVkFrontFace(state.front_face.front_face) == raster.*.frontFace);
    try testing.expect(state.depth_bias_enable.enable == dep_bias_enable);
    try testing.expect(raster.*.lineWidth == 1);

    const ms = create_info.pMultisampleState orelse return error.NullPtr;
    try testing.expect(
        conv.toVkSampleCount(state.sample_count.sample_count) == ms.*.rasterizationSamples,
    );
    try testing.expect(ms.*.sampleShadingEnable == c.VK_FALSE);
    if (@TypeOf(state.sample_mask.sample_mask) != u64) unreachable;
    try testing.expect(
        @as(c.VkSampleMask, @truncate(state.sample_mask.sample_mask)) == ms.*.pSampleMask[0],
    );
    try testing.expect(
        @as(c.VkSampleMask, @truncate(state.sample_mask.sample_mask >> 32)) == ms.*.pSampleMask[1],
    );
    try testing.expect(ms.*.alphaToCoverageEnable == c.VK_FALSE);
    // TODO: Test alpha to one when dynamic state for it is added.

    const ds = create_info.pDepthStencilState orelse return error.NullPtr;
    const dep_test_enable = ds.*.depthTestEnable == c.VK_TRUE;
    const dep_write_enable = ds.*.depthWriteEnable == c.VK_TRUE;
    const sten_test_enable = ds.*.stencilTestEnable == c.VK_TRUE;
    try testing.expect(state.depth_test_enable.enable == dep_test_enable);
    try testing.expect(state.depth_write_enable.enable == dep_write_enable);
    if (dep_test_enable)
        try testing.expect(
            conv.toVkCompareOp(state.depth_compare_op.compare_op) == ds.*.depthCompareOp,
        );
    try testing.expect(ds.*.depthBoundsTestEnable == c.VK_FALSE);
    try testing.expect(state.stencil_test_enable.enable == sten_test_enable);
    if (sten_test_enable)
        inline for (
            .{ &state.stencil_op.front, &state.stencil_op.back },
            .{ &ds.*.front, &ds.*.back },
        ) |s, t| {
            try testing.expect(conv.toVkStencilOp(s.fail_op) == t.failOp);
            try testing.expect(conv.toVkStencilOp(s.pass_op) == t.passOp);
            try testing.expect(conv.toVkStencilOp(s.depth_fail_op) == t.depthFailOp);
            try testing.expect(conv.toVkCompareOp(s.compare_op) == t.compareOp);
        };

    const rendering = &key.rendering;

    const col_n = blk: {
        var col_n: u32 = ngl.Cmd.max_color_attachment;
        while (col_n != 0 and rendering.color_view.views[col_n - 1].val == 0) : (col_n -= 1) {}
        break :blk col_n;
    };

    const col_blend = create_info.pColorBlendState orelse return error.NullPtr;
    try testing.expect(col_blend.*.logicOpEnable == c.VK_FALSE);
    try testing.expect(col_blend.*.attachmentCount == col_n);
    if (col_n == 0)
        try testing.expect(col_blend.*.pAttachments == null)
    else for (
        state.color_blend_enable.enable[0..col_n],
        state.color_blend.blend[0..col_n],
        state.color_write.write_masks[0..col_n],
        col_blend.*.pAttachments[0..col_n],
    ) |enable, blend, write_mask, attach| {
        const blend_enable = attach.blendEnable == c.VK_TRUE;
        try testing.expect(enable == blend_enable);
        try testing.expect(
            conv.toVkBlendFactor(blend.color_source_factor) == attach.srcColorBlendFactor,
        );
        try testing.expect(
            conv.toVkBlendFactor(blend.color_dest_factor) == attach.dstColorBlendFactor,
        );
        try testing.expect(conv.toVkBlendOp(blend.color_op) == attach.colorBlendOp);
        try testing.expect(
            conv.toVkBlendFactor(blend.alpha_source_factor) == attach.srcAlphaBlendFactor,
        );
        try testing.expect(
            conv.toVkBlendFactor(blend.alpha_dest_factor) == attach.dstAlphaBlendFactor,
        );
        try testing.expect(conv.toVkBlendOp(blend.alpha_op) == attach.alphaBlendOp);
        try testing.expect(conv.toVkColorComponentFlags(write_mask) == attach.colorWriteMask);
    }

    const dynamic = create_info.pDynamicState orelse return error.NullPtr;
    const dyn_state_n = 7;
    const dyn_state_min = 0;
    const dyn_state_max = 8;
    try testing.expect(dyn_state_n == dynamic.*.dynamicStateCount);
    for (dynamic.*.pDynamicStates[0..dyn_state_n]) |x| {
        try testing.expect(x >= dyn_state_min and x <= dyn_state_max);
        try testing.expect(std.mem.count(
            c.VkDynamicState,
            dynamic.*.pDynamicStates[0..dyn_state_n],
            &.{x},
        ) == 1);
    }

    if (Device.cast(context().device.impl).hasDynamicRendering()) {
        var next: ?*const c.VkBaseInStructure = @ptrCast(@alignCast(create_info.pNext));
        while (next) |x| {
            if (x.sType != c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO) {
                next = x.pNext;
                continue;
            }
            const rend: *const c.VkPipelineRenderingCreateInfo = @ptrCast(x);
            try testing.expect(rendering.view_mask.view_mask == rend.viewMask);
            try testing.expect(col_n == rend.colorAttachmentCount);
            for (0..rend.colorAttachmentCount) |i|
                try testing.expect(
                    try conv.toVkFormat(rendering.color_format.formats[i]) ==
                        rend.pColorAttachmentFormats[i],
                );
            try testing.expect(
                try conv.toVkFormat(rendering.depth_format.format) ==
                    rend.depthAttachmentFormat,
            );
            try testing.expect(
                try conv.toVkFormat(rendering.stencil_format.format) ==
                    rend.stencilAttachmentFormat,
            );
            break;
        } else return error.BadNextChain;
        try testing.expect(create_info.renderPass == null_handle);
    } else {
        var next: ?*const c.VkBaseInStructure = @ptrCast(@alignCast(create_info.pNext));
        while (next) |x| {
            if (x.sType == c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO)
                return error.BadNextChain;
            next = x.pNext;
        }
        try testing.expect(create_info.renderPass != null_handle);
    }

    try testing.expect(create_info.layout == vert_shd.pipeline_layout);
    try testing.expect(create_info.subpass == 0);
    try testing.expect(create_info.basePipelineHandle == null_handle);
    try testing.expect(create_info.basePipelineIndex == -1);
}

test createPrimitivePipeline {
    const dev = Device.cast(context().device.impl);

    var key = Dynamic.init();
    defer key.clear(testing.allocator, dev);

    var set_layt = try ngl.DescriptorSetLayout.init(testing.allocator, &context().device, .{
        .bindings = &.{.{
            .binding = 0,
            .type = .combined_image_sampler,
            .count = 1,
            .stage_mask = .{ .fragment = true },
            .immutable_samplers = null,
        }},
    });
    defer set_layt.deinit(testing.allocator, &context().device);
    const push_const = [1]ngl.PushConstantRange{.{
        .offset = 0,
        .size = 64,
        .stage_mask = .{ .vertex = true },
    }};
    const shaders = try ngl.Shader.init(testing.allocator, &context().device, &.{
        .{
            .type = .vertex,
            .next = .{ .fragment = true },
            .code = &vert_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &push_const,
            .specialization = null,
            .link = true,
        },
        .{
            .type = .fragment,
            .next = .{},
            .code = &frag_spv,
            .name = "main",
            .set_layouts = &.{&set_layt},
            .push_constants = &push_const,
            .specialization = null,
            .link = true,
        },
    });
    defer testing.allocator.free(shaders);
    var vert_shd = if (shaders[0]) |x| x else |err| return err;
    defer vert_shd.deinit(testing.allocator, &context().device);
    var frag_shd = if (shaders[1]) |x| x else |err| return err;
    defer frag_shd.deinit(testing.allocator, &context().device);
    key.state.shaders.set(&.{ .vertex, .fragment }, &.{ &vert_shd, &frag_shd });

    try key.state.vertex_input.set(
        testing.allocator,
        &.{.{
            .binding = 0,
            .stride = 20,
            .step_rate = .vertex,
        }},
        &.{
            .{
                .location = 0,
                .binding = 0,
                .format = .rgb32_sfloat,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 0,
                .format = .rg32_sfloat,
                .offset = 12,
            },
        },
    );
    key.state.primitive_topology.set(.triangle_strip);

    key.state.rasterization_enable.set(true); // This is the default.
    key.state.polygon_mode.set(.line);
    key.state.cull_mode.set(.front);
    key.state.front_face.set(.counter_clockwise);
    key.state.sample_count.set(.@"4");
    key.state.sample_mask.set(0x600000005); // The 2nd word is ignored.

    key.state.depth_test_enable.set(true);
    key.state.depth_compare_op.set(.less_equal);
    key.state.depth_write_enable.set(true);
    key.state.stencil_test_enable.set(true);
    key.state.stencil_op.set(.front, .replace, .invert, .decrement_wrap, .greater);
    key.state.stencil_op.set(.back, .invert, .increment_clamp, .replace, .equal);

    key.state.color_blend_enable.set(0, &.{ true, true });
    key.state.color_blend.set(0, &.{
        .{
            .color_source_factor = .dest_color,
            .color_dest_factor = .dest_alpha,
            .color_op = .max,
            .alpha_source_factor = .source_alpha,
            .alpha_dest_factor = .source_color,
            .alpha_op = .reverse_subtract,
        },
        .{
            .color_source_factor = .source_alpha,
            .color_dest_factor = .constant_alpha,
            .color_op = .subtract,
            .alpha_source_factor = .dest_color,
            .alpha_dest_factor = .constant_color,
            .alpha_op = .min,
        },
    });
    key.state.color_write.set(0, &.{ .all, .{ .mask = .{ .r = true } } });

    // It relies on `key.rendering` to infer the number
    // of color attachments used; just the blend-related
    // state set above is not sufficient.
    // Note that the view's `impl.val` must not be zero.
    var col_views = [_]ngl.ImageView{
        .{
            .impl = .{ .val = 1 },
            .format = .rgba16_sfloat,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 2 },
            .format = .rgba16_sfloat,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 3 },
            .format = .rgba8_unorm,
            .samples = .@"4",
        },
    };
    var ds_view = ngl.ImageView{
        .impl = .{ .val = 4 },
        .format = for ([_]ngl.Format{
            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
        }) |comb| {
            if (comb.getFeatures(&context().device).optimal_tiling.depth_stencil_attachment)
                break comb;
        } else unreachable,
        .samples = .@"4",
    };
    key.rendering.set(.{
        .colors = &.{
            .{
                .view = &col_views[0],
                .layout = .color_attachment_optimal,
                .load_op = .load,
                .store_op = .dont_care,
                .clear_value = null,
                .resolve = .{
                    .view = &col_views[1],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &col_views[2],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 0, 0, 0, 1 } },
                .resolve = null,
            },
        },
        .depth = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        },
        .stencil = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        },
        .render_area = .{ .width = 1920, .height = 1080 },
        .layers = 1,
    });
    const rp = if (!dev.hasDynamicRendering())
        try createRenderPass(testing.allocator, dev, key.rendering)
    else
        null_handle;
    defer dev.vkDestroyRenderPass(rp, null);

    const pl = try createPrimitivePipeline(testing.allocator, dev, key, rp);
    defer dev.vkDestroyPipeline(pl, null);

    try testing.expect(pl != null_handle);
}

fn validateRenderPass(key: Rendering.Key, create_info: c.VkRenderPassCreateInfo) !void {
    if (!builtin.is_test) @compileError("For testing only");

    try testing.expect(create_info.subpassCount == 1);
    try testing.expect(create_info.pSubpasses != null);
    try testing.expect(create_info.dependencyCount == 0);

    const subpass = create_info.pSubpasses;
    try testing.expect(subpass.*.inputAttachmentCount == 0);
    try testing.expect(subpass.*.preserveAttachmentCount == 0);

    const col_n = blk: {
        var n: u32 = 0;
        while (key.color_format.formats[n] != .unknown) : (n += 1) {}
        try testing.expect(n == subpass.*.colorAttachmentCount);
        break :blk n;
    };
    const col_rv_n = blk: {
        var n: u32 = 0;
        for (0..col_n) |i| {
            if (key.color_resolve_layout.layouts[i] != .unknown)
                n += 1;
        }
        break :blk n;
    };
    const ds_n: u32 = blk: {
        const has_dep = key.depth_format.format != .unknown;
        const has_sten = key.stencil_format.format != .unknown;
        break :blk if (has_dep or has_sten) 1 else 0;
    };
    const ds_rv_n: u32 = 0; // TODO

    const attach_n = col_n + col_rv_n + ds_n + ds_rv_n;
    try testing.expect(attach_n == create_info.attachmentCount);

    // Code that create render passes and framebuffers
    // must put the attachments in the same order:
    //
    // * 1st color
    // * 1st color's resolve (optional)
    // * ...
    // * nth color
    // * nth color's resolve (optional)
    // * depth/stencil (optional)
    // * depth/stencil's resolve (optional; not yet supported)

    if (ds_rv_n != 0) {
        unreachable; // TODO
    } else if (ds_n != 0) {
        const ds = subpass.*.pDepthStencilAttachment;
        try testing.expect(ds != null);
        try testing.expect(ds.*.attachment == attach_n - 1);
    }

    var attach_i: u32 = 0;
    for (0..col_n) |i| {
        const col = subpass.*.pColorAttachments[i];
        try testing.expect(col.attachment == attach_i);
        attach_i += 1;
        if (key.color_resolve_layout.layouts[i] != .unknown) {
            const rv = subpass.*.pResolveAttachments[i];
            try testing.expect(rv.attachment == attach_i);
            attach_i += 1;
        }
    }
}

test createRenderPass {
    const dev = Device.cast(context().device.impl);

    var key = Dynamic.init().rendering;

    const no_attach = try createRenderPass(testing.allocator, dev, key);
    dev.vkDestroyRenderPass(no_attach, null);

    var dep_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = .d16_unorm,
        .samples = .@"1",
    };
    key.set(.{
        .colors = &.{},
        .depth = .{
            .view = &dep_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = 1024, .height = 1024 },
        .layers = 1,
    });
    const dep_only = try createRenderPass(testing.allocator, dev, key);
    dev.vkDestroyRenderPass(dep_only, null);

    const s8_feat = ngl.Format.s8_uint.getFeatures(&context().device);
    if (s8_feat.optimal_tiling.depth_stencil_attachment) {
        var sten_view = ngl.ImageView{
            .impl = .{ .val = 0 },
            .format = .s8_uint,
            .samples = .@"1",
        };
        key.set(.{
            .colors = &.{},
            .depth = null,
            .stencil = .{
                .view = &sten_view,
                .layout = .depth_stencil_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .depth_stencil = .{ undefined, 0x7f } },
                .resolve = null,
            },
            .render_area = .{ .width = 240, .height = 135 },
            .layers = 1,
        });
        const sten_only = try createRenderPass(testing.allocator, dev, key);
        dev.vkDestroyRenderPass(sten_only, null);
    } else log.warn("Skipping createRenderPass's stencil-only test", .{});

    var ms_dep_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = dep_view.format,
        .samples = .@"4",
    };
    key.set(.{
        .colors = &.{},
        .depth = .{
            .view = &ms_dep_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = .{
                .view = &dep_view,
                .layout = .depth_stencil_attachment_optimal,
                .mode = .sample_zero,
            },
        },
        .stencil = null,
        .render_area = .{ .width = 2048, .height = 2048 },
        .layers = 1,
    });
    // TODO: Implement this.
    const ms_dep_only = createRenderPass(testing.allocator, dev, key);
    try testing.expect(ms_dep_only == Error.NotSupported);

    var col_views = [3]ngl.ImageView{
        .{
            .impl = .{ .val = 0 },
            .format = .rgba8_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0 },
            .format = .a2bgr10_unorm,
            .samples = .@"1",
        },
        .{
            .impl = .{ .val = 0 },
            .format = .rgba16_sfloat,
            .samples = .@"1",
        },
    };
    for ([_][]const *ngl.ImageView{
        &.{&col_views[0]},
        &.{ &col_views[0], &col_views[1] },
        &.{ &col_views[0], &col_views[1], &col_views[2] },
    }) |views| {
        var attachs: [col_views.len]ngl.Cmd.Rendering.Attachment = undefined;
        for (views, attachs[0..views.len]) |view, *attach|
            attach.* = .{
                .view = view,
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = null,
            };
        key.set(.{
            .colors = attachs[0..views.len],
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = 800, .height = 450 },
            .layers = 1,
        });
        const col_only = try createRenderPass(testing.allocator, dev, key);
        dev.vkDestroyRenderPass(col_only, null);
    }

    var ms_col_views = [3]ngl.ImageView{
        .{
            .impl = .{ .val = 0 },
            .format = col_views[0].format,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0 },
            .format = col_views[1].format,
            .samples = .@"4",
        },
        .{
            .impl = .{ .val = 0 },
            .format = col_views[2].format,
            .samples = .@"4",
        },
    };
    for ([_][]const struct { *ngl.ImageView, ?*ngl.ImageView }{
        &.{
            .{ &ms_col_views[0], &col_views[0] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], &col_views[1] },
        },
        &.{
            .{ &ms_col_views[0], null },
            .{ &ms_col_views[1], &col_views[1] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], null },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], &col_views[1] },
            .{ &ms_col_views[2], &col_views[2] },
        },
        &.{
            .{ &ms_col_views[0], &col_views[0] },
            .{ &ms_col_views[1], null },
            .{ &ms_col_views[2], &col_views[2] },
        },
        &.{
            .{ &ms_col_views[0], null },
            .{ &ms_col_views[1], &col_views[1] },
            .{ &ms_col_views[2], null },
        },
    }) |views| {
        var attachs: [ms_col_views.len]ngl.Cmd.Rendering.Attachment = undefined;
        for (views, attachs[0..views.len]) |view, *attach|
            attach.* = .{
                .view = view[0],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = if (view[1] == null) .store else .dont_care,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = if (view[1]) |ss| .{
                    .view = ss,
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                } else null,
            };
        key.set(.{
            .colors = attachs[0..views.len],
            .depth = null,
            .stencil = null,
            .render_area = .{ .width = 1024, .height = 576 },
            .layers = 1,
        });
        const ms_col_only = try createRenderPass(testing.allocator, dev, key);
        dev.vkDestroyRenderPass(ms_col_only, null);
    }

    var ds_view = ngl.ImageView{
        .impl = .{ .val = 0 },
        .format = for ([_]ngl.Format{
            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat_s8_uint,
        }) |comb| {
            if (comb.getFeatures(&context().device).optimal_tiling.depth_stencil_attachment)
                break comb;
        } else unreachable,
        .samples = .@"4",
    };
    key.set(.{
        .colors = &.{
            .{
                .view = &ms_col_views[0],
                .layout = .color_attachment_optimal,
                .load_op = .load,
                .store_op = .dont_care,
                .clear_value = null,
                .resolve = .{
                    .view = &col_views[0],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &ms_col_views[2],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .color_f32 = .{ 0.1, 0.2, 0.3, 1 } },
                .resolve = .{
                    .view = &col_views[2],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
            .{
                .view = &ms_col_views[1],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 0.5, 0.5, 0.5, 1 } },
                .resolve = null,
            },
        },
        .depth = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        },
        .stencil = .{
            .view = &ds_view,
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ undefined, 0xff } },
            .resolve = null,
        },
        .render_area = .{ .width = 1920, .height = 1080 },
        .layers = 1,
    });
    const ms_col_ds = try createRenderPass(testing.allocator, dev, key);
    dev.vkDestroyRenderPass(ms_col_ds, null);
}

fn validateFramebuffer(key: Fbo.Key, create_info: c.VkFramebufferCreateInfo) !void {
    if (!builtin.is_test) @compileError("For testing only");

    try testing.expect(create_info.renderPass != null_handle);

    const col_n = blk: {
        var n: u32 = 0;
        while (key.color_format.formats[n] != .unknown) : (n += 1) {}
        break :blk n;
    };
    const col_rv_n = blk: {
        var n: u32 = 0;
        for (0..col_n) |i| {
            if (key.color_resolve_layout.layouts[i] != .unknown)
                n += 1;
        }
        break :blk n;
    };
    const ds_n: u32 = blk: {
        const has_dep = key.depth_format.format != .unknown;
        const has_sten = key.stencil_format.format != .unknown;
        break :blk if (has_dep or has_sten) 1 else 0;
    };
    const ds_rv_n: u32 = 0; // TODO

    const attach_n = col_n + col_rv_n + ds_n + ds_rv_n;
    try testing.expect(attach_n == create_info.attachmentCount);

    if (ds_rv_n != 0) {
        unreachable; // TODO
    } else if (ds_n != 0) {
        const ds = create_info.pAttachments[attach_n - 1];
        try testing.expect(
            ds == ImageView.cast(if (key.depth_format.format != .unknown)
                key.depth_view.view
            else
                key.stencil_view.view).handle,
        );
    }

    var attach_i: u32 = 0;
    for (0..col_n) |i| {
        const col = create_info.pAttachments[attach_i];
        try testing.expect(col == ImageView.cast(key.color_view.views[i]).handle);
        attach_i += 1;
        if (key.color_resolve_layout.layouts[i] != .unknown) {
            const rv = create_info.pAttachments[attach_i];
            try testing.expect(rv == ImageView.cast(key.color_resolve_view.views[i]).handle);
            attach_i += 1;
        }
    }

    try testing.expect(create_info.width == key.render_area_size.width);
    try testing.expect(create_info.height == key.render_area_size.height);
    try testing.expect(create_info.layers == key.layers.layers);
}

test createFramebuffer {
    const ndev = &context().device;
    const dev = Device.cast(ndev.impl);

    var key = Dynamic.init().rendering;

    key.set(.{
        .colors = &.{},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = 240, .height = 135 },
        .layers = 1,
    });
    const no_attach_rp = try createRenderPass(testing.allocator, dev, key);
    defer dev.vkDestroyRenderPass(no_attach_rp, null);
    const no_attach = try createFramebuffer(testing.allocator, dev, key, no_attach_rp);
    dev.vkDestroyFramebuffer(no_attach, null);

    const width = 800;
    const height = 450;

    const col_spls = [3]ngl.SampleCount{ .@"1", .@"4", .@"4" };
    var col_imgs: [col_spls.len]ngl.Image = undefined;
    var col_mems: [col_spls.len]ngl.Memory = undefined;
    var col_views: [col_spls.len]ngl.ImageView = undefined;
    for (col_spls, &col_imgs, &col_mems, &col_views, 0..) |spls, *col_img, *col_mem, *col_view, i| {
        errdefer for (0..i) |j| {
            col_views[j].deinit(testing.allocator, ndev);
            col_imgs[j].deinit(testing.allocator, ndev);
            ndev.free(testing.allocator, &col_mems[j]);
        };
        col_img.* = try ngl.Image.init(testing.allocator, ndev, .{
            .type = .@"2d",
            .format = .rgba8_unorm,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = spls,
            .tiling = .optimal,
            .usage = .{ .color_attachment = true },
            .misc = .{},
            .initial_layout = .unknown,
        });
        errdefer col_img.deinit(testing.allocator, ndev);
        const col_reqs = col_img.getMemoryRequirements(ndev);
        col_mem.* = try ndev.alloc(testing.allocator, .{
            .size = col_reqs.size,
            .type_index = col_reqs.findType(ndev.*, .{ .device_local = true }, null).?,
        });
        errdefer ndev.free(testing.allocator, col_mem);
        try col_img.bind(ndev, col_mem, 0);
        col_view.* = try ngl.ImageView.init(testing.allocator, ndev, .{
            .image = col_img,
            .type = .@"2d",
            .format = .rgba8_unorm,
            .range = .{
                .aspect_mask = .{ .color = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });
    }
    defer for (0..col_spls.len) |i| {
        col_views[i].deinit(testing.allocator, ndev);
        col_imgs[i].deinit(testing.allocator, ndev);
        ndev.free(testing.allocator, &col_mems[i]);
    };

    key.set(.{
        .colors = &.{.{
            .view = &col_views[0],
            .layout = .general,
            .load_op = .dont_care,
            .store_op = .dont_care,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = null,
        .stencil = null,
        .render_area = .{ .width = width, .height = height },
        .layers = 1,
    });
    const col_only_rp = try createRenderPass(testing.allocator, dev, key);
    defer dev.vkDestroyRenderPass(col_only_rp, null);
    const col_only = try createFramebuffer(testing.allocator, dev, key, col_only_rp);
    dev.vkDestroyFramebuffer(col_only, null);

    const dep_spls = [2]ngl.SampleCount{ .@"1", .@"4" };
    var dep_imgs: [dep_spls.len]ngl.Image = undefined;
    var dep_mems: [dep_spls.len]ngl.Memory = undefined;
    var dep_views: [dep_spls.len]ngl.ImageView = undefined;
    for (dep_spls, &dep_imgs, &dep_mems, &dep_views, 0..) |spls, *dep_img, *dep_mem, *dep_view, i| {
        errdefer for (0..i) |j| {
            dep_views[j].deinit(testing.allocator, ndev);
            dep_imgs[j].deinit(testing.allocator, ndev);
            ndev.free(testing.allocator, &dep_mems[j]);
        };
        dep_img.* = try ngl.Image.init(testing.allocator, ndev, .{
            .type = .@"2d",
            .format = .d16_unorm,
            .width = width,
            .height = height,
            .depth_or_layers = 1,
            .levels = 1,
            .samples = spls,
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment = true },
            .misc = .{},
            .initial_layout = .unknown,
        });
        errdefer dep_img.deinit(testing.allocator, ndev);
        const dep_reqs = dep_img.getMemoryRequirements(ndev);
        dep_mem.* = try ndev.alloc(testing.allocator, .{
            .size = dep_reqs.size,
            .type_index = dep_reqs.findType(ndev.*, .{ .device_local = true }, null).?,
        });
        errdefer ndev.free(testing.allocator, dep_mem);
        try dep_img.bind(ndev, dep_mem, 0);
        dep_view.* = try ngl.ImageView.init(testing.allocator, ndev, .{
            .image = dep_img,
            .type = .@"2d",
            .format = .d16_unorm,
            .range = .{
                .aspect_mask = .{ .depth = true },
                .level = 0,
                .levels = 1,
                .layer = 0,
                .layers = 1,
            },
        });
    }
    defer for (0..dep_spls.len) |i| {
        dep_views[i].deinit(testing.allocator, ndev);
        dep_imgs[i].deinit(testing.allocator, ndev);
        ndev.free(testing.allocator, &dep_mems[i]);
    };

    key.set(.{
        .colors = &.{},
        .depth = .{
            .view = &dep_views[0],
            .layout = .general,
            .load_op = .dont_care,
            .store_op = .dont_care,
            .clear_value = null,
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = width, .height = height },
        .layers = 1,
    });
    const dep_only_rp = try createRenderPass(testing.allocator, dev, key);
    defer dev.vkDestroyRenderPass(dep_only_rp, null);
    const dep_only = try createFramebuffer(testing.allocator, dev, key, dep_only_rp);
    dev.vkDestroyFramebuffer(dep_only, null);

    key.set(.{
        .colors = &.{.{
            .view = &col_views[0],
            .layout = .general,
            .load_op = .load,
            .store_op = .store,
            .clear_value = null,
            .resolve = null,
        }},
        .depth = .{
            .view = &dep_views[0],
            .layout = .general,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 1, undefined } },
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = width, .height = height },
        .layers = 1,
    });
    const col_dep_rp = try createRenderPass(testing.allocator, dev, key);
    defer dev.vkDestroyRenderPass(col_dep_rp, null);
    const col_dep = try createFramebuffer(testing.allocator, dev, key, col_dep_rp);
    dev.vkDestroyFramebuffer(col_dep, null);

    key.set(.{
        .colors = &.{
            .{
                .view = &col_views[2],
                .layout = .color_attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color_f32 = .{ 1, 1, 1, 1 } },
                .resolve = null,
            },
            .{
                .view = &col_views[1],
                .layout = .general,
                .load_op = .load,
                .store_op = .dont_care,
                .clear_value = null,
                .resolve = .{
                    .view = &col_views[0],
                    .layout = .color_attachment_optimal,
                    .mode = .average,
                },
            },
        },
        .depth = .{
            .view = &dep_views[1],
            .layout = .depth_stencil_attachment_optimal,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ 0, undefined } },
            .resolve = null,
        },
        .stencil = null,
        .render_area = .{ .width = width, .height = height },
        .layers = 1,
    });
    const ms_rp = try createRenderPass(testing.allocator, dev, key);
    defer dev.vkDestroyRenderPass(ms_rp, null);
    const ms = try createFramebuffer(testing.allocator, dev, key, ms_rp);
    dev.vkDestroyFramebuffer(ms, null);
}

// #version 460 core
//
// layout(push_constant) uniform PushConst { mat4 m; } push_const;
// layout(location = 0) in vec3 position;
// layout(location = 1) in vec2 uv;
// layout(location = 0) out vec2 out_uv;
//
// void main() {
//     gl_Position = push_const.m * vec4(position, 1.0);
//     out_uv = uv;
// }
const vert_spv align(4) = [984]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x29, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x9,  0x0, 0x0,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x19, 0x0,  0x0,  0x0,  0x25, 0x0,  0x0,  0x0,
    0x27, 0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x48, 0x0,  0x5,  0x0,
    0xb,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x47, 0x0,  0x3,  0x0,  0xb,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x4,  0x0, 0x11, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x5,  0x0,  0x0,  0x0,
    0x48, 0x0, 0x5,  0x0, 0x11, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x48, 0x0,  0x5,  0x0,  0x11, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x7,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x47, 0x0,  0x3,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x19, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x25, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x47, 0x0,  0x4,  0x0,  0x27, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,  0x21, 0x0,  0x3,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x15, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x2b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x1c, 0x0,  0x4,  0x0,  0xa,  0x0,  0x0,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x1e, 0x0,  0x6,  0x0,  0xb,  0x0,  0x0,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0xa,  0x0,  0x0,  0x0,  0xa,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0xb,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,
    0xc,  0x0, 0x0,  0x0, 0xd,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0x15, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,
    0xe,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x18, 0x0,  0x4,  0x0,
    0x10, 0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x3,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x11, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x10, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x17, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x18, 0x0,  0x0,  0x0,
    0x19, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x2b, 0x0,  0x4,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1b, 0x0, 0x0,  0x0, 0x0,  0x0,  0x80, 0x3f, 0x20, 0x0,  0x4,  0x0,  0x21, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x23, 0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x24, 0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x23, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x24, 0x0,  0x0,  0x0,
    0x25, 0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x23, 0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x26, 0x0,  0x0,  0x0,
    0x27, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0x14, 0x0,  0x0,  0x0,  0x15, 0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x16, 0x0, 0x0,  0x0, 0x15, 0x0,  0x0,  0x0,  0x3d, 0x0,  0x4,  0x0,  0x17, 0x0,  0x0,  0x0,
    0x1a, 0x0, 0x0,  0x0, 0x19, 0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,  0x6,  0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x1a, 0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x51, 0x0,  0x5,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0x51, 0x0, 0x5,  0x0, 0x6,  0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x1a, 0x0,  0x0,  0x0,
    0x2,  0x0, 0x0,  0x0, 0x50, 0x0,  0x7,  0x0,  0x7,  0x0,  0x0,  0x0,  0x1f, 0x0,  0x0,  0x0,
    0x1c, 0x0, 0x0,  0x0, 0x1d, 0x0,  0x0,  0x0,  0x1e, 0x0,  0x0,  0x0,  0x1b, 0x0,  0x0,  0x0,
    0x91, 0x0, 0x5,  0x0, 0x7,  0x0,  0x0,  0x0,  0x20, 0x0,  0x0,  0x0,  0x16, 0x0,  0x0,  0x0,
    0x1f, 0x0, 0x0,  0x0, 0x41, 0x0,  0x5,  0x0,  0x21, 0x0,  0x0,  0x0,  0x22, 0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x22, 0x0,  0x0,  0x0,
    0x20, 0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0x23, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,
    0x27, 0x0, 0x0,  0x0, 0x3e, 0x0,  0x3,  0x0,  0x25, 0x0,  0x0,  0x0,  0x28, 0x0,  0x0,  0x0,
    0xfd, 0x0, 0x1,  0x0, 0x38, 0x0,  0x1,  0x0,
};

// #version 460 core
//
// layout(set = 0, binding = 0) uniform sampler2D ts;
// layout(location = 0) in vec2 uv;
// layout(location = 0) out vec4 color_0;
//
// void main() {
//     color_0 = texture(ts, uv);
// }
const frag_spv align(4) = [476]u8{
    0x3,  0x2, 0x23, 0x7, 0x0,  0x0,  0x1,  0x0,  0xb,  0x0,  0x8,  0x0,  0x14, 0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x11, 0x0,  0x2,  0x0,  0x1,  0x0,  0x0,  0x0,  0xb,  0x0,  0x6,  0x0,
    0x1,  0x0, 0x0,  0x0, 0x47, 0x4c, 0x53, 0x4c, 0x2e, 0x73, 0x74, 0x64, 0x2e, 0x34, 0x35, 0x30,
    0x0,  0x0, 0x0,  0x0, 0xe,  0x0,  0x3,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1,  0x0,  0x0,  0x0,
    0xf,  0x0, 0x7,  0x0, 0x4,  0x0,  0x0,  0x0,  0x4,  0x0,  0x0,  0x0,  0x6d, 0x61, 0x69, 0x6e,
    0x0,  0x0, 0x0,  0x0, 0x9,  0x0,  0x0,  0x0,  0x11, 0x0,  0x0,  0x0,  0x10, 0x0,  0x3,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x22, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0xd,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x47, 0x0,  0x4,  0x0,  0x11, 0x0,  0x0,  0x0,
    0x1e, 0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x13, 0x0,  0x2,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x21, 0x0, 0x3,  0x0, 0x3,  0x0,  0x0,  0x0,  0x2,  0x0,  0x0,  0x0,  0x16, 0x0,  0x3,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x20, 0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0x7,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x4,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x3,  0x0, 0x0,  0x0, 0x7,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x8,  0x0,  0x0,  0x0,
    0x9,  0x0, 0x0,  0x0, 0x3,  0x0,  0x0,  0x0,  0x19, 0x0,  0x9,  0x0,  0xa,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x0,  0x1b, 0x0,  0x3,  0x0,
    0xb,  0x0, 0x0,  0x0, 0xa,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,
    0x0,  0x0, 0x0,  0x0, 0xb,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0xc,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x17, 0x0,  0x4,  0x0,  0xf,  0x0,  0x0,  0x0,
    0x6,  0x0, 0x0,  0x0, 0x2,  0x0,  0x0,  0x0,  0x20, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x1,  0x0, 0x0,  0x0, 0xf,  0x0,  0x0,  0x0,  0x3b, 0x0,  0x4,  0x0,  0x10, 0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x1,  0x0,  0x0,  0x0,  0x36, 0x0,  0x5,  0x0,  0x2,  0x0,  0x0,  0x0,
    0x4,  0x0, 0x0,  0x0, 0x0,  0x0,  0x0,  0x0,  0x3,  0x0,  0x0,  0x0,  0xf8, 0x0,  0x2,  0x0,
    0x5,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0xb,  0x0,  0x0,  0x0,  0xe,  0x0,  0x0,  0x0,
    0xd,  0x0, 0x0,  0x0, 0x3d, 0x0,  0x4,  0x0,  0xf,  0x0,  0x0,  0x0,  0x12, 0x0,  0x0,  0x0,
    0x11, 0x0, 0x0,  0x0, 0x57, 0x0,  0x5,  0x0,  0x7,  0x0,  0x0,  0x0,  0x13, 0x0,  0x0,  0x0,
    0xe,  0x0, 0x0,  0x0, 0x12, 0x0,  0x0,  0x0,  0x3e, 0x0,  0x3,  0x0,  0x9,  0x0,  0x0,  0x0,
    0x13, 0x0, 0x0,  0x0, 0xfd, 0x0,  0x1,  0x0,  0x38, 0x0,  0x1,  0x0,
};
