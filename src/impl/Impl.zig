const std = @import("std");
const builtin = @import("builtin");

const ngl = @import("../ngl.zig");
const Error = ngl.Error;

ptr: *anyopaque,
vtable: *const VTable,

fn Opaque(comptime Api: type) type {
    return opaque {
        pub inline fn cast(api: *const Api) *@This() {
            return @ptrCast(@alignCast(api.impl));
        }
    };
}

pub const Instance = Opaque(ngl.Instance);
pub const Device = Opaque(ngl.Device);
pub const Queue = Opaque(ngl.Queue);
pub const Memory = Opaque(ngl.Memory);
pub const CommandPool = Opaque(ngl.CommandPool);
pub const CommandBuffer = Opaque(ngl.CommandBuffer);
pub const Fence = Opaque(ngl.Fence);
pub const Semaphore = Opaque(ngl.Semaphore);
pub const Buffer = Opaque(ngl.Buffer);
pub const BufferView = Opaque(ngl.BufferView);
pub const Image = Opaque(ngl.Image);
pub const ImageView = Opaque(ngl.ImageView);
pub const Sampler = Opaque(ngl.Sampler);

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
        command_pool: *CommandPool,
        device: *Device,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void,

    freeCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        command_pool: *CommandPool,
        device: *Device,
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
    command_pool: *CommandPool,
    device: *Device,
    desc: ngl.CommandBuffer.Desc,
    command_buffers: []ngl.CommandBuffer,
) Error!void {
    return self.vtable.allocCommandBuffers(
        self.ptr,
        allocator,
        command_pool,
        device,
        desc,
        command_buffers,
    );
}

pub fn freeCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    command_pool: *CommandPool,
    device: *Device,
    command_buffers: []const ngl.CommandBuffer,
) void {
    self.vtable.freeCommandBuffers(self.ptr, allocator, command_pool, device, command_buffers);
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
