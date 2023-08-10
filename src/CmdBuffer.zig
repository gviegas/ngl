const CmdPool = @import("CmdPool.zig");
const Impl = @import("Impl.zig");
const Inner = Impl.CmdBuffer;
const Texture = @import("Texture.zig");
const TexView = @import("TexView.zig");
const Pipeline = @import("Pipeline.zig");
const DescSet = @import("DescSet.zig");
const Buffer = @import("Buffer.zig");
const Error = @import("main.zig").Error;

pool: *CmdPool,
inner: Inner,
kind: Kind,

pub const Kind = enum {
    direct,
    indirect,
};

pub const Config = struct {
    kind: Kind,
};

const Self = @This();

pub fn free(self: *Self) void {
    self.inner.free(self.*);
    self.* = undefined;
}

// TODO
pub fn begin(self: *Self) Error!void {
    _ = self;
}

// TODO
pub fn end(self: *Self) Error!void {
    _ = self;
}

// TODO
pub fn reset(self: *Self) Error!void {
    _ = self;
}

pub const LoadOp = enum {
    load,
    clear,
    discard,
};

pub const StoreOp = enum {
    store,
    discard,
};

pub const PassAttachment = struct {
    view: *TexView,
    load_op: LoadOp,
    store_op: StoreOp,
    clear_value: union(enum) {
        color: [4]f64,
        depth: f32,
        stencil: u32,
    } = .{ .color = .{ 1, 1, 1, 1 } },
    resolve: ?*TexView = null,
};

pub const Pass = struct {
    width: u32,
    height: u32,
    layers: u32,
    colors: []const PassAttachment,
    depth: ?PassAttachment,
    stencil: ?PassAttachment,
};

// TODO
pub fn beginPass(self: *Self, pass: Pass) void {
    _ = self;
    _ = pass;
}

// TODO
pub fn endPass(self: *Self) void {
    _ = self;
}

pub const SyncScope = packed struct {
    none: bool = false,
    vertex_input: bool = false,
    vertex_shading: bool = false,
    fragment_shading: bool = false,
    ds_output: bool = false,
    color_output: bool = false,
    all_rendering: bool = false,
    compute_shading: bool = false,
    copy: bool = false,
    all: bool = false,
};

pub const SyncAccess = packed struct {
    none: bool = false,
    vertex_buffer_read: bool = false,
    index_buffer_read: bool = false,
    shader_read: bool = false,
    shader_write: bool = false,
    color_read: bool = false,
    color_write: bool = false,
    ds_read: bool = false,
    ds_write: bool = false,
    copy_read: bool = false,
    copy_write: bool = false,
    any_read: bool = false,
    any_write: bool = false,
};

pub const Barrier = struct {
    scope_before: SyncScope,
    scope_after: SyncScope,
    access_before: SyncAccess,
    access_after: SyncAccess,
};

// TODO
pub fn barrier(self: *Self, barriers: []const Barrier) void {
    _ = self;
    _ = barriers;
}

pub const TexLayout = enum {
    undefined,
    shader_store,
    shader_read,
    color_attachment,
    ds_attachment,
    ds_read,
    copy_src,
    copy_dst,
    present,
};

pub const Transition = struct {
    barrier: Barrier,
    layout_before: TexLayout,
    layout_after: TexLayout,
    texture: *Texture,
    first_level: u32,
    levels: u32,
    first_layer: u32,
    layers: u32,
};

// TODO
pub fn transition(self: *Self, transitions: []const Transition) void {
    _ = self;
    _ = transitions;
}

// TODO
pub fn setPipeline(self: *Self, pipeline: *Pipeline) void {
    _ = self;
    _ = pipeline;
}

// TODO
pub fn setDescriptors(
    self: *Self,
    ps_kind: Pipeline.Kind,
    start: u32,
    sets: []const *DescSet,
) void {
    _ = self;
    _ = ps_kind;
    _ = start;
    _ = sets;
}

// TODO
pub fn setBlendColor(self: *Self, r: f32, g: f32, b: f32, a: f32) void {
    _ = self;
    _ = r;
    _ = g;
    _ = b;
    _ = a;
}

// TODO
pub fn setStencilRef(self: *Self, value: u32) void {
    _ = self;
    _ = value;
}

pub const IndexType = enum {
    u16,
    u32,
};

// TODO
pub fn setIndices(self: *Self, index_type: IndexType, buffer: *Buffer, offset: u64) void {
    _ = self;
    _ = index_type;
    _ = buffer;
    _ = offset;
}

// TODO
pub fn setVertices(self: *Self, start: u32, buffers: []const *Buffer, offsets: []const u64) void {
    _ = self;
    _ = start;
    _ = buffers;
    _ = offsets;
}

// TODO
pub fn setViewport(
    self: *Self,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    znear: f32,
    zfar: f32,
) void {
    _ = self;
    _ = x;
    _ = y;
    _ = width;
    _ = height;
    _ = znear;
    _ = zfar;
}

// TODO
pub fn setScissor(self: *Self, x: u32, y: u32, width: u32, height: u32) void {
    _ = self;
    _ = x;
    _ = y;
    _ = width;
    _ = height;
}

// TODO
pub fn draw(
    self: *Self,
    vertex_count: u32,
    instance_count: u32,
    base_vertex: u32,
    base_instance: u32,
) void {
    _ = self;
    _ = vertex_count;
    _ = instance_count;
    _ = base_vertex;
    _ = base_instance;
}

// TODO
pub fn drawIndexed(
    self: *Self,
    index_count: u32,
    instance_count: u32,
    base_index: u32,
    vertex_offset: i32,
    base_instance: u32,
) void {
    _ = self;
    _ = index_count;
    _ = instance_count;
    _ = base_index;
    _ = vertex_offset;
    _ = base_instance;
}

// TODO
pub fn drawIndirect(self: *Self) void {
    _ = self;
}

// TODO
pub fn drawIndexedIndirect(self: *Self) void {
    _ = self;
}

// TODO
pub fn dispatch(self: *Self, group_count_x: u32, group_count_y: u32, group_count_z: u32) void {
    _ = self;
    _ = group_count_x;
    _ = group_count_y;
    _ = group_count_z;
}

// TODO
pub fn dispatchIndirect(self: *Self) void {
    _ = self;
}

pub const TexAspect = enum {
    all,
    depth,
    stencil,
};

pub const TexRegion = struct {
    texture: *Texture,
    level: u32,
    x: u32,
    y: u32,
    z_or_layer: u32,
    aspect: TexAspect,
};

pub const BufTiling = struct {
    buffer: *Buffer,
    offset: u64,
    bytes_per_row: u32,
    rows_per_slice: u32,
};

pub const TexWrite = struct {
    dest: TexRegion,
    src: BufTiling,
    width: u32,
    height: u32,
    depth_or_layers: u32,
};

pub const TexRead = struct {
    dest: BufTiling,
    src: TexRegion,
    width: u32,
    height: u32,
    depth_or_layers: u32,
};

pub const TexCopy = struct {
    dest: TexRegion,
    src: TexRegion,
    width: u32,
    height: u32,
    depth_or_layers: u32,
};

pub const BufCopy = struct {
    dest: *Buffer,
    dest_offset: u64,
    src: *Buffer,
    src_offset: u64,
    size: u64,
};

// TODO
pub fn writeTexture(self: *Self, writes: []const TexWrite) void {
    _ = self;
    _ = writes;
}

// TODO
pub fn readTexture(self: *Self, reads: []const TexRead) void {
    _ = self;
    _ = reads;
}

// TODO
pub fn copyTexture(self: *Self, copies: []const TexCopy) void {
    _ = self;
    _ = copies;
}

// TODO
pub fn copyBuffer(self: *Self, copies: []const BufCopy) void {
    _ = self;
    _ = copies;
}

// TODO
pub fn fillBuffer(self: *Self, buffer: *Buffer, offset: u64, value: u8, size: u64) void {
    _ = self;
    _ = buffer;
    _ = offset;
    _ = value;
    _ = size;
}

// TODO
pub fn debugMarker(self: *Self) void {
    _ = self;
}

pub fn impl(self: Self) *const Impl {
    return self.pool.device.impl;
}
