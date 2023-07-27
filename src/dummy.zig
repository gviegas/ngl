const std = @import("std");
const log = std.log.scoped(.ngl);
const Allocator = std.mem.Allocator;

const Impl = @import("Impl.zig");
const Device = Impl.Device;
const Heap = Impl.Heap;
const Buffer = Impl.Buffer;
const Texture = Impl.Texture;
const TexView = Impl.TexView;
const Sampler = Impl.Sampler;
const Error = @import("main.zig").Error;

pub const DummyImpl = struct {
    pub fn init(allocator: Allocator) Impl {
        log.debug("Dummy Impl initialized", .{});
        return .{
            .name = .dummy,
            .ptr = undefined,
            .vtable = &vtable,
            .allocator = allocator,
        };
    }
    const vtable = Impl.VTable{
        .impl = .{ .deinit = deinit, .initDevice = initDevice },
        .device = .{
            .deinit = DummyDevice.deinit,
            .heapBufferPlacement = DummyDevice.heapBufferPlacement,
            .heapTexturePlacement = DummyDevice.heapTexturePlacement,
            .initHeap = DummyDevice.initHeap,
            .initSampler = DummyDevice.initSampler,
        },
        .heap = .{
            .deinit = DummyHeap.deinit,
            .initBuffer = DummyHeap.initBuffer,
            .initTexture = DummyHeap.initTexture,
        },
        .buffer = .{ .deinit = DummyBuffer.deinit },
        .texture = .{ .deinit = DummyTexture.deinit, .initView = DummyTexture.initView },
        .tex_view = .{ .deinit = DummyTexView.deinit },
        .sampler = .{ .deinit = DummySampler.deinit },
    };

    fn deinit(_: *anyopaque) void {
        log.debug("Dummy Impl deinitialized", .{});
    }

    fn initDevice(_: Impl, _: Device.Config) Error!Device {
        log.debug("Dummy Device initialized", .{});
        return .{
            .high_performance = false,
            .low_power = false,
            .fallback = false,
            .ptr = undefined,
        };
    }
};

const DummyDevice = struct {
    fn deinit(_: Device.Outer) void {
        log.debug("Dummy Device deinitialized", .{});
    }

    fn heapBufferPlacement(_: Device.Outer, _: Buffer.Config) Error!Device.PlacementInfo {
        log.debug("Dummy Device's heapBufferPlacement called", .{});
        return .{
            .size = ~@as(u64, (4 << 20) - 1),
            .alignment = 4 << 20,
            .write_only_heap = false,
            .read_only_heap = false,
        };
    }

    fn heapTexturePlacement(_: Device.Outer, _: Texture.Config) Error!Device.PlacementInfo {
        log.debug("Dummy Device's heapTexturePlacement called", .{});
        return .{
            .size = ~@as(u64, (4 << 20) - 1),
            .alignment = 4 << 20,
            .write_only_heap = false,
            .read_only_heap = false,
        };
    }

    fn initHeap(_: Device.Outer, _: Heap.Config) Error!Heap {
        log.debug("Dummy Heap initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initSampler(_: Device.Outer, _: Sampler.Config) Error!Sampler {
        log.debug("Dummy Sampler initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyHeap = struct {
    fn deinit(_: Heap.Outer) void {
        log.debug("Dummy Heap deinitialized", .{});
    }

    fn initBuffer(_: Heap.Outer, _: Buffer.Config) Error!Buffer {
        log.debug("Dummy Buffer initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initTexture(_: Heap.Outer, _: Texture.Config) Error!Texture {
        log.debug("Dummy Texture initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyBuffer = struct {
    fn deinit(_: Buffer.Outer) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

const DummyTexture = struct {
    fn deinit(_: Texture.Outer) void {
        log.debug("Dummy Texture deinitialized", .{});
    }

    fn initView(_: Texture.Outer, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyTexView = struct {
    fn deinit(_: TexView.Outer) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};

const DummySampler = struct {
    fn deinit(_: Sampler.Outer) void {
        log.debug("Dummy Sampler deinitialized", .{});
    }
};
