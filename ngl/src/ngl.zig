const std = @import("std");

const root = @import("root");

pub const DriverApi = @import("impl/Impl.zig").DriverApi;
pub const getGpus = @import("core/init.zig").getGpus;
pub const Gpu = @import("core/init.zig").Gpu;
pub const Device = @import("core/init.zig").Device;
pub const Queue = @import("core/init.zig").Queue;
pub const Memory = @import("core/init.zig").Memory;
pub const Feature = @import("core/init.zig").Feature;
pub const CommandPool = @import("core/cmd.zig").CommandPool;
pub const CommandBuffer = @import("core/cmd.zig").CommandBuffer;
pub const Cmd = CommandBuffer.Cmd;
pub const Stage = @import("core/sync.zig").Stage;
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
pub const Shader = @import("core/shd.zig").Shader;
pub const ShaderLayout = @import("core/shd.zig").ShaderLayout;
pub const DescriptorType = @import("core/shd.zig").DescriptorType;
pub const DescriptorSetLayout = @import("core/shd.zig").DescriptorSetLayout;
pub const PushConstantRange = @import("core/shd.zig").PushConstantRange;
pub const DescriptorPool = @import("core/shd.zig").DescriptorPool;
pub const DescriptorSet = @import("core/shd.zig").DescriptorSet;
pub const QueryType = @import("core/query.zig").QueryType;
pub const QueryPool = @import("core/query.zig").QueryPool;
pub const QueryResolve = @import("core/query.zig").QueryResolve;
pub const Surface = @import("core/dpy.zig").Surface;
pub const Swapchain = @import("core/dpy.zig").Swapchain;

pub const Error = error{
    NotReady,
    Timeout,
    InvalidArgument,
    TooManyObjects,
    Fragmentation,
    OutOfMemory,
    NotSupported,
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
            for (e.fields) |f|
                fields = fields ++ &[_]StructField{.{
                    .name = f.name,
                    .type = bool,
                    .default_value = @ptrCast(&false),
                    .is_comptime = false,
                    .alignment = 0,
                }};
        },
        else => @compileError("E must be an enum type"),
    }
    return @Type(.{ .Struct = .{
        .layout = .@"packed",
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn noFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == 0;
}

pub fn allFlagsSet(flags: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == ~@as(U, 0);
}

pub fn eqlFlags(flags: anytype, other: anytype) bool {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @as(U, @bitCast(flags)) == @as(U, @bitCast(other));
}

pub fn andFlags(flags: anytype, mask: @TypeOf(flags)) @TypeOf(flags) {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    const masked = @as(U, @bitCast(flags)) & @as(U, @bitCast(mask));
    return @bitCast(masked);
}

pub fn orFlags(flags: anytype, mask: @TypeOf(flags)) @TypeOf(flags) {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    const masked = @as(U, @bitCast(flags)) | @as(U, @bitCast(mask));
    return @bitCast(masked);
}

pub fn xorFlags(flags: anytype, mask: @TypeOf(flags)) @TypeOf(flags) {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    const masked = @as(U, @bitCast(flags)) ^ @as(U, @bitCast(mask));
    return @bitCast(masked);
}

pub fn notFlags(flags: anytype) @TypeOf(flags) {
    const U = @typeInfo(@TypeOf(flags)).Struct.backing_integer.?;
    return @bitCast(~@as(U, @bitCast(flags)));
}

/// One can define `ngl_options` in the root file to provide their
/// own `Options`.
pub const options: Options = if (@hasDecl(root, "ngl_options")) root.ngl_options else .{};

pub const Options = struct {
    app_name: [:0]const u8 = "",
    app_version: u32 = 0,
    engine_name: [:0]const u8 = "",
    engine_version: u32 = 0,
};

test {
    _ = @import("test/test.zig");
}
