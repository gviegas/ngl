const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const Dummy = @import("dummy.zig").DummyImpl;
const Error = @import("main.zig").Error;

const Impl = @This();

var lock = Mutex{};
var dummy = struct {
    impl: ?Impl = null,
    count: u64 = 0,
}{};

name: Name,
ptr: *anyopaque,
vtable: *const VTable,

pub const Name = enum {
    dummy,
    // TODO
};

pub fn get(name: ?Name) Error!*Impl {
    lock.lock();
    defer lock.unlock();
    // TODO
    const nm = name orelse .dummy;
    switch (nm) {
        .dummy => {
            dummy.impl = Dummy.init();
            dummy.count += 1;
            return &dummy.impl.?;
        },
    }
}

pub fn unget(self: *Impl) void {
    lock.lock();
    defer lock.unlock();
    switch (self.name) {
        .dummy => {
            if (dummy.count == 1) {
                self.vtable.impl.deinit(self.ptr);
                dummy.impl = null;
                dummy.count = 0;
            } else dummy.count -|= 1;
        },
    }
    self.* = undefined;
}

pub const Device = struct {
    pub const Outer = @import("Device.zig");
    pub const Kind = Outer.Kind;
    pub const Config = Outer.Config;

    kind: Kind,
    ptr: *anyopaque,

    pub fn init(impl: Impl, allocator: Allocator, config: Config) Error!Device {
        return impl.vtable.device.init(impl, allocator, config);
    }

    pub fn deinit(self: *Device, device: Outer, allocator: Allocator) void {
        device.impl.vtable.device.deinit(device, allocator);
        self.* = undefined;
    }
};

pub const Heap = struct {
    pub const Outer = @import("Heap.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn init(device: Device.Outer, allocator: Allocator, config: Config) Error!Heap {
        return device.impl.vtable.heap.init(device, allocator, config);
    }

    pub fn deinit(self: *Heap, heap: Outer, allocator: Allocator) void {
        heap.device.impl.vtable.heap.deinit(heap, allocator);
        self.* = undefined;
    }
};

pub const Buffer = struct {
    pub const Outer = @import("Buffer.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn init(heap: Heap.Outer, allocator: Allocator, config: Config) Error!Buffer {
        return heap.device.impl.vtable.buffer.init(heap, allocator, config);
    }

    pub fn deinit(self: *Buffer, buffer: Outer, allocator: Allocator) void {
        buffer.heap.device.impl.vtable.buffer.deinit(buffer, allocator);
        self.* = undefined;
    }
};

pub const Texture = struct {
    pub const Outer = @import("Texture.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn init(heap: Heap.Outer, allocator: Allocator, config: Config) Error!Texture {
        return heap.device.impl.vtable.texture.init(heap, allocator, config);
    }

    pub fn deinit(self: *Texture, texture: Outer, allocator: Allocator) void {
        texture.heap.device.impl.vtable.texture.deinit(texture, allocator);
        self.* = undefined;
    }
};

pub const TexView = struct {
    pub const Outer = @import("TexView.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn init(texture: Texture.Outer, allocator: Allocator, config: Config) Error!TexView {
        return texture.heap.device.impl.vtable.tex_view.init(texture, allocator, config);
    }

    pub fn deinit(self: *TexView, tex_view: Outer, allocator: Allocator) void {
        tex_view.texture.heap.device.impl.vtable.tex_view.deinit(tex_view, allocator);
        self.* = undefined;
    }
};

pub const Sampler = struct {
    pub const Outer = @import("Sampler.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn init(device: Device.Outer, allocator: Allocator, config: Config) Error!Sampler {
        return device.impl.vtable.sampler.init(device, allocator, config);
    }

    pub fn deinit(self: *Sampler, sampler: Outer, allocator: Allocator) void {
        sampler.device.impl.vtable.sampler.deinit(sampler, allocator);
        self.* = undefined;
    }
};

pub const VTable = struct {
    impl: struct {
        deinit: *const fn (*anyopaque) void,
    },

    device: struct {
        init: *const fn (Impl, Allocator, Device.Config) Error!Device,
        deinit: *const fn (Device.Outer, Allocator) void,
    },

    heap: struct {
        init: *const fn (Device.Outer, Allocator, Heap.Config) Error!Heap,
        deinit: *const fn (Heap.Outer, Allocator) void,
    },

    buffer: struct {
        init: *const fn (Heap.Outer, Allocator, Buffer.Config) Error!Buffer,
        deinit: *const fn (Buffer.Outer, Allocator) void,
    },

    texture: struct {
        init: *const fn (Heap.Outer, Allocator, Texture.Config) Error!Texture,
        deinit: *const fn (Texture.Outer, Allocator) void,
    },

    tex_view: struct {
        init: *const fn (Texture.Outer, Allocator, TexView.Config) Error!TexView,
        deinit: *const fn (TexView.Outer, Allocator) void,
    },

    sampler: struct {
        init: *const fn (Device.Outer, Allocator, Sampler.Config) Error!Sampler,
        deinit: *const fn (Sampler.Outer, Allocator) void,
    },
};
