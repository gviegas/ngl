const std = @import("std");

const Impl = @import("impl/Impl.zig");

pub const Instance = @import("core/init.zig").Instance;
pub const DriverApi = Impl.DriverApi;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;
pub const Memory = @import("core/init.zig").Memory;
pub const Feature = @import("core/init.zig").Feature;
pub const CommandPool = @import("core/cmd.zig").CommandPool;
pub const CommandBuffer = @import("core/cmd.zig").CommandBuffer;
pub const Cmd = CommandBuffer.Cmd;
pub const PipelineStage = @import("core/sync.zig").PipelineStage;
pub const Access = @import("core/sync.zig").Access;
pub const Fence = @import("core/sync.zig").Fence;
pub const Semaphore = @import("core/sync.zig").Semaphore;
pub const Format = @import("core/res.zig").Format;
pub const Buffer = @import("core/res.zig").Buffer;
pub const BufferView = @import("core/res.zig").BufferView;
pub const SampleCount = @import("core/res.zig").SampleCount;
pub const Image = @import("core/res.zig").Image;
pub const ImageView = @import("core/res.zig").ImageView;
pub const CompareOp = @import("core/res.zig").CompareOp;
pub const Sampler = @import("core/res.zig").Sampler;
pub const LoadOp = @import("core/pass.zig").LoadOp;
pub const StoreOp = @import("core/pass.zig").StoreOp;
pub const ResolveMode = @import("core/pass.zig").ResolveMode;
pub const RenderPass = @import("core/pass.zig").RenderPass;
pub const FrameBuffer = @import("core/pass.zig").FrameBuffer;
pub const DescriptorType = @import("core/desc.zig").DescriptorType;
pub const DescriptorSetLayout = @import("core/desc.zig").DescriptorSetLayout;
pub const PushConstantRange = @import("core/desc/zig").PushConstantRange;
pub const PipelineLayout = @import("core/desc.zig").PipelineLayout;
pub const DescriptorPool = @import("core/desc.zig").DescriptorPool;
pub const DescriptorSet = @import("core/desc.zig").DescriptorSet;
pub const Pipeline = @import("core/state.zig").Pipeline;
pub const ShaderStage = @import("core/state.zig").ShaderStage;
pub const Primitive = @import("core/state.zig").Primitive;
pub const Viewport = @import("core/state.zig").Viewport;
pub const Rasterization = @import("core/state.zig").Rasterization;
pub const DepthStencil = @import("core/state.zig").DepthStencil;
pub const ColorBlend = @import("core/state.zig").ColorBlend;
pub const GraphicsState = @import("core/state.zig").GraphicsState;
pub const ComputeState = @import("core/state.zig").ComputeState;
pub const PipelineCache = @import("core/state.zig").PipelineCache;
pub const Surface = @import("core/dpy.zig").Surface;
pub const SwapChain = @import("core/dpy.zig").SwapChain;

pub const Error = error{
    NotReady,
    Timeout,
    InvalidArgument,
    TooManyObjects,
    Fragmentation,
    OutOfMemory,
    NotSupported,
    NotPresent,
    InitializationFailed,
    DeviceLost,
    SurfaceLost,
    WindowInUse,
    OutOfDate,
    Other,
};

pub fn Flags(comptime E: type) type {
    const StructField = std.builtin.Type.StructField;
    var fields: []const StructField = &[_]StructField{};
    switch (@typeInfo(E)) {
        .Enum => |e| {
            for (e.fields) |f| {
                fields = fields ++ &[1]StructField{.{
                    .name = f.name,
                    .type = bool,
                    .default_value = @ptrCast(&false),
                    .is_comptime = false,
                    .alignment = 0,
                }};
            }
        },
        else => @compileError("E must be an enum type"),
    }
    return @Type(.{ .Struct = .{
        .layout = .Packed,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub inline fn noFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == 0;
}

pub inline fn allFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == ~@as(U, 0);
}

/// This can be overriden by defining `ngl_options` in the root file.
pub const options = struct {
    const root = @import("root");
    const override = if (@hasDecl(root, "ngl_options")) root.ngl_options else struct {};

    pub const app_name: ?[*:0]const u8 = if (@hasDecl(override, "app_name"))
        override.app_name
    else
        null;

    pub const app_version: ?u32 = if (@hasDecl(override, "app_version"))
        override.app_version
    else
        null;

    pub const engine_name: ?[*:0]const u8 = if (@hasDecl(override, "engine_name"))
        override.engine_name
    else
        null;

    pub const engine_version: ?u32 = if (@hasDecl(override, "engine_version"))
        override.engine_version
    else
        null;
};

test {
    _ = @import("test/test.zig");
}
