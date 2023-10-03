const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const Error = ngl.Error;

ptr: *anyopaque,
vtable: *const VTable,

pub const Instance = opaque {};
pub const Device = opaque {};
pub const Queue = opaque {};
pub const Memory = opaque {};
pub const CommandPool = opaque {};
pub const CommandBuffer = opaque {};
pub const Fence = opaque {};
pub const Semaphore = opaque {};
pub const Buffer = opaque {};
pub const BufferView = opaque {};
pub const Image = opaque {};
pub const ImageView = opaque {};
pub const Sampler = opaque {};
pub const RenderPass = opaque {};
pub const FrameBuffer = opaque {};
pub const DescriptorSetLayout = opaque {};
pub const PipelineLayout = opaque {};
pub const DescriptorPool = opaque {};
pub const DescriptorSet = opaque {};
pub const Pipeline = opaque {};
pub const PipelineCache = opaque {};

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    // Instance --------------------------------------------

    initInstance: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        desc: ngl.Instance.Desc,
    ) Error!*Instance,

    listDevices: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: *Instance,
    ) Error![]ngl.Device.Desc,

    deinitInstance: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: *Instance,
    ) void,

    // Device ----------------------------------------------

    initDevice: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        instance: *Instance,
        desc: ngl.Device.Desc,
    ) Error!*Device,

    getQueues: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Queue.max]*Queue,
        device: *Device,
    ) []*Queue,

    getMemoryTypes: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
        device: *Device,
    ) []ngl.Memory.Type,

    allocMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Memory.Desc,
    ) Error!*Memory,

    freeMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        memory: *Memory,
    ) void,

    deinitDevice: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, device: *Device) void,

    // CommandPool -----------------------------------------

    initCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.CommandPool.Desc,
    ) Error!*CommandPool,

    allocCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        command_pool: *CommandPool,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void,

    freeCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        command_pool: *CommandPool,
        command_buffers: []const ngl.CommandBuffer,
    ) void,

    deinitCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        command_pool: *CommandPool,
    ) void,

    // CommandBuffer ---------------------------------------

    // TODO

    // Fence -----------------------------------------------

    initFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Fence.Desc,
    ) Error!*Fence,

    deinitFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        fence: *Fence,
    ) void,

    // Semaphore -------------------------------------------

    initSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Semaphore.Desc,
    ) Error!*Semaphore,

    deinitSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        semaphore: *Semaphore,
    ) void,

    // Buffer ----------------------------------------------

    initBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Buffer.Desc,
    ) Error!*Buffer,

    getMemoryRequirementsBuffer: *const fn (
        ctx: *anyopaque,
        device: *Device,
        buffer: *Buffer,
    ) ngl.Memory.Requirements,

    deinitBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        buffer: *Buffer,
    ) void,

    // BufferView ------------------------------------------

    initBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.BufferView.Desc,
    ) Error!*BufferView,

    deinitBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        buffer: *BufferView,
    ) void,

    // Image -----------------------------------------------

    initImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Image.Desc,
    ) Error!*Image,

    getMemoryRequirementsImage: *const fn (
        ctx: *anyopaque,
        device: *Device,
        image: *Image,
    ) ngl.Memory.Requirements,

    deinitImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        image: *Image,
    ) void,

    // ImageView -------------------------------------------

    initImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.ImageView.Desc,
    ) Error!*ImageView,

    deinitImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        image_view: *ImageView,
    ) void,

    // Sampler ---------------------------------------------

    initSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Sampler.Desc,
    ) Error!*Sampler,

    deinitSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        sampler: *Sampler,
    ) void,

    // RenderPass ------------------------------------------

    initRenderPass: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.RenderPass.Desc,
    ) Error!*RenderPass,

    deinitRenderPass: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        render_pass: *RenderPass,
    ) void,

    // FrameBuffer -----------------------------------------

    initFrameBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.FrameBuffer.Desc,
    ) Error!*FrameBuffer,

    deinitFrameBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        frame_buffer: *FrameBuffer,
    ) void,

    // DescriptorSetLayout ---------------------------------

    initDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!*DescriptorSetLayout,

    deinitDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        descriptor_set_layout: *DescriptorSetLayout,
    ) void,

    // PipelineLayout --------------------------------------

    initPipelineLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.PipelineLayout.Desc,
    ) Error!*PipelineLayout,

    deinitPipelineLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        pipeline_layout: *PipelineLayout,
    ) void,

    // DescriptorPool --------------------------------------

    initDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!*DescriptorPool,

    allocDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        descriptor_pool: *DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void,

    freeDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        descriptor_pool: *DescriptorPool,
        descriptor_sets: []const ngl.DescriptorSet,
    ) void,

    deinitDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        descriptor_pool: *DescriptorPool,
    ) void,

    // Pipeline --------------------------------------------

    initPipelinesGraphics: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Pipeline.Desc(ngl.GraphicsState),
        pipelines: []ngl.Pipeline,
    ) Error!void,

    initPipelinesCompute: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.Pipeline.Desc(ngl.ComputeState),
        pipelines: []ngl.Pipeline,
    ) Error!void,

    deinitPipeline: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        pipeline: *Pipeline,
        type: ngl.Pipeline.Type,
    ) void,

    // PipelineCache ---------------------------------------

    initPipelineCache: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        desc: ngl.PipelineCache.Desc,
    ) Error!*PipelineCache,

    deinitPipelineCache: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        pipeline_cache: *PipelineCache,
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
) Error!*Instance {
    return self.vtable.initInstance(self.ptr, allocator, desc);
}

pub fn listDevices(
    self: *Self,
    allocator: std.mem.Allocator,
    instance: *Instance,
) Error![]ngl.Device.Desc {
    return self.vtable.listDevices(self.ptr, allocator, instance);
}

pub fn deinitInstance(self: *Self, allocator: std.mem.Allocator, instance: *Instance) void {
    self.vtable.deinitInstance(self.ptr, allocator, instance);
}

pub fn initDevice(
    self: *Self,
    allocator: std.mem.Allocator,
    instance: *Instance,
    desc: ngl.Device.Desc,
) Error!*Device {
    return self.vtable.initDevice(self.ptr, allocator, instance, desc);
}

pub fn getQueues(self: *Self, allocation: *[ngl.Queue.max]*Queue, device: *Device) []*Queue {
    return self.vtable.getQueues(self.ptr, allocation, device);
}

pub fn getMemoryTypes(
    self: *Self,
    allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
    device: *Device,
) []ngl.Memory.Type {
    return self.vtable.getMemoryTypes(self.ptr, allocation, device);
}

pub fn allocMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Memory.Desc,
) Error!*Memory {
    return self.vtable.allocMemory(self.ptr, allocator, device, desc);
}

pub fn freeMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    memory: *Memory,
) void {
    self.vtable.freeMemory(self.ptr, allocator, device, memory);
}

pub fn deinitDevice(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
    self.vtable.deinitDevice(self.ptr, allocator, device);
}

pub fn initCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.CommandPool.Desc,
) Error!*CommandPool {
    return self.vtable.initCommandPool(self.ptr, allocator, device, desc);
}

pub fn allocCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    command_pool: *CommandPool,
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

pub fn freeCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    command_pool: *CommandPool,
    command_buffers: []const ngl.CommandBuffer,
) void {
    self.vtable.freeCommandBuffers(self.ptr, allocator, device, command_pool, command_buffers);
}

pub fn deinitCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    command_pool: *CommandPool,
) void {
    self.vtable.deinitCommandPool(self.ptr, allocator, device, command_pool);
}

pub fn initFence(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Fence.Desc,
) Error!*Fence {
    return self.vtable.initFence(self.ptr, allocator, device, desc);
}

pub fn deinitFence(self: *Self, allocator: std.mem.Allocator, device: *Device, fence: *Fence) void {
    self.vtable.deinitFence(self.ptr, allocator, device, fence);
}

pub fn initSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Semaphore.Desc,
) Error!*Semaphore {
    return self.vtable.initSemaphore(self.ptr, allocator, device, desc);
}

pub fn deinitSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    semaphore: *Semaphore,
) void {
    self.vtable.deinitSemaphore(self.ptr, allocator, device, semaphore);
}

pub fn initBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Buffer.Desc,
) Error!*Buffer {
    return self.vtable.initBuffer(self.ptr, allocator, device, desc);
}

pub fn getMemoryRequirementsBuffer(
    self: *Self,
    device: *Device,
    buffer: *Buffer,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsBuffer(self.ptr, device, buffer);
}

pub fn deinitBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    buffer: *Buffer,
) void {
    self.vtable.deinitBuffer(self.ptr, allocator, device, buffer);
}

pub fn initBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.BufferView.Desc,
) Error!*BufferView {
    return self.vtable.initBufferView(self.ptr, allocator, device, desc);
}

pub fn deinitBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    buffer_view: *BufferView,
) void {
    self.vtable.deinitBufferView(self.ptr, allocator, device, buffer_view);
}

pub fn initImage(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Image.Desc,
) Error!*Image {
    return self.vtable.initImage(self.ptr, allocator, device, desc);
}

pub fn deinitImage(self: *Self, allocator: std.mem.Allocator, device: *Device, image: *Image) void {
    self.vtable.deinitImage(self.ptr, allocator, device, image);
}

pub fn getMemoryRequirementsImage(
    self: *Self,
    device: *Device,
    image: *Image,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsImage(self.ptr, device, image);
}

pub fn initImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.ImageView.Desc,
) Error!*ImageView {
    return self.vtable.initImageView(self.ptr, allocator, device, desc);
}

pub fn deinitImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    image_view: *ImageView,
) void {
    self.vtable.deinitImageView(self.ptr, allocator, device, image_view);
}

pub fn initSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Sampler.Desc,
) Error!*Sampler {
    return self.vtable.initSampler(self.ptr, allocator, device, desc);
}

pub fn deinitSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    sampler: *Sampler,
) void {
    self.vtable.deinitSampler(self.ptr, allocator, device, sampler);
}

pub fn initRenderPass(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.RenderPass.Desc,
) Error!*RenderPass {
    return self.vtable.initRenderPass(self.ptr, allocator, device, desc);
}

pub fn deinitRenderPass(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    render_pass: *RenderPass,
) void {
    self.vtable.deinitRenderPass(self.ptr, allocator, device, render_pass);
}

pub fn initFrameBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.FrameBuffer.Desc,
) Error!*FrameBuffer {
    return self.vtable.initFrameBuffer(self.ptr, allocator, device, desc);
}

pub fn deinitFrameBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    frame_buffer: *FrameBuffer,
) void {
    self.vtable.deinitFrameBuffer(self.ptr, allocator, device, frame_buffer);
}

pub fn initDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.DescriptorSetLayout.Desc,
) Error!*DescriptorSetLayout {
    return self.vtable.initDescriptorSetLayout(self.ptr, allocator, device, desc);
}

pub fn deinitDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    descriptor_set_layout: *DescriptorSetLayout,
) void {
    self.vtable.deinitDescriptorSetLayout(self.ptr, allocator, device, descriptor_set_layout);
}

pub fn initPipelineLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.PipelineLayout.Desc,
) Error!*PipelineLayout {
    return self.vtable.initPipelineLayout(self.ptr, allocator, device, desc);
}

pub fn deinitPipelineLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    pipeline_layout: *PipelineLayout,
) void {
    self.vtable.deinitPipelineLayout(self.ptr, allocator, device, pipeline_layout);
}

pub fn initDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.DescriptorPool.Desc,
) Error!*DescriptorPool {
    return self.vtable.initDescriptorPool(self.ptr, allocator, device, desc);
}

pub fn allocDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    descriptor_pool: *DescriptorPool,
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

pub fn freeDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    descriptor_pool: *DescriptorPool,
    descriptor_sets: []const ngl.DescriptorSet,
) void {
    self.vtable.freeDescriptorSets(self.ptr, allocator, device, descriptor_pool, descriptor_sets);
}

pub fn deinitDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    descriptor_pool: *DescriptorPool,
) void {
    self.vtable.deinitDescriptorPool(self.ptr, allocator, device, descriptor_pool);
}

pub fn initPipelinesGraphics(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Pipeline.Desc(ngl.GraphicsState),
    pipelines: []ngl.Pipeline,
) Error!void {
    return self.vtable.initPipelinesGraphics(self.ptr, allocator, device, desc, pipelines);
}

pub fn initPipelinesCompute(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.Pipeline.Desc(ngl.ComputeState),
    pipelines: []ngl.Pipeline,
) Error!void {
    return self.vtable.initPipelinesCompute(self.ptr, allocator, device, desc, pipelines);
}

pub fn deinitPipeline(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    pipeline: *Pipeline,
    @"type": ngl.Pipeline.Type,
) void {
    self.vtable.deinitPipeline(self, allocator, device, pipeline, @"type");
}

pub fn initPipelineCache(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    desc: ngl.PipelineCache.Desc,
) Error!*PipelineCache {
    return self.vtable.initPipelineCache(self.ptr, allocator, device, desc);
}

pub fn deinitPipelineCache(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    pipeline_cache: *PipelineCache,
) void {
    self.vtable.deinitPipelineCache(self.ptr, allocator, device, pipeline_cache);
}
