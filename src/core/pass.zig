const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Format = ngl.Format;
const ImageView = ngl.ImageView;
const SampleCount = ngl.SampleCount;
const Image = ngl.Image;
const PipelineStage = ngl.PipelineStage;
const Access = ngl.Access;
const Pipeline = ngl.Pipeline;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const LoadOp = enum {
    load,
    clear,
    dont_care,
};

pub const StoreOp = enum {
    store,
    dont_care,
};

pub const ResolveMode = enum {
    average,
    sample_zero,
    min,
    max,

    pub const Flags = ngl.Flags(ResolveMode);
};

pub const RenderPass = struct {
    impl: Impl.RenderPass,

    pub const Index = u16;
    pub const max_attachment_index = ~@as(Index, 0);
    pub const max_subpass_index = ~@as(Index, 0);

    pub const Attachment = struct {
        format: Format,
        samples: SampleCount,
        load_op: LoadOp,
        store_op: StoreOp,
        initial_layout: Image.Layout,
        final_layout: Image.Layout,
        resolve_mode: ?ResolveMode,
        combined: ?struct {
            stencil_store_op: StoreOp,
            stencil_load_op: LoadOp,
            //stencil_initial_layout: Image.Layout,
            //stencil_final_layout: Image.Layout,
            //stencil_resolve_mode: ?ResolveMode,
        },
        may_alias: bool,

        pub const Ref = struct {
            index: Index,
            layout: Image.Layout,
            aspect_mask: Image.Aspect.Flags,
            resolve: ?struct {
                index: Index,
                layout: Image.Layout,
            },
        };
    };

    pub const Subpass = struct {
        pipeline_type: Pipeline.Type,
        input_attachments: ?[]const ?Attachment.Ref,
        color_attachments: ?[]const ?Attachment.Ref,
        depth_stencil_attachment: ?Attachment.Ref,
        preserve_attachments: ?[]const Index,

        pub const Ref = union(enum) {
            index: Index,
            external,
        };
    };

    pub const Dependency = struct {
        source_subpass: Subpass.Ref,
        dest_subpass: Subpass.Ref,
        source_stage_mask: PipelineStage.Flags,
        source_access_mask: Access.Flags,
        dest_stage_mask: PipelineStage.Flags,
        dest_access_mask: Access.Flags,
        by_region: bool,
    };

    pub const Desc = struct {
        attachments: ?[]const Attachment,
        subpasses: []const Subpass,
        dependencies: ?[]const Dependency,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initRenderPass(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitRenderPass(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};

pub const FrameBuffer = struct {
    impl: Impl.FrameBuffer,

    pub const Desc = struct {
        render_pass: *RenderPass,
        attachments: ?[]const *ImageView,
        width: u32,
        height: u32,
        layers: u32,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initFrameBuffer(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitFrameBuffer(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
