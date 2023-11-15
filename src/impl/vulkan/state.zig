const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const ndhOrNull = conv.ndhOrNull;
const check = conv.check;
const Device = @import("init.zig").Device;
const PipelineLayout = @import("desc.zig").PipelineLayout;
const RenderPass = @import("pass.zig").RenderPass;

pub const Pipeline = struct {
    handle: c.VkPipeline,
    modules: [max_stage]c.VkShaderModule,

    const max_stage = 2;

    pub inline fn cast(impl: Impl.Pipeline) *Pipeline {
        return impl.ptr(Pipeline);
    }

    pub fn initGraphics(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Pipeline.Desc(ngl.GraphicsState),
        pipelines: []ngl.Pipeline,
    ) Error!void {
        const dev = Device.cast(device);

        var create_infos = try allocator.alloc(c.VkGraphicsPipelineCreateInfo, desc.states.len);
        defer allocator.free(create_infos);

        var create_inner = try allocator.alloc(
            struct {
                vertex_input_state: c.VkPipelineVertexInputStateCreateInfo,
                input_assembly_state: c.VkPipelineInputAssemblyStateCreateInfo,
                viewport_state: c.VkPipelineViewportStateCreateInfo,
                viewport_state_viewport: c.VkViewport,
                viewport_state_scissor: c.VkRect2D,
                rasterization_state: c.VkPipelineRasterizationStateCreateInfo,
                multisample_state: c.VkPipelineMultisampleStateCreateInfo,
                multisample_state_sample_mask: [2]u32,
                depth_stencil_state: c.VkPipelineDepthStencilStateCreateInfo,
                color_blend_state: c.VkPipelineColorBlendStateCreateInfo,
                dynamic_state: c.VkPipelineDynamicStateCreateInfo,
                dynamic_state_dynamic_states: [4]c.VkDynamicState,
            },
            desc.states.len,
        );
        defer allocator.free(create_inner);

        var stages: []c.VkPipelineShaderStageCreateInfo = &.{};
        var vert_binds: []c.VkVertexInputBindingDescription = &.{};
        var vert_attrs: []c.VkVertexInputAttributeDescription = &.{};
        var blend_attachs: []c.VkPipelineColorBlendAttachmentState = &.{};
        defer {
            if (stages.len > 0) allocator.free(stages);
            if (vert_binds.len > 0) allocator.free(vert_binds);
            if (vert_attrs.len > 0) allocator.free(vert_attrs);
            if (blend_attachs.len > 0) allocator.free(blend_attachs);
        }
        {
            var stage_n: usize = 0;
            var bind_n: usize = 0;
            var attr_n: usize = 0;
            var blend_n: usize = 0;
            for (desc.states) |state| {
                stage_n += state.stages.len;
                if (state.primitive) |x| {
                    bind_n += x.bindings.len;
                    attr_n += x.attributes.len;
                }
                if (state.color_blend) |x| blend_n += x.attachments.len;
            }
            if (stage_n > 0) stages = try allocator.alloc(
                c.VkPipelineShaderStageCreateInfo,
                stage_n,
            ) else unreachable;
            if (bind_n > 0) vert_binds = try allocator.alloc(
                c.VkVertexInputBindingDescription,
                bind_n,
            );
            if (attr_n > 0) vert_attrs = try allocator.alloc(
                c.VkVertexInputAttributeDescription,
                attr_n,
            );
            if (blend_n > 0) blend_attachs = try allocator.alloc(
                c.VkPipelineColorBlendAttachmentState,
                blend_n,
            );
        }
        var stages_ptr = stages.ptr;
        var vert_binds_ptr = vert_binds.ptr;
        var vert_attrs_ptr = vert_attrs.ptr;
        var blend_attachs_ptr = blend_attachs.ptr;

        const defaults: struct {
            vertex_input_state: c.VkPipelineVertexInputStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = 0,
                .pVertexBindingDescriptions = null,
                .vertexAttributeDescriptionCount = 0,
                .pVertexAttributeDescriptions = null,
            },
            input_assembly_state: c.VkPipelineInputAssemblyStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            },
            tessellation_state: c.VkPipelineTessellationStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .patchControlPoints = 4,
            },
            viewport_state: c.VkPipelineViewportStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .viewportCount = 1,
                .pViewports = null,
                .scissorCount = 1,
                .pScissors = null,
            },
            rasterization_state: c.VkPipelineRasterizationStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = c.VK_TRUE,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .cullMode = c.VK_CULL_MODE_FRONT_AND_BACK,
                .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0,
                .depthBiasClamp = 0,
                .depthBiasSlopeFactor = 0,
                .lineWidth = 1,
            },
            multisample_state: c.VkPipelineMultisampleStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            },
            depth_stencil_state: c.VkPipelineDepthStencilStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = c.VK_FALSE,
                .depthWriteEnable = c.VK_FALSE,
                .depthCompareOp = c.VK_COMPARE_OP_NEVER,
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = c.VK_FALSE,
                .front = .{
                    .failOp = c.VK_STENCIL_OP_KEEP,
                    .passOp = c.VK_STENCIL_OP_KEEP,
                    .depthFailOp = c.VK_STENCIL_OP_KEEP,
                    .compareOp = c.VK_COMPARE_OP_NEVER,
                    .compareMask = 0,
                    .writeMask = 0,
                    .reference = 0,
                },
                .back = .{
                    .failOp = c.VK_STENCIL_OP_KEEP,
                    .passOp = c.VK_STENCIL_OP_KEEP,
                    .depthFailOp = c.VK_STENCIL_OP_KEEP,
                    .compareOp = c.VK_COMPARE_OP_NEVER,
                    .compareMask = 0,
                    .writeMask = 0,
                    .reference = 0,
                },
                .minDepthBounds = 0,
                .maxDepthBounds = 0,
            },
            color_blend_state: c.VkPipelineColorBlendStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_CLEAR,
                .attachmentCount = 0,
                .pAttachments = null,
                .blendConstants = .{ 0, 0, 0, 0 },
            },
            dynamic_state: c.VkPipelineDynamicStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .dynamicStateCount = 0,
                .pDynamicStates = null,
            },
        } = .{};

        for (create_infos, create_inner, desc.states) |*info, *inner, state| {
            info.* = .{
                .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stageCount = @intCast(state.stages.len),
                .pStages = undefined, // Set below
                .pVertexInputState = &inner.vertex_input_state,
                .pInputAssemblyState = &inner.input_assembly_state,
                .pTessellationState = &defaults.tessellation_state,
                .pViewportState = &inner.viewport_state,
                .pRasterizationState = &inner.rasterization_state,
                .pMultisampleState = &inner.multisample_state,
                .pDepthStencilState = &inner.depth_stencil_state,
                .pColorBlendState = &inner.color_blend_state,
                .pDynamicState = &inner.dynamic_state,
                .layout = PipelineLayout.cast(state.layout.impl).handle,
                .renderPass = if (state.render_pass) |x|
                    RenderPass.cast(x.impl).handle
                else
                    null_handle,
                .subpass = state.subpass,
                // TODO: Expose these
                .basePipelineHandle = null_handle,
                .basePipelineIndex = -1,
            };

            inner.vertex_input_state = if (state.primitive) |s| .{
                .sType = defaults.vertex_input_state.sType,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = @intCast(s.bindings.len),
                .pVertexBindingDescriptions = blk: {
                    for (vert_binds_ptr, s.bindings) |*p, b|
                        p.* = .{
                            .binding = b.binding,
                            .stride = b.stride,
                            .inputRate = switch (b.step_rate) {
                                .vertex => c.VK_VERTEX_INPUT_RATE_VERTEX,
                                // TODO: Support other instance divisor values
                                // (need to check availability)
                                .instance => |div| if (div == 1)
                                    c.VK_VERTEX_INPUT_RATE_INSTANCE
                                else
                                    return Error.NotSupported,
                            },
                        };
                    defer vert_binds_ptr += s.bindings.len;
                    break :blk vert_binds_ptr;
                },
                .vertexAttributeDescriptionCount = @intCast(s.attributes.len),
                .pVertexAttributeDescriptions = blk: {
                    for (vert_attrs_ptr, s.attributes) |*p, a|
                        p.* = .{
                            .location = a.location,
                            .binding = a.binding,
                            .format = try conv.toVkFormat(a.format),
                            .offset = a.offset,
                        };
                    defer vert_attrs_ptr += s.attributes.len;
                    break :blk vert_attrs_ptr;
                },
            } else defaults.vertex_input_state;

            inner.input_assembly_state = if (state.primitive) |s| .{
                .sType = defaults.input_assembly_state.sType,
                .pNext = null,
                .flags = 0,
                .topology = conv.toVkPrimitiveTopology(s.topology),
                .primitiveRestartEnable = if (s.restart) c.VK_TRUE else c.VK_FALSE,
            } else defaults.input_assembly_state;

            inner.viewport_state = if (state.viewport) |s| .{
                .sType = defaults.viewport_state.sType,
                .pNext = null,
                .flags = 0,
                .viewportCount = 1,
                .pViewports = blk: {
                    inner.viewport_state_viewport = .{
                        .x = s.x,
                        .y = s.y,
                        .width = s.width,
                        .height = s.height,
                        .minDepth = s.near,
                        .maxDepth = s.far,
                    };
                    break :blk &inner.viewport_state_viewport;
                },
                .scissorCount = 1,
                .pScissors = blk: {
                    inner.viewport_state_scissor = if (s.scissor) |x| .{
                        .offset = .{
                            .x = @min(x.x, std.math.maxInt(i32)),
                            .y = @min(x.y, std.math.maxInt(i32)),
                        },
                        .extent = .{
                            .width = x.width,
                            .height = x.height,
                        },
                    } else .{
                        .offset = .{
                            .x = @intFromFloat(@min(@abs(s.x), std.math.maxInt(i32))),
                            .y = @intFromFloat(@min(@abs(s.y), std.math.maxInt(i32))),
                        },
                        .extent = .{
                            .width = @intFromFloat(@min(@abs(s.width), std.math.maxInt(u32))),
                            .height = @intFromFloat(@min(@abs(s.height), std.math.maxInt(u32))),
                        },
                    };
                    break :blk &inner.viewport_state_scissor;
                },
            } else defaults.viewport_state;

            inner.rasterization_state = if (state.rasterization) |s| .{
                .sType = defaults.rasterization_state.sType,
                .pNext = null,
                .flags = 0,
                .depthClampEnable = if (s.depth_clamp) c.VK_TRUE else c.VK_FALSE,
                .rasterizerDiscardEnable = c.VK_FALSE,
                .polygonMode = conv.toVkPolygonMode(s.polygon_mode),
                .cullMode = conv.toVkCullModeFlags(s.cull_mode),
                .frontFace = if (s.clockwise)
                    c.VK_FRONT_FACE_CLOCKWISE
                else
                    c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
                .depthBiasEnable = if (s.depth_bias == null) c.VK_FALSE else c.VK_TRUE,
                .depthBiasConstantFactor = if (s.depth_bias) |x| x.value else 0,
                .depthBiasClamp = if (s.depth_bias) |x| x.clamp else 0,
                .depthBiasSlopeFactor = if (s.depth_bias) |x| x.slope else 0,
                .lineWidth = 1.0,
            } else defaults.rasterization_state;

            inner.multisample_state = if (state.rasterization) |s| .{
                .sType = defaults.multisample_state.sType,
                .pNext = null,
                .flags = 0,
                .rasterizationSamples = conv.toVkSampleCount(s.samples),
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 0,
                .pSampleMask = blk: {
                    inner.multisample_state_sample_mask[0] = @truncate(s.sample_mask);
                    inner.multisample_state_sample_mask[1] = @truncate(s.sample_mask >> 32);
                    break :blk inner.multisample_state_sample_mask[0..].ptr;
                },
                .alphaToCoverageEnable = if (s.alpha_to_coverage) c.VK_TRUE else c.VK_FALSE,
                .alphaToOneEnable = if (s.alpha_to_one) c.VK_TRUE else c.VK_FALSE,
            } else defaults.multisample_state;

            inner.depth_stencil_state = if (state.depth_stencil) |s| .{
                .sType = defaults.depth_stencil_state.sType,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = if (s.depth_compare == null) c.VK_FALSE else c.VK_TRUE,
                .depthWriteEnable = if (s.depth_write) c.VK_TRUE else c.VK_FALSE,
                .depthCompareOp = conv.toVkCompareOp(s.depth_compare orelse .never),
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = if (s.stencil_front != null or s.stencil_back != null)
                    c.VK_TRUE
                else
                    c.VK_FALSE,
                .front = if (s.stencil_front) |t| .{
                    .failOp = conv.toVkStencilOp(t.fail_op),
                    .passOp = conv.toVkStencilOp(t.pass_op),
                    .depthFailOp = conv.toVkStencilOp(t.depth_fail_op),
                    .compareOp = conv.toVkCompareOp(t.compare),
                    .compareMask = t.read_mask,
                    .writeMask = t.write_mask,
                    .reference = t.reference orelse 0,
                } else .{
                    .failOp = c.VK_STENCIL_OP_KEEP,
                    .passOp = c.VK_STENCIL_OP_KEEP,
                    .depthFailOp = c.VK_STENCIL_OP_KEEP,
                    .compareOp = c.VK_COMPARE_OP_ALWAYS,
                    .compareMask = 0,
                    .writeMask = 0,
                    .reference = if (s.stencil_back) |x| x.reference orelse 0 else 0,
                },
                .back = if (s.stencil_back) |t| .{
                    .failOp = conv.toVkStencilOp(t.fail_op),
                    .passOp = conv.toVkStencilOp(t.pass_op),
                    .depthFailOp = conv.toVkStencilOp(t.depth_fail_op),
                    .compareOp = conv.toVkCompareOp(t.compare),
                    .compareMask = t.read_mask,
                    .writeMask = t.write_mask,
                    .reference = t.reference orelse 0,
                } else .{
                    .failOp = c.VK_STENCIL_OP_KEEP,
                    .passOp = c.VK_STENCIL_OP_KEEP,
                    .depthFailOp = c.VK_STENCIL_OP_KEEP,
                    .compareOp = c.VK_COMPARE_OP_ALWAYS,
                    .compareMask = 0,
                    .writeMask = 0,
                    .reference = if (s.stencil_front) |x| x.reference orelse 0 else 0,
                },
                .minDepthBounds = 0,
                .maxDepthBounds = 0,
            } else defaults.depth_stencil_state;

            inner.color_blend_state = if (state.color_blend) |s| .{
                .sType = defaults.color_blend_state.sType,
                .pNext = null,
                .flags = 0,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_CLEAR,
                .attachmentCount = @intCast(s.attachments.len),
                .pAttachments = blk: {
                    for (blend_attachs_ptr, s.attachments) |*p, a| {
                        p.* = if (a.blend) |b| .{
                            .blendEnable = c.VK_TRUE,
                            .srcColorBlendFactor = conv.toVkBlendFactor(b.color_source_factor),
                            .dstColorBlendFactor = conv.toVkBlendFactor(b.color_dest_factor),
                            .colorBlendOp = conv.toVkBlendOp(b.color_op),
                            .srcAlphaBlendFactor = conv.toVkBlendFactor(b.alpha_source_factor),
                            .dstAlphaBlendFactor = conv.toVkBlendFactor(b.alpha_dest_factor),
                            .alphaBlendOp = conv.toVkBlendOp(b.alpha_op),
                            .colorWriteMask = undefined,
                        } else .{
                            .blendEnable = c.VK_FALSE,
                            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                            .colorBlendOp = c.VK_BLEND_OP_ADD,
                            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                            .alphaBlendOp = c.VK_BLEND_OP_ADD,
                            .colorWriteMask = undefined,
                        };
                        p.colorWriteMask = switch (a.write) {
                            .all => c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
                                c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                            .mask => |x| blk2: {
                                var flags: c.VkColorComponentFlags = 0;
                                if (x.r) flags |= c.VK_COLOR_COMPONENT_R_BIT;
                                if (x.g) flags |= c.VK_COLOR_COMPONENT_G_BIT;
                                if (x.b) flags |= c.VK_COLOR_COMPONENT_B_BIT;
                                if (x.a) flags |= c.VK_COLOR_COMPONENT_A_BIT;
                                break :blk2 flags;
                            },
                        };
                    }
                    defer blend_attachs_ptr += s.attachments.len;
                    break :blk blend_attachs_ptr;
                },
                .blendConstants = switch (s.constants) {
                    .static => |x| x,
                    else => .{ 0, 0, 0, 0 },
                },
            } else defaults.color_blend_state;

            inner.dynamic_state = blk: {
                var dyns: []c.VkDynamicState = &inner.dynamic_state_dynamic_states;
                if (state.viewport == null) {
                    dyns[0] = c.VK_DYNAMIC_STATE_VIEWPORT;
                    dyns[1] = c.VK_DYNAMIC_STATE_SCISSOR;
                    dyns = dyns[2..];
                }
                if (state.depth_stencil) |x| {
                    if ((x.stencil_front != null and x.stencil_front.?.reference == null) or
                        (x.stencil_back != null and x.stencil_back.?.reference == null))
                    {
                        dyns[0] = c.VK_DYNAMIC_STATE_STENCIL_REFERENCE;
                        dyns = dyns[1..];
                    }
                }
                if (state.color_blend) |x| {
                    if (x.constants == .dynamic) {
                        dyns[0] = c.VK_DYNAMIC_STATE_BLEND_CONSTANTS;
                        dyns = dyns[1..];
                    }
                }
                const dyn_n = inner.dynamic_state_dynamic_states.len - dyns.len;
                break :blk if (dyn_n > 0) .{
                    .sType = defaults.dynamic_state.sType,
                    .pNext = null,
                    .flags = 0,
                    .dynamicStateCount = @intCast(dyn_n),
                    .pDynamicStates = &inner.dynamic_state_dynamic_states,
                } else defaults.dynamic_state;
            };
        }

        var module_create_infos: []c.VkShaderModuleCreateInfo = &.{};
        defer if (module_create_infos.len > 0) allocator.free(module_create_infos);

        errdefer for (stages) |s| {
            if (s.module == null_handle) break;
            dev.vkDestroyShaderModule(s.module, null);
        };

        if (false) { // TODO: Don't create modules if maintenance5 is available
            stages_ptr[0].module = null;
            // TODO...
        } else {
            for (create_infos, desc.states) |*info, state| {
                errdefer stages_ptr[0].module = null_handle;

                info.*.pStages = stages_ptr;

                for (state.stages) |stage| {
                    stages_ptr[0] = .{
                        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .stage = conv.toVkShaderStage(stage.stage),
                        .module = undefined,
                        .pName = stage.name,
                        .pSpecializationInfo = null, // TODO
                    };

                    try check(dev.vkCreateShaderModule(&.{
                        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                        .pNext = null,
                        .flags = 0,
                        .codeSize = stage.code.len,
                        .pCode = @as([*]const u32, @ptrCast(stage.code.ptr)),
                    }, null, &stages_ptr[0].module));

                    stages_ptr += 1;
                }
            }
        }

        var handles = try allocator.alloc(c.VkPipeline, create_infos.len);
        defer allocator.free(handles);

        try check(dev.vkCreateGraphicsPipelines(
            if (desc.cache) |x| PipelineCache.cast(x.impl).handle else null_handle,
            @intCast(create_infos.len),
            create_infos.ptr,
            null,
            handles.ptr,
        ));

        stages_ptr = stages.ptr;

        for (pipelines, handles, desc.states, 0..) |*pl, h, s, i| {
            var ptr = allocator.create(Pipeline) catch |err| {
                for (0..i) |j| {
                    allocator.destroy(cast(pipelines[j].impl));
                    pipelines[j].impl = undefined;
                }
                return err;
            };
            std.debug.assert(s.stages.len <= max_stage);
            @memset(ptr.modules[s.stages.len..], null_handle);
            ptr.handle = h;
            for (0..s.stages.len) |j| ptr.modules[j] = stages_ptr[j].module;
            stages_ptr += s.stages.len;
            pl.impl = .{ .val = @intFromPtr(ptr) };
        }
    }

    pub fn initCompute(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.Pipeline.Desc(ngl.ComputeState),
        pipelines: []ngl.Pipeline,
    ) Error!void {
        const dev = Device.cast(device);

        var create_infos = try allocator.alloc(c.VkComputePipelineCreateInfo, desc.states.len);
        defer allocator.free(create_infos);

        for (desc.states, create_infos) |state, *info| {
            info.* = .{
                .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stage = undefined, // Set below
                .layout = PipelineLayout.cast(state.layout.impl).handle,
                // TODO: Expose these
                .basePipelineHandle = null_handle,
                .basePipelineIndex = -1,
            };
        }

        var module_create_infos: []c.VkShaderModuleCreateInfo = &.{};
        defer if (module_create_infos.len > 0) allocator.free(module_create_infos);

        var modules = try allocator.alloc(c.VkShaderModule, desc.states.len);
        defer allocator.free(modules);
        errdefer for (modules) |m| {
            if (m == null_handle) break;
            dev.vkDestroyShaderModule(m, null);
        };

        if (false) { // TODO: Don't create modules if maintenance5 is available
            @memset(modules, null);
            // TODO...
        } else {
            for (desc.states, modules, create_infos) |state, *module, *info| {
                errdefer module.* = null_handle;

                try check(dev.vkCreateShaderModule(&.{
                    .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .codeSize = state.stage.code.len,
                    .pCode = @as([*]const u32, @ptrCast(state.stage.code.ptr)),
                }, null, module));

                info.stage = .{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
                    .module = module.*,
                    .pName = state.stage.name,
                    .pSpecializationInfo = null, // TODO
                };
            }
        }

        var handles = try allocator.alloc(c.VkPipeline, create_infos.len);
        defer allocator.free(handles);

        try check(dev.vkCreateComputePipelines(
            if (desc.cache) |x| PipelineCache.cast(x.impl).handle else null_handle,
            @intCast(create_infos.len),
            create_infos.ptr,
            null,
            handles.ptr,
        ));

        for (pipelines, handles, 0..) |*pl, h, i| {
            var ptr = allocator.create(Pipeline) catch |err| {
                for (0..i) |j| {
                    allocator.destroy(cast(pipelines[j].impl));
                    pipelines[j].impl = undefined;
                }
                return err;
            };
            @memset(ptr.modules[1..], null_handle);
            ptr.handle = h;
            ptr.modules[0] = modules[i];
            pl.impl = .{ .val = @intFromPtr(ptr) };
        }
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        pipeline: Impl.Pipeline,
        _: ngl.Pipeline.Type,
    ) void {
        const dev = Device.cast(device);
        const pl = cast(pipeline);
        dev.vkDestroyPipeline(pl.handle, null);
        for (pl.modules) |module|
            if (ndhOrNull(module)) |m| dev.vkDestroyShaderModule(m, null) else break;
        allocator.destroy(pl);
    }
};

pub const PipelineCache = packed struct {
    handle: c.VkPipelineCache,

    pub inline fn cast(impl: Impl.PipelineCache) PipelineCache {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.PipelineCache.Desc,
    ) Error!Impl.PipelineCache {
        var pl_cache: c.VkPipelineCache = undefined;
        try check(Device.cast(device).vkCreatePipelineCache(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .initialDataSize = if (desc.initial_data) |x| x.len else 0,
            .pInitialData = if (desc.initial_data) |x| x.ptr else null,
        }, null, &pl_cache));

        return .{ .val = @bitCast(PipelineCache{ .handle = pl_cache }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        pipeline_cache: Impl.PipelineCache,
    ) void {
        Device.cast(device).vkDestroyPipelineCache(cast(pipeline_cache).handle, null);
    }
};
