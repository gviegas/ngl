const std = @import("std");

const ngl = @import("../ngl.zig");
const CommandBuffer = ngl.CommandBuffer;
const PipelineStage = ngl.PipelineStage;
const Fence = ngl.Fence;
const Semaphore = ngl.Semaphore;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Instance = struct {
    impl: Impl.Instance,

    // TODO
    pub const Desc = struct {};

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, desc: Desc) Error!Self {
        try Impl.init(allocator);
        return .{ .impl = try Impl.get().initInstance(allocator, desc) };
    }

    /// Caller is responsible for freeing the returned slice.
    pub fn listDevices(self: *Self, allocator: std.mem.Allocator) Error![]Device.Desc {
        return Impl.get().listDevices(allocator, self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        Impl.get().deinitInstance(allocator, self.impl);
        self.* = undefined;
    }
};

pub const Device = struct {
    impl: Impl.Device,
    queues: [Queue.max]Queue,
    queue_n: u8,
    mem_types: [Memory.max_type]Memory.Type,
    mem_type_n: u8,

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
        impl: ?u64 = null,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, instance: *Instance, desc: Desc) Error!Self {
        var self = Self{
            .impl = try Impl.get().initDevice(allocator, instance.impl, desc),
            .queues = undefined,
            .queue_n = 0,
            .mem_types = undefined,
            .mem_type_n = 0,
        };
        // Track the current element in `desc.queues` since it
        // might be interspersed with `null`s
        var queue_i: usize = 0;
        var queue_alloc: [Queue.max]Impl.Queue = undefined;
        const queues = Impl.get().getQueues(&queue_alloc, self.impl);
        for (self.queues[0..queues.len], queues) |*queue, impl| {
            // This assumes that implementations won't reorder
            // the queues - the order must match `desc`'s
            while (desc.queues[queue_i] == null) : (queue_i += 1) {}
            queue.* = .{
                .impl = impl,
                .capabilities = desc.queues[queue_i].?.capabilities,
                .priority = desc.queues[queue_i].?.priority,
            };
            queue_i += 1;
        }
        self.queue_n = @intCast(queues.len);
        self.mem_type_n = @intCast(Impl.get().getMemoryTypes(&self.mem_types, self.impl).len);
        return self;
    }

    pub fn alloc(self: *Self, allocator: std.mem.Allocator, desc: Memory.Desc) Error!Memory {
        return .{ .impl = try Impl.get().allocMemory(allocator, self.impl, desc) };
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator, memory: *Memory) void {
        Impl.get().freeMemory(allocator, self.impl, memory.impl);
        memory.* = undefined;
    }

    pub fn wait(self: *Self) Error!void {
        return Impl.get().waitDevice(self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        Impl.get().deinitDevice(allocator, self.impl);
        self.* = undefined;
    }
};

pub const Queue = struct {
    impl: Impl.Queue,
    capabilities: Capabilities,
    priority: Priority,

    pub const max = 4;

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
        impl: ?u64 = null,
    };

    pub const Submit = struct {
        commands: []const CommandBufferSubmit,
        wait: []const SemaphoreSubmit,
        signal: []const SemaphoreSubmit,

        pub const CommandBufferSubmit = struct {
            command_buffer: *CommandBuffer,
        };

        pub const SemaphoreSubmit = struct {
            semaphore: *Semaphore,
            stage_mask: PipelineStage.Flags,
        };
    };

    const Self = @This();

    pub fn submit(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        fence: ?*Fence,
        submits: []const Submit,
    ) Error!void {
        return Impl.get().submit(
            allocator,
            device.impl,
            self.impl,
            if (fence) |x| x.impl else null,
            submits,
        );
    }

    pub fn wait(self: *Self, device: *Device) Error!void {
        return Impl.get().waitQueue(device.impl, self.impl);
    }
};

pub const Memory = struct {
    impl: Impl.Memory,

    pub const TypeIndex = u5;
    pub const max_type = 32;

    pub const HeapIndex = u4;
    pub const max_heap = 16;

    pub const Properties = packed struct {
        device_local: bool = false,
        host_visible: bool = false,
        host_coherent: bool = false,
        host_cached: bool = false,
        lazily_allocated: bool = false,
    };

    pub const Type = struct {
        properties: Properties,
        heap_index: HeapIndex,
    };

    pub const Requirements = struct {
        size: u64,
        alignment: u64,
        type_bits: u32,

        pub inline fn supportsMemoryType(self: Requirements, type_index: TypeIndex) bool {
            return self.type_bits & (@as(u32, 1) << type_index) != 0;
        }
    };

    pub const Desc = struct {
        size: u64,
        type_index: TypeIndex,
    };

    const Self = @This();

    // TODO: Consider storing the size of the memory allocation
    // so this method can return a slice
    pub fn map(self: *Self, device: *Device, offset: u64, size: ?u64) Error![*]u8 {
        return try Impl.get().mapMemory(device.impl, self.impl, offset, size);
    }

    // TODO: Track memory state
    pub fn unmap(self: *Self, device: *Device) void {
        Impl.get().unmapMemory(device.impl, self.impl);
    }

    pub fn flushMapped(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        return Impl.get().flushMappedMemory(allocator, device.impl, self.impl, offsets, sizes);
    }

    pub fn invalidateMapped(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        return Impl.get().invalidateMappedMemory(allocator, device.impl, self.impl, offsets, sizes);
    }
};
