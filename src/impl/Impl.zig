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

// TODO
pub inline fn cast(comptime T: type, api: anytype) *T {
    switch (@typeInfo(@TypeOf(api))) {
        .Pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .Struct => {},
                else => @compileError("Not a valid pointee type"),
            }
        },
        else => @compileError("Not a pointer type"),
    }
    return @ptrCast(@alignCast(@field(api, "impl")));
}

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

    deinitCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Device,
        command_pool: *CommandPool,
    ) void,
};

const Self = @This();

var lock = std.Thread.Mutex{};
var impl: ?Self = null;
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

pub fn deinitCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: *Device,
    command_pool: *CommandPool,
) void {
    self.vtable.deinitCommandPool(self.ptr, allocator, device, command_pool);
}
