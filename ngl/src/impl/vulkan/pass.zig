const std = @import("std");

const c = @import("c");

const ngl = @import("../../ngl.zig");
const ImageView = @import("res.zig").ImageView;
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const conv = @import("conv.zig");
const null_handle = conv.null_handle;
const check = conv.check;
const log = @import("init.zig").log;
const Device = @import("init.zig").Device;

pub const RenderPass = packed struct {
    handle: c.VkRenderPass,

    pub fn cast(impl: Impl.RenderPass) RenderPass {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.RenderPass.Desc,
    ) Error!Impl.RenderPass {
        // TODO:
        // - Input attachment's aspect mask (v1.1/VK_KHR_maintenance2)
        // - Depth/stencil resolve (v1.2/VK_KHR_depth_stencil_resolve)
        // (this requires VkSubpassDescription2)

        var create_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .attachmentCount = undefined,
            .pAttachments = undefined,
            .subpassCount = undefined,
            .pSubpasses = undefined,
            .dependencyCount = undefined,
            .pDependencies = undefined,
        };

        // Attachment descriptions
        const attach_descs = blk: {
            const attachs = desc.attachments orelse &.{};
            if (attachs.len == 0) {
                create_info.attachmentCount = 0;
                create_info.pAttachments = null;
                break :blk null;
            }
            const attach_descs = try allocator.alloc(c.VkAttachmentDescription, attachs.len);
            errdefer allocator.free(attach_descs);
            for (attach_descs, attachs) |*attach_desc, attach| {
                attach_desc.* = .{
                    .flags = if (attach.may_alias) c.VK_ATTACHMENT_DESCRIPTION_MAY_ALIAS_BIT else 0,
                    .format = try conv.toVkFormat(attach.format),
                    .samples = conv.toVkSampleCount(attach.samples),
                    .loadOp = conv.toVkAttachmentLoadOp(attach.load_op),
                    .storeOp = conv.toVkAttachmentStoreOp(attach.store_op),
                    .stencilLoadOp = undefined,
                    .stencilStoreOp = undefined,
                    .initialLayout = conv.toVkImageLayout(attach.initial_layout),
                    .finalLayout = conv.toVkImageLayout(attach.final_layout),
                };
                if (attach.combined) |s| {
                    attach_desc.stencilLoadOp = conv.toVkAttachmentLoadOp(s.stencil_load_op);
                    attach_desc.stencilStoreOp = conv.toVkAttachmentStoreOp(s.stencil_store_op);
                } else {
                    attach_desc.stencilLoadOp = attach_desc.loadOp;
                    attach_desc.stencilStoreOp = attach_desc.storeOp;
                }
            }
            create_info.attachmentCount = @intCast(attachs.len);
            create_info.pAttachments = attach_descs.ptr;
            break :blk attach_descs;
        };
        defer if (attach_descs) |x| allocator.free(x);

        // Subpass descriptions
        const subp_descs = try allocator.alloc(c.VkSubpassDescription, desc.subpasses.len);
        defer allocator.free(subp_descs);
        var attach_refs: ?[]c.VkAttachmentReference = undefined;
        var attach_inds: ?[]u32 = undefined;
        {
            var n: usize = 0;
            var m: usize = 0;
            for (desc.subpasses) |subp| {
                if (subp.input_attachments) |x| n += x.len;
                if (subp.color_attachments) |x| n += x.len;
                if (subp.depth_stencil_attachment != null) n += 1;
                if (subp.preserve_attachments) |x| m += x.len;
            }
            attach_refs = if (n == 0) null else try allocator.alloc(c.VkAttachmentReference, 2 * n);
            errdefer if (attach_refs) |x| allocator.free(x);
            attach_inds = if (m == 0) null else try allocator.alloc(u32, m);
        }
        defer if (attach_refs) |x| allocator.free(x);
        defer if (attach_inds) |x| allocator.free(x);
        {
            var refs_ptr = if (attach_refs) |x| x.ptr else undefined;
            var inds_ptr = if (attach_inds) |x| x.ptr else undefined;
            const unused = c.VkAttachmentReference{
                .attachment = c.VK_ATTACHMENT_UNUSED,
                .layout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            };
            for (subp_descs, desc.subpasses) |*subp_desc, subp| {
                subp_desc.* = .{
                    .flags = 0,
                    .pipelineBindPoint = conv.toVkPipelineBindPoint(subp.pipeline_type),
                    .inputAttachmentCount = undefined,
                    .pInputAttachments = undefined,
                    .colorAttachmentCount = undefined,
                    .pColorAttachments = undefined,
                    .pResolveAttachments = undefined,
                    .pDepthStencilAttachment = undefined,
                    .preserveAttachmentCount = undefined,
                    .pPreserveAttachments = undefined,
                };
                if (subp.input_attachments) |refs| {
                    subp_desc.inputAttachmentCount = @intCast(refs.len);
                    subp_desc.pInputAttachments = refs_ptr;
                    for (refs, 0..) |ref, i| {
                        refs_ptr[i] = if (ref) |r| .{
                            .attachment = r.index,
                            .layout = conv.toVkImageLayout(r.layout),
                        } else unused;
                    }
                    refs_ptr += refs.len;
                } else {
                    subp_desc.inputAttachmentCount = 0;
                    subp_desc.pInputAttachments = null;
                }
                if (subp.color_attachments) |refs| {
                    subp_desc.colorAttachmentCount = @intCast(refs.len);
                    subp_desc.pColorAttachments = refs_ptr;
                    subp_desc.pResolveAttachments = refs_ptr + refs.len;
                    for (refs, 0..) |ref, i| {
                        if (ref) |cr| {
                            refs_ptr[i] = .{
                                .attachment = cr.index,
                                .layout = conv.toVkImageLayout(cr.layout),
                            };
                            refs_ptr[refs.len + i] = if (cr.resolve) |rr| .{
                                .attachment = rr.index,
                                .layout = conv.toVkImageLayout(rr.layout),
                            } else unused;
                        } else {
                            refs_ptr[i] = unused;
                            refs_ptr[refs.len + i] = unused;
                        }
                    }
                    refs_ptr += 2 * refs.len;
                } else {
                    subp_desc.colorAttachmentCount = 0;
                    subp_desc.pColorAttachments = null;
                    subp_desc.pResolveAttachments = null;
                }
                if (subp.depth_stencil_attachment) |ref| {
                    subp_desc.pDepthStencilAttachment = refs_ptr;
                    refs_ptr[0] = .{
                        .attachment = ref.index,
                        .layout = conv.toVkImageLayout(ref.layout),
                    };
                    // TODO
                    if (ref.resolve != null) {
                        log.warn("Depth/stencil resolve not implemented", .{});
                        return Error.NotSupported;
                    }
                    refs_ptr += 2;
                } else {
                    subp_desc.pDepthStencilAttachment = null;
                }
                if (subp.preserve_attachments) |inds| {
                    subp_desc.preserveAttachmentCount = @intCast(inds.len);
                    subp_desc.pPreserveAttachments = inds_ptr;
                    for (inds, 0..) |idx, i| inds_ptr[i] = idx;
                    inds_ptr += inds.len;
                } else {
                    subp_desc.preserveAttachmentCount = 0;
                    subp_desc.pPreserveAttachments = null;
                }
            }
            create_info.subpassCount = @intCast(subp_descs.len);
            create_info.pSubpasses = subp_descs.ptr;
        }

        // Subpass dependencies
        const subp_depends = blk: {
            if (desc.dependencies) |depends| {
                const subp_depends = try allocator.alloc(c.VkSubpassDependency, depends.len);
                for (subp_depends, depends) |*subp_depend, depend| {
                    subp_depend.* = .{
                        .srcSubpass = switch (depend.source_subpass) {
                            .index => |idx| idx,
                            .external => c.VK_SUBPASS_EXTERNAL,
                        },
                        .dstSubpass = switch (depend.dest_subpass) {
                            .index => |idx| idx,
                            .external => c.VK_SUBPASS_EXTERNAL,
                        },
                        .srcStageMask = conv.toVkPipelineStageFlags(.source, depend.source_stage_mask),
                        .dstStageMask = conv.toVkPipelineStageFlags(.dest, depend.dest_stage_mask),
                        .srcAccessMask = conv.toVkAccessFlags(depend.source_access_mask),
                        .dstAccessMask = conv.toVkAccessFlags(depend.dest_access_mask),
                        .dependencyFlags = if (depend.by_region)
                            c.VK_DEPENDENCY_BY_REGION_BIT
                        else
                            0,
                    };
                }
                create_info.dependencyCount = @intCast(depends.len);
                create_info.pDependencies = subp_depends.ptr;
                break :blk subp_depends;
            }
            create_info.dependencyCount = 0;
            create_info.pDependencies = null;
            break :blk null;
        };
        defer if (subp_depends) |x| allocator.free(x);

        // Render pass
        var rp: c.VkRenderPass = undefined;
        try check(Device.cast(device).vkCreateRenderPass(&create_info, null, &rp));
        return .{ .val = @bitCast(RenderPass{ .handle = rp }) };
    }

    pub fn getRenderAreaGranularity(
        _: *anyopaque,
        device: Impl.Device,
        render_pass: Impl.RenderPass,
    ) [2]u32 {
        var gran: c.VkExtent2D = undefined;
        Device.cast(device).vkGetRenderAreaGranularity(cast(render_pass).handle, &gran);
        return .{ gran.width, gran.height };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        render_pass: Impl.RenderPass,
    ) void {
        Device.cast(device).vkDestroyRenderPass(cast(render_pass).handle, null);
    }
};

pub const FrameBuffer = packed struct {
    handle: c.VkFramebuffer,

    pub fn cast(impl: Impl.FrameBuffer) FrameBuffer {
        return @bitCast(impl.val);
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: Impl.Device,
        desc: ngl.FrameBuffer.Desc,
    ) Error!Impl.FrameBuffer {
        const attach_n: u32 = if (desc.attachments) |x| @intCast(x.len) else 0;
        const attachs: ?[]c.VkImageView = blk: {
            if (attach_n == 0) break :blk null;
            const handles = try allocator.alloc(c.VkImageView, attach_n);
            for (handles, desc.attachments.?) |*handle, attach|
                handle.* = ImageView.cast(attach.impl).handle;
            break :blk handles;
        };
        defer if (attachs) |x| allocator.free(x);

        var fb: c.VkFramebuffer = undefined;
        try check(Device.cast(device).vkCreateFramebuffer(&.{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = RenderPass.cast(desc.render_pass.impl).handle,
            .attachmentCount = attach_n,
            .pAttachments = if (attachs) |x| x.ptr else null,
            .width = desc.width,
            .height = desc.height,
            .layers = desc.layers,
        }, null, &fb));

        return .{ .val = @bitCast(FrameBuffer{ .handle = fb }) };
    }

    pub fn deinit(
        _: *anyopaque,
        _: std.mem.Allocator,
        device: Impl.Device,
        frame_buffer: Impl.FrameBuffer,
    ) void {
        Device.cast(device).vkDestroyFramebuffer(cast(frame_buffer).handle, null);
    }
};
