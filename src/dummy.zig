const std = @import("std");
const log = std.log.scoped(.ngl);
const Allocator = std.mem.Allocator;

const impl = @import("impl.zig");
const Impl = impl.Impl;
const Device = impl.Device;
const Buffer = impl.Buffer;
const Texture = impl.Texture;
const TexView = impl.TexView;
const Sampler = impl.Sampler;
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
        .deinit = deinit,
        .initDevice = DummyDevice.init,
    };

    fn deinit(_: *anyopaque) void {
        log.debug("Dummy Impl deinitialized", .{});
    }
};

const DummyDevice = struct {
    fn init(_: *anyopaque, _: Allocator, _: Device.Config) Error!Device {
        log.debug("Dummy Device initialized", .{});
        return .{
            .kind = .debug,
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Device.VTable{
        .deinit = deinit,
        .initBuffer = DummyBuffer.init,
        .initTexture = DummyTexture.init,
        .initSampler = DummySampler.init,
    };

    fn deinit(_: *anyopaque, _: Allocator) void {
        log.debug("Dummy Device deinitialized", .{});
    }
};

const DummyBuffer = struct {
    fn init(_: *anyopaque, _: Allocator, _: Buffer.Config) Error!Buffer {
        log.debug("Dummy Buffer initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Buffer.VTable{
        .deinit = deinit,
    };

    fn deinit(_: *anyopaque, _: Allocator, _: Device) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

const DummyTexture = struct {
    fn init(_: *anyopaque, _: Allocator, _: Texture.Config) Error!Texture {
        log.debug("Dummy Texture initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Texture.VTable{
        .deinit = deinit,
        .initView = DummyTexView.init,
    };

    fn deinit(_: *anyopaque, _: Allocator, _: Device) void {
        log.debug("Dummy Texture deinitialized", .{});
    }
};

const DummyTexView = struct {
    fn init(_: *anyopaque, _: Allocator, _: Device, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = TexView.VTable{
        .deinit = deinit,
    };

    fn deinit(_: *anyopaque, _: Allocator, _: Device, _: Texture) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};

const DummySampler = struct {
    fn init(_: *anyopaque, _: Allocator, _: Sampler.Config) Error!Sampler {
        log.debug("Dummy Sampler initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Sampler.VTable{
        .deinit = deinit,
    };

    fn deinit(_: *anyopaque, _: Allocator, _: Device) void {
        log.debug("Dummy Sampler deinitialized", .{});
    }
};
