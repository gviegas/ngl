const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const Error = ngl.Error;

ptr: *anyopaque,
vtable: *const VTable,

/// It should be instantiated with a different `T` every time
/// to guarantee type safety.
fn Type(comptime T: type) type {
    return struct {
        val: u64,

        pub inline fn ptr(self: @This(), comptime Pointee: type) *Pointee {
            const p: *anyopaque = @ptrFromInt(self.val);
            return @ptrCast(@alignCast(p));
        }

        pub const ApiType = T;
    };
}

pub const Instance = Type(ngl.Instance);
pub const Device = Type(ngl.Device);
pub const Queue = Type(ngl.Queue);
pub const Memory = Type(ngl.Memory);
pub const CommandPool = Type(ngl.CommandPool);
pub const CommandBuffer = Type(ngl.CommandBuffer);
pub const Fence = Type(ngl.Fence);
pub const Semaphore = Type(ngl.Semaphore);
pub const Buffer = Type(ngl.Buffer);
pub const BufferView = Type(ngl.BufferView);
pub const Image = Type(ngl.Image);
pub const ImageView = Type(ngl.ImageView);
pub const Sampler = Type(ngl.Sampler);
pub const RenderPass = Type(ngl.RenderPass);
pub const FrameBuffer = Type(ngl.FrameBuffer);
pub const DescriptorSetLayout = Type(ngl.DescriptorSetLayout);
pub const PipelineLayout = Type(ngl.PipelineLayout);
pub const DescriptorPool = Type(ngl.DescriptorPool);
pub const DescriptorSet = Type(ngl.DescriptorSet);
pub const Pipeline = Type(ngl.Pipeline);
pub const PipelineCache = Type(ngl.PipelineCache);

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    // Instance --------------------------------------------

    initInstance: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        desc: ngl.Instance.Desc,
    ) Error!Instance,

    listDevices: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Instance,
    ) Error![]ngl.Device.Desc,

    deinitInstance: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Instance,
    ) void,

    // Device ----------------------------------------------

    initDevice: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: Instance,
        desc: ngl.Device.Desc,
    ) Error!Device,

    getQueues: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Queue.max]Queue,
        device: Device,
    ) []Queue,

    getMemoryTypes: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
        device: Device,
    ) []ngl.Memory.Type,

    allocMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Memory.Desc,
    ) Error!Memory,

    freeMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
    ) void,

    waitDevice: *const fn (ctx: *anyopaque, device: Device) Error!void,

    deinitDevice: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, device: Device) void,

    // Queue -----------------------------------------------

    submit: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        queue: Queue,
        fence: ?Fence,
        submits: []const ngl.Queue.Submit,
    ) Error!void,

    waitQueue: *const fn (ctx: *anyopaque, device: Device, queue: Queue) Error!void,

    // Memory ----------------------------------------------

    mapMemory: *const fn (
        ctx: *anyopaque,
        device: Device,
        memory: Memory,
        offset: u64,
        size: ?u64,
    ) Error![*]u8,

    unmapMemory: *const fn (ctx: *anyopaque, device: Device, memory: Memory) void,

    flushMappedMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void,

    invalidateMappedMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void,

    // CommandPool -----------------------------------------

    initCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.CommandPool.Desc,
    ) Error!CommandPool,

    allocCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void,

    resetCommandPool: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_pool: CommandPool,
    ) Error!void,

    freeCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
        command_buffers: []const *ngl.CommandBuffer,
    ) void,

    deinitCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
    ) void,

    // CommandBuffer ---------------------------------------

    beginCommandBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        desc: ngl.CommandBuffer.Cmd.Desc,
    ) Error!void,

    setPipeline: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        type: ngl.Pipeline.Type,
        pipeline: Pipeline,
    ) void,

    setDescriptors: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        pipeline_type: ngl.Pipeline.Type,
        pipeline_layout: PipelineLayout,
        first_set: u32,
        descriptor_sets: []const *ngl.DescriptorSet,
    ) void,

    setPushConstants: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        pipeline_layout: PipelineLayout,
        stage_mask: ngl.ShaderStage.Flags,
        offset: u16,
        constants: []align(4) const u8,
    ) void,

    setIndexBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        index_type: ngl.CommandBuffer.Cmd.IndexType,
        buffer: Buffer,
        offset: u64,
        size: u64,
    ) void,

    setVertexBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        first_binding: u32,
        buffers: []const *ngl.Buffer,
        offsets: []const u64,
        sizes: []const u64,
    ) void,

    setViewport: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        viewport: ngl.Viewport,
    ) void,

    setStencilReference: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stencil_face: ngl.CommandBuffer.Cmd.StencilFace,
        reference: u32,
    ) void,

    setBlendConstants: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        constants: [4]f32,
    ) void,

    beginRenderPass: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        render_pass_begin: ngl.CommandBuffer.Cmd.RenderPassBegin,
        subpass_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
    ) void,

    nextSubpass: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        next_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
        current_end: ngl.CommandBuffer.Cmd.SubpassEnd,
    ) void,

    endRenderPass: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        subpass_end: ngl.CommandBuffer.Cmd.SubpassEnd,
    ) void,

    executeCommands: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        secondary_command_buffers: []const *ngl.CommandBuffer,
    ) void,

    endCommandBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
    ) Error!void,

    // Fence -----------------------------------------------

    initFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Fence.Desc,
    ) Error!Fence,

    resetFences: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        fences: []const *ngl.Fence,
    ) Error!void,

    waitFences: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        timeout: u64,
        fences: []const *ngl.Fence,
    ) Error!void,

    getFenceStatus: *const fn (
        ctx: *anyopaque,
        device: Device,
        fence: Fence,
    ) Error!ngl.Fence.Status,

    deinitFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        fence: Fence,
    ) void,

    // Semaphore -------------------------------------------

    initSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Semaphore.Desc,
    ) Error!Semaphore,

    deinitSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        semaphore: Semaphore,
    ) void,

    // Buffer ----------------------------------------------

    initBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Buffer.Desc,
    ) Error!Buffer,

    getMemoryRequirementsBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        buffer: Buffer,
    ) ngl.Memory.Requirements,

    bindMemoryBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        buffer: Buffer,
        memory: Memory,
        memory_offset: u64,
    ) Error!void,

    deinitBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        buffer: Buffer,
    ) void,

    // BufferView ------------------------------------------

    initBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.BufferView.Desc,
    ) Error!BufferView,

    deinitBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        buffer: BufferView,
    ) void,

    // Image -----------------------------------------------

    initImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Image.Desc,
    ) Error!Image,

    getMemoryRequirementsImage: *const fn (
        ctx: *anyopaque,
        device: Device,
        image: Image,
    ) ngl.Memory.Requirements,

    bindMemoryImage: *const fn (
        ctx: *anyopaque,
        device: Device,
        image: Image,
        memory: Memory,
        memory_offset: u64,
    ) Error!void,

    deinitImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        image: Image,
    ) void,

    // ImageView -------------------------------------------

    initImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.ImageView.Desc,
    ) Error!ImageView,

    deinitImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        image_view: ImageView,
    ) void,

    // Sampler ---------------------------------------------

    initSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Sampler.Desc,
    ) Error!Sampler,

    deinitSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        sampler: Sampler,
    ) void,

    // RenderPass ------------------------------------------

    initRenderPass: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.RenderPass.Desc,
    ) Error!RenderPass,

    deinitRenderPass: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        render_pass: RenderPass,
    ) void,

    // FrameBuffer -----------------------------------------

    initFrameBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.FrameBuffer.Desc,
    ) Error!FrameBuffer,

    deinitFrameBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        frame_buffer: FrameBuffer,
    ) void,

    // DescriptorSetLayout ---------------------------------

    initDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!DescriptorSetLayout,

    deinitDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_set_layout: DescriptorSetLayout,
    ) void,

    // PipelineLayout --------------------------------------

    initPipelineLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.PipelineLayout.Desc,
    ) Error!PipelineLayout,

    deinitPipelineLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        pipeline_layout: PipelineLayout,
    ) void,

    // DescriptorPool --------------------------------------

    initDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!DescriptorPool,

    allocDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_pool: DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void,

    resetDescriptorPool: *const fn (
        ctx: *anyopaque,
        device: Device,
        descriptor_pool: DescriptorPool,
    ) Error!void,

    deinitDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_pool: DescriptorPool,
    ) void,

    // DescriptorSet ---------------------------------------

    writeDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        writes: []const ngl.DescriptorSet.Write,
    ) Error!void,

    // Pipeline --------------------------------------------

    initPipelinesGraphics: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Pipeline.Desc(ngl.GraphicsState),
        pipelines: []ngl.Pipeline,
    ) Error!void,

    initPipelinesCompute: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Pipeline.Desc(ngl.ComputeState),
        pipelines: []ngl.Pipeline,
    ) Error!void,

    deinitPipeline: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        pipeline: Pipeline,
        type: ngl.Pipeline.Type,
    ) void,

    // PipelineCache ---------------------------------------

    initPipelineCache: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.PipelineCache.Desc,
    ) Error!PipelineCache,

    deinitPipelineCache: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        pipeline_cache: PipelineCache,
    ) void,
};

const Self = @This();

var lock = std.Thread.Mutex{};
var impl: ?Self = null;
// TODO: This isn't needed currently
var gpa: ?std.mem.Allocator = null;

/// It's only valid to call this after `init()` succeeds.
/// `deinit()` invalidates the `Impl`. Don't store it.
pub inline fn get() *Self {
    std.debug.assert(impl != null);
    return &impl.?;
}

// TODO: Debug-check inputs/outputs of these functions

// TODO: Parameters
pub fn init(allocator: std.mem.Allocator) Error!void {
    lock.lock();
    defer lock.unlock();
    if (impl) |_| return;
    impl = switch (builtin.os.tag) {
        .linux, .windows => try @import("vulkan/init.zig").init(),
        else => return Error.NotSupported,
    };
    gpa = allocator;
}

pub fn deinit(self: *Self) void {
    lock.lock();
    defer lock.unlock();
    self.vtable.deinit(self.ptr, gpa.?);
    self.* = undefined;
    impl = null;
    gpa = null;
}

pub fn initInstance(
    self: *Self,
    allocator: std.mem.Allocator,
    desc: ngl.Instance.Desc,
) Error!Instance {
    return self.vtable.initInstance(self.ptr, allocator, desc);
}

pub fn listDevices(
    self: *Self,
    allocator: std.mem.Allocator,
    instance: Instance,
) Error![]ngl.Device.Desc {
    return self.vtable.listDevices(self.ptr, allocator, instance);
}

pub fn deinitInstance(self: *Self, allocator: std.mem.Allocator, instance: Instance) void {
    self.vtable.deinitInstance(self.ptr, allocator, instance);
}

pub fn initDevice(
    self: *Self,
    allocator: std.mem.Allocator,
    instance: Instance,
    desc: ngl.Device.Desc,
) Error!Device {
    return self.vtable.initDevice(self.ptr, allocator, instance, desc);
}

pub fn getQueues(self: *Self, allocation: *[ngl.Queue.max]Queue, device: Device) []Queue {
    return self.vtable.getQueues(self.ptr, allocation, device);
}

pub fn getMemoryTypes(
    self: *Self,
    allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
    device: Device,
) []ngl.Memory.Type {
    return self.vtable.getMemoryTypes(self.ptr, allocation, device);
}

pub fn allocMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Memory.Desc,
) Error!Memory {
    return self.vtable.allocMemory(self.ptr, allocator, device, desc);
}

pub fn freeMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
) void {
    self.vtable.freeMemory(self.ptr, allocator, device, memory);
}

pub fn waitDevice(self: *Self, device: Device) Error!void {
    return self.vtable.waitDevice(self.ptr, device);
}

pub fn deinitDevice(self: *Self, allocator: std.mem.Allocator, device: Device) void {
    self.vtable.deinitDevice(self.ptr, allocator, device);
}

pub fn submit(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    queue: Queue,
    fence: ?Fence,
    submits: []const ngl.Queue.Submit,
) Error!void {
    return self.vtable.submit(self.ptr, allocator, device, queue, fence, submits);
}

pub fn waitQueue(self: *Self, device: Device, queue: Queue) Error!void {
    return self.vtable.waitQueue(self.ptr, device, queue);
}

pub fn mapMemory(self: *Self, device: Device, memory: Memory, offset: u64, size: ?u64) Error![*]u8 {
    return self.vtable.mapMemory(self.ptr, device, memory, offset, size);
}

pub fn unmapMemory(self: *Self, device: Device, memory: Memory) void {
    self.vtable.unmapMemory(self.ptr, device, memory);
}

pub fn flushMappedMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
    offsets: []const u64,
    sizes: ?[]const u64,
) Error!void {
    return self.vtable.flushMappedMemory(self.ptr, allocator, device, memory, offsets, sizes);
}

pub fn invalidateMappedMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
    offsets: []const u64,
    sizes: ?[]const u64,
) Error!void {
    return self.vtable.invalidateMappedMemory(self.ptr, allocator, device, memory, offsets, sizes);
}

pub fn initCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.CommandPool.Desc,
) Error!CommandPool {
    return self.vtable.initCommandPool(self.ptr, allocator, device, desc);
}

pub fn allocCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
    desc: ngl.CommandBuffer.Desc,
    command_buffers: []ngl.CommandBuffer,
) Error!void {
    return self.vtable.allocCommandBuffers(
        self.ptr,
        allocator,
        device,
        command_pool,
        desc,
        command_buffers,
    );
}

pub fn resetCommandPool(self: *Self, device: Device, command_pool: CommandPool) Error!void {
    return self.vtable.resetCommandPool(self.ptr, device, command_pool);
}

pub fn freeCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
    command_buffers: []const *ngl.CommandBuffer,
) void {
    self.vtable.freeCommandBuffers(self.ptr, allocator, device, command_pool, command_buffers);
}

pub fn deinitCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
) void {
    self.vtable.deinitCommandPool(self.ptr, allocator, device, command_pool);
}

pub fn beginCommandBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    desc: ngl.CommandBuffer.Cmd.Desc,
) Error!void {
    return self.vtable.beginCommandBuffer(self.ptr, allocator, device, command_buffer, desc);
}

pub fn setPipeline(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    @"type": ngl.Pipeline.Type,
    pipeline: Pipeline,
) void {
    self.vtable.setPipeline(self.ptr, device, command_buffer, @"type", pipeline);
}

pub fn setDescriptors(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    pipeline_type: ngl.Pipeline.Type,
    pipeline_layout: PipelineLayout,
    first_set: u32,
    descriptor_sets: []const *ngl.DescriptorSet,
) void {
    self.vtable.setDescriptors(
        self.ptr,
        allocator,
        device,
        command_buffer,
        pipeline_type,
        pipeline_layout,
        first_set,
        descriptor_sets,
    );
}

pub fn setPushConstants(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    pipeline_layout: PipelineLayout,
    stage_mask: ngl.ShaderStage.Flags,
    offset: u16,
    constants: []align(4) const u8,
) void {
    self.vtable.setPushConstants(
        self.ptr,
        device,
        command_buffer,
        pipeline_layout,
        stage_mask,
        offset,
        constants,
    );
}

pub fn setIndexBuffer(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    index_type: ngl.CommandBuffer.Cmd.IndexType,
    buffer: Buffer,
    offset: u64,
    size: u64,
) void {
    self.vtable.setIndexBuffer(self.ptr, device, command_buffer, index_type, buffer, offset, size);
}

pub fn setVertexBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    first_binding: u32,
    buffers: []const *ngl.Buffer,
    offsets: []const u64,
    sizes: []const u64,
) void {
    self.vtable.setVertexBuffers(
        self.ptr,
        allocator,
        device,
        command_buffer,
        first_binding,
        buffers,
        offsets,
        sizes,
    );
}

pub fn setViewport(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    viewport: ngl.Viewport,
) void {
    self.vtable.setViewport(self.ptr, device, command_buffer, viewport);
}

pub fn setStencilReference(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stencil_face: ngl.CommandBuffer.Cmd.StencilFace,
    reference: u32,
) void {
    self.vtable.setStencilReference(self.ptr, device, command_buffer, stencil_face, reference);
}

pub fn setBlendConstants(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    constants: [4]f32,
) void {
    self.vtable.setBlendConstants(self.ptr, device, command_buffer, constants);
}

pub fn beginRenderPass(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    render_pass_begin: ngl.CommandBuffer.Cmd.RenderPassBegin,
    subpass_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
) void {
    self.vtable.beginRenderPass(
        self.ptr,
        allocator,
        device,
        command_buffer,
        render_pass_begin,
        subpass_begin,
    );
}

pub fn nextSubpass(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    next_begin: ngl.CommandBuffer.Cmd.SubpassBegin,
    current_end: ngl.CommandBuffer.Cmd.SubpassEnd,
) void {
    self.vtable.nextSubpass(self.ptr, device, command_buffer, next_begin, current_end);
}

pub fn endRenderPass(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    subpass_end: ngl.CommandBuffer.Cmd.SubpassEnd,
) void {
    self.vtable.endRenderPass(self.ptr, device, command_buffer, subpass_end);
}

pub fn executeCommands(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    secondary_command_buffers: []const *ngl.CommandBuffer,
) void {
    self.vtable.executeCommands(
        self.ptr,
        allocator,
        device,
        command_buffer,
        secondary_command_buffers,
    );
}

pub fn endCommandBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
) Error!void {
    return self.vtable.endCommandBuffer(self.ptr, allocator, device, command_buffer);
}

pub fn initFence(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Fence.Desc,
) Error!Fence {
    return self.vtable.initFence(self.ptr, allocator, device, desc);
}

pub fn resetFences(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    fences: []const *ngl.Fence,
) Error!void {
    return self.vtable.resetFences(self.ptr, allocator, device, fences);
}

pub fn waitFences(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    timeout: u64,
    fences: []const *ngl.Fence,
) Error!void {
    return self.vtable.waitFences(self.ptr, allocator, device, timeout, fences);
}

pub fn getFenceStatus(self: *Self, device: Device, fence: Fence) Error!ngl.Fence.Status {
    return self.vtable.getFenceStatus(self.ptr, device, fence);
}

pub fn deinitFence(self: *Self, allocator: std.mem.Allocator, device: Device, fence: Fence) void {
    self.vtable.deinitFence(self.ptr, allocator, device, fence);
}

pub fn initSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Semaphore.Desc,
) Error!Semaphore {
    return self.vtable.initSemaphore(self.ptr, allocator, device, desc);
}

pub fn deinitSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    semaphore: Semaphore,
) void {
    self.vtable.deinitSemaphore(self.ptr, allocator, device, semaphore);
}

pub fn initBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Buffer.Desc,
) Error!Buffer {
    return self.vtable.initBuffer(self.ptr, allocator, device, desc);
}

pub fn getMemoryRequirementsBuffer(
    self: *Self,
    device: Device,
    buffer: Buffer,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsBuffer(self.ptr, device, buffer);
}

pub fn bindMemoryBuffer(
    self: *Self,
    device: Device,
    buffer: Buffer,
    memory: Memory,
    memory_offset: u64,
) Error!void {
    return self.vtable.bindMemoryBuffer(self.ptr, device, buffer, memory, memory_offset);
}

pub fn deinitBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    buffer: Buffer,
) void {
    self.vtable.deinitBuffer(self.ptr, allocator, device, buffer);
}

pub fn initBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.BufferView.Desc,
) Error!BufferView {
    return self.vtable.initBufferView(self.ptr, allocator, device, desc);
}

pub fn deinitBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    buffer_view: BufferView,
) void {
    self.vtable.deinitBufferView(self.ptr, allocator, device, buffer_view);
}

pub fn initImage(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Image.Desc,
) Error!Image {
    return self.vtable.initImage(self.ptr, allocator, device, desc);
}

pub fn deinitImage(self: *Self, allocator: std.mem.Allocator, device: Device, image: Image) void {
    self.vtable.deinitImage(self.ptr, allocator, device, image);
}

pub fn getMemoryRequirementsImage(
    self: *Self,
    device: Device,
    image: Image,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsImage(self.ptr, device, image);
}

pub fn bindMemoryImage(
    self: *Self,
    device: Device,
    image: Image,
    memory: Memory,
    memory_offset: u64,
) Error!void {
    return self.vtable.bindMemoryImage(self.ptr, device, image, memory, memory_offset);
}

pub fn initImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.ImageView.Desc,
) Error!ImageView {
    return self.vtable.initImageView(self.ptr, allocator, device, desc);
}

pub fn deinitImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    image_view: ImageView,
) void {
    self.vtable.deinitImageView(self.ptr, allocator, device, image_view);
}

pub fn initSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Sampler.Desc,
) Error!Sampler {
    return self.vtable.initSampler(self.ptr, allocator, device, desc);
}

pub fn deinitSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    sampler: Sampler,
) void {
    self.vtable.deinitSampler(self.ptr, allocator, device, sampler);
}

pub fn initRenderPass(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.RenderPass.Desc,
) Error!RenderPass {
    return self.vtable.initRenderPass(self.ptr, allocator, device, desc);
}

pub fn deinitRenderPass(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    render_pass: RenderPass,
) void {
    self.vtable.deinitRenderPass(self.ptr, allocator, device, render_pass);
}

pub fn initFrameBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.FrameBuffer.Desc,
) Error!FrameBuffer {
    return self.vtable.initFrameBuffer(self.ptr, allocator, device, desc);
}

pub fn deinitFrameBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    frame_buffer: FrameBuffer,
) void {
    self.vtable.deinitFrameBuffer(self.ptr, allocator, device, frame_buffer);
}

pub fn initDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.DescriptorSetLayout.Desc,
) Error!DescriptorSetLayout {
    return self.vtable.initDescriptorSetLayout(self.ptr, allocator, device, desc);
}

pub fn deinitDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_set_layout: DescriptorSetLayout,
) void {
    self.vtable.deinitDescriptorSetLayout(self.ptr, allocator, device, descriptor_set_layout);
}

pub fn initPipelineLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.PipelineLayout.Desc,
) Error!PipelineLayout {
    return self.vtable.initPipelineLayout(self.ptr, allocator, device, desc);
}

pub fn deinitPipelineLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    pipeline_layout: PipelineLayout,
) void {
    self.vtable.deinitPipelineLayout(self.ptr, allocator, device, pipeline_layout);
}

pub fn initDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.DescriptorPool.Desc,
) Error!DescriptorPool {
    return self.vtable.initDescriptorPool(self.ptr, allocator, device, desc);
}

pub fn allocDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_pool: DescriptorPool,
    desc: ngl.DescriptorSet.Desc,
    descriptor_sets: []ngl.DescriptorSet,
) Error!void {
    return self.vtable.allocDescriptorSets(
        self.ptr,
        allocator,
        device,
        descriptor_pool,
        desc,
        descriptor_sets,
    );
}

pub fn resetDescriptorPool(
    self: *Self,
    device: Device,
    descriptor_pool: DescriptorPool,
) Error!void {
    return self.vtable.resetDescriptorPool(self.ptr, device, descriptor_pool);
}

pub fn deinitDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_pool: DescriptorPool,
) void {
    self.vtable.deinitDescriptorPool(self.ptr, allocator, device, descriptor_pool);
}

pub fn writeDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    writes: []const ngl.DescriptorSet.Write,
) Error!void {
    return self.vtable.writeDescriptorSets(self.ptr, allocator, device, writes);
}

pub fn initPipelinesGraphics(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Pipeline.Desc(ngl.GraphicsState),
    pipelines: []ngl.Pipeline,
) Error!void {
    return self.vtable.initPipelinesGraphics(self.ptr, allocator, device, desc, pipelines);
}

pub fn initPipelinesCompute(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Pipeline.Desc(ngl.ComputeState),
    pipelines: []ngl.Pipeline,
) Error!void {
    return self.vtable.initPipelinesCompute(self.ptr, allocator, device, desc, pipelines);
}

pub fn deinitPipeline(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    pipeline: Pipeline,
    @"type": ngl.Pipeline.Type,
) void {
    self.vtable.deinitPipeline(self, allocator, device, pipeline, @"type");
}

pub fn initPipelineCache(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.PipelineCache.Desc,
) Error!PipelineCache {
    return self.vtable.initPipelineCache(self.ptr, allocator, device, desc);
}

pub fn deinitPipelineCache(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    pipeline_cache: PipelineCache,
) void {
    self.vtable.deinitPipelineCache(self.ptr, allocator, device, pipeline_cache);
}
