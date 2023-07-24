const std = @import("std");
const log = std.log.scoped(.ngl);
const Allocator = std.mem.Allocator;

const impl = @import("impl.zig");
const Impl = impl.Impl;
const Device = impl.Device;
const Buffer = impl.Buffer;
const Texture = impl.Texture;
const TexView = impl.TexView;
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

    pub fn deinit(_: *anyopaque) void {
        log.debug("Dummy Impl deinitialized", .{});
    }
};

pub const DummyDevice = struct {
    pub fn init(_: *anyopaque, _: Allocator, _: Device.Config) Error!Device {
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
    };

    pub fn deinit(_: *anyopaque, _: Allocator) void {
        log.debug("Dummy Device deinitialized", .{});
    }
};

pub const DummyBuffer = struct {
    pub fn init(_: *anyopaque, _: Allocator, _: Buffer.Config) Error!Buffer {
        log.debug("Dummy Buffer initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = Buffer.VTable{
        .deinit = deinit,
    };

    pub fn deinit(_: *anyopaque, _: Allocator, _: Device) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

pub const DummyTexture = struct {
    pub fn init(_: *anyopaque, _: Allocator, _: Texture.Config) Error!Texture {
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

    pub fn deinit(_: *anyopaque, _: Allocator, _: Device) void {
        log.debug("Dummy Texture deinitialized", .{});
    }
};

pub const DummyTexView = struct {
    pub fn init(_: *anyopaque, _: Allocator, _: Device, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{
            .ptr = undefined,
            .vtable = &vtable,
        };
    }
    const vtable = TexView.VTable{
        .deinit = deinit,
    };

    pub fn deinit(_: *anyopaque, _: Allocator, _: Device, _: Texture) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};
