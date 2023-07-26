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
        .impl = .{
            .deinit = deinit,
            .initDevice = initDevice,
        },
        .device = .{
            .deinit = DummyDevice.deinit,
            .initHeap = DummyDevice.initHeap,
            .initSampler = DummyDevice.initSampler,
        },
        .heap = .{
            .deinit = DummyHeap.deinit,
            .initBuffer = DummyHeap.initBuffer,
            .initTexture = DummyHeap.initTexture,
        },
        .buffer = .{
            .deinit = DummyBuffer.deinit,
        },
        .texture = .{
            .deinit = DummyTexture.deinit,
            .initView = DummyTexture.initView,
        },
        .tex_view = .{
            .deinit = DummyTexView.deinit,
        },
        .sampler = .{
            .deinit = DummySampler.deinit,
        },
    };

    fn deinit(_: *anyopaque) void {
        log.debug("Dummy Impl deinitialized", .{});
    }

    fn initDevice(_: Impl, _: Allocator, _: Device.Config) Error!Device {
        log.debug("Dummy Device initialized", .{});
        return .{ .kind = .debug, .ptr = undefined };
    }
};

const DummyDevice = struct {
    fn deinit(_: Device.Outer, _: Allocator) void {
        log.debug("Dummy Device deinitialized", .{});
    }

    fn initHeap(_: Device.Outer, _: Allocator, _: Heap.Config) Error!Heap {
        log.debug("Dummy Heap initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initSampler(_: Device.Outer, _: Allocator, _: Sampler.Config) Error!Sampler {
        log.debug("Dummy Sampler initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyHeap = struct {
    fn deinit(_: Heap.Outer, _: Allocator) void {
        log.debug("Dummy Heap deinitialized", .{});
    }

    fn initBuffer(_: Heap.Outer, _: Allocator, _: Buffer.Config) Error!Buffer {
        log.debug("Dummy Buffer initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initTexture(_: Heap.Outer, _: Allocator, _: Texture.Config) Error!Texture {
        log.debug("Dummy Texture initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyBuffer = struct {
    fn deinit(_: Buffer.Outer, _: Allocator) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

const DummyTexture = struct {
    fn deinit(_: Texture.Outer, _: Allocator) void {
        log.debug("Dummy Texture deinitialized", .{});
    }

    fn initView(_: Texture.Outer, _: Allocator, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{ .ptr = undefined };
    }
};

const DummyTexView = struct {
    fn deinit(_: TexView.Outer, _: Allocator) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};

const DummySampler = struct {
    fn deinit(_: Sampler.Outer, _: Allocator) void {
        log.debug("Dummy Sampler deinitialized", .{});
    }
};
