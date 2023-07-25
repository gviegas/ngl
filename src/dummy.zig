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
    pub fn init() Impl {
        log.debug("Dummy Impl initialized", .{});
        return .{
            .name = .dummy,
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Impl.VTable{
        .impl = .{ .deinit = deinit },
        .device = .{ .init = DummyDevice.init, .deinit = DummyDevice.deinit },
        .heap = .{ .init = DummyHeap.init, .deinit = DummyHeap.deinit },
        .buffer = .{ .init = DummyBuffer.init, .deinit = DummyBuffer.deinit },
        .texture = .{ .init = DummyTexture.init, .deinit = DummyTexture.deinit },
        .tex_view = .{ .init = DummyTexView.init, .deinit = DummyTexView.deinit },
        .sampler = .{ .init = DummySampler.init, .deinit = DummySampler.deinit },
    };

    fn deinit(_: *anyopaque) void {
        log.debug("Dummy Impl deinitialized", .{});
    }
};

const DummyDevice = struct {
    fn init(_: Impl, _: Allocator, _: Device.Config) Error!Device {
        log.debug("Dummy Device initialized", .{});
        return .{ .kind = .debug, .ptr = undefined };
    }

    fn deinit(_: Device.Outer, _: Allocator) void {
        log.debug("Dummy Device deinitialized", .{});
    }
};

const DummyHeap = struct {
    fn init(_: Device.Outer, _: Allocator, _: Heap.Config) Error!Heap {
        log.debug("Dummy Heap initialized", .{});
        return .{ .ptr = undefined };
    }

    fn deinit(_: Heap.Outer, _: Allocator) void {
        log.debug("Dummy Heap deinitialized", .{});
    }
};

const DummyBuffer = struct {
    fn init(_: Heap.Outer, _: Allocator, _: Buffer.Config) Error!Buffer {
        log.debug("Dummy Buffer initialized", .{});
        return .{ .ptr = undefined };
    }

    fn deinit(_: Buffer.Outer, _: Allocator) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

const DummyTexture = struct {
    fn init(_: Heap.Outer, _: Allocator, _: Texture.Config) Error!Texture {
        log.debug("Dummy Texture initialized", .{});
        return .{ .ptr = undefined };
    }

    fn deinit(_: Texture.Outer, _: Allocator) void {
        log.debug("Dummy Texture deinitialized", .{});
    }
};

const DummyTexView = struct {
    fn init(_: Texture.Outer, _: Allocator, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{ .ptr = undefined };
    }

    fn deinit(_: TexView.Outer, _: Allocator) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};

const DummySampler = struct {
    fn init(_: Device.Outer, _: Allocator, _: Sampler.Config) Error!Sampler {
        log.debug("Dummy Sampler initialized", .{});
        return .{ .ptr = undefined };
    }

    fn deinit(_: Sampler.Outer, _: Allocator) void {
        log.debug("Dummy Sampler deinitialized", .{});
    }
};
