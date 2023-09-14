const std = @import("std");

const Error = @import("../ngl.zig").Error;
const Impl = @import("../impl/Impl.zig");

pub const Instance = struct {
    impl: *Impl.Instance,
    allocator: std.mem.Allocator,

    // TODO
    pub const Desc = struct {};

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, desc: Desc) Error!Self {
        try Impl.init(allocator);
        return .{
            .impl = try Impl.get().initInstance(allocator, desc),
            .allocator = allocator,
        };
    }

    pub fn listDevices(self: *Self, allocator: std.mem.Allocator) Error![]Device.Desc {
        return Impl.get().listDevices(allocator, self.impl);
    }

    pub fn deinit(self: *Self) void {
        Impl.get().deinitInstance(self.allocator, self.impl);
        self.* = undefined;
    }
};

pub const Device = struct {
    impl: *Impl.Device,
    allocator: std.mem.Allocator,
    queues: [Queue.max]Queue,
    queue_n: u8,

    pub const Type = enum {
        discrete_gpu,
        integrated_gpu,
        cpu,
        other,
    };

    // TODO
    pub const Desc = struct {
        type: Type = .discrete_gpu,
        queues: [Queue.max]?Queue.Desc = [_]?Queue.Desc{null} ** Queue.max,
        impl: ?*anyopaque = null,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, instance: *Instance, desc: Desc) Error!Self {
        var self = Self{
            .impl = try Impl.get().initDevice(allocator, instance.impl, desc),
            .allocator = allocator,
            .queues = undefined,
            .queue_n = 0,
        };
        var queue_alloc: [Queue.max]Impl.Queue = undefined;
        const queues = Impl.get().getQueues(&queue_alloc, self.impl);
        for (queues, 0..) |q, i| self.queues[i] = .{ .impl = q };
        self.queue_n = @intCast(queues.len);
        return self;
    }

    pub fn deinit(self: *Self) void {
        Impl.get().deinitDevice(self.allocator, self.impl);
        self.* = undefined;
    }
};

pub const Queue = struct {
    impl: Impl.Queue,

    pub const Capabilities = packed struct {
        graphics: bool = false,
        compute: bool = false,
        transfer: bool = false,
    };

    pub const Priority = enum {
        default,
        low,
        high,
    };

    pub const Desc = struct {
        capabilities: Capabilities,
        priority: Priority = .default,
        impl: ?*anyopaque = null,
    };

    pub const max = 4;
};
