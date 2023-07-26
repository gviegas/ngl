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

pub fn initDevice(self: Impl, allocator: Allocator, config: Device.Config) Error!Device {
    return self.vtable.impl.initDevice(self, allocator, config);
}

pub const Device = struct {
    pub const Outer = @import("Device.zig");
    pub const Kind = Outer.Kind;
    pub const Config = Outer.Config;

    kind: Kind,
    ptr: *anyopaque,

    pub fn deinit(self: *Device, device: Outer, allocator: Allocator) void {
        device.impl.vtable.device.deinit(device, allocator);
        self.* = undefined;
    }

    pub fn initHeap(device: Outer, allocator: Allocator, config: Heap.Config) Error!Heap {
        return device.impl.vtable.device.initHeap(device, allocator, config);
    }

    pub fn initSampler(device: Outer, allocator: Allocator, config: Sampler.Config) Error!Sampler {
        return device.impl.vtable.device.initSampler(device, allocator, config);
    }
};

pub const Heap = struct {
    pub const Outer = @import("Heap.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Heap, heap: Outer, allocator: Allocator) void {
        heap.device.impl.vtable.heap.deinit(heap, allocator);
        self.* = undefined;
    }

    pub fn initBuffer(heap: Outer, allocator: Allocator, config: Buffer.Config) Error!Buffer {
        return heap.device.impl.vtable.heap.initBuffer(heap, allocator, config);
    }

    pub fn initTexture(heap: Outer, allocator: Allocator, config: Texture.Config) Error!Texture {
        return heap.device.impl.vtable.heap.initTexture(heap, allocator, config);
    }
};

pub const Buffer = struct {
    pub const Outer = @import("Buffer.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Buffer, buffer: Outer, allocator: Allocator) void {
        buffer.heap.device.impl.vtable.buffer.deinit(buffer, allocator);
        self.* = undefined;
    }
};

pub const Texture = struct {
    pub const Outer = @import("Texture.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Texture, texture: Outer, allocator: Allocator) void {
        texture.heap.device.impl.vtable.texture.deinit(texture, allocator);
        self.* = undefined;
    }

    pub fn initView(texture: Outer, allocator: Allocator, config: TexView.Config) Error!TexView {
        return texture.heap.device.impl.vtable.texture.initView(texture, allocator, config);
    }
};

pub const TexView = struct {
    pub const Outer = @import("TexView.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *TexView, tex_view: Outer, allocator: Allocator) void {
        tex_view.texture.heap.device.impl.vtable.tex_view.deinit(tex_view, allocator);
        self.* = undefined;
    }
};

pub const Sampler = struct {
    pub const Outer = @import("Sampler.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Sampler, sampler: Outer, allocator: Allocator) void {
        sampler.device.impl.vtable.sampler.deinit(sampler, allocator);
        self.* = undefined;
    }
};

pub const VTable = struct {
    impl: struct {
        deinit: *const fn (*anyopaque) void,
        initDevice: *const fn (Impl, Allocator, Device.Config) Error!Device,
    },

    device: struct {
        deinit: *const fn (Device.Outer, Allocator) void,
        initHeap: *const fn (Device.Outer, Allocator, Heap.Config) Error!Heap,
        initSampler: *const fn (Device.Outer, Allocator, Sampler.Config) Error!Sampler,
    },

    heap: struct {
        deinit: *const fn (Heap.Outer, Allocator) void,
        initBuffer: *const fn (Heap.Outer, Allocator, Buffer.Config) Error!Buffer,
        initTexture: *const fn (Heap.Outer, Allocator, Texture.Config) Error!Texture,
    },

    buffer: struct {
        deinit: *const fn (Buffer.Outer, Allocator) void,
    },

    texture: struct {
        deinit: *const fn (Texture.Outer, Allocator) void,
        initView: *const fn (Texture.Outer, Allocator, TexView.Config) Error!TexView,
    },

    tex_view: struct {
        deinit: *const fn (TexView.Outer, Allocator) void,
    },

    sampler: struct {
        deinit: *const fn (Sampler.Outer, Allocator) void,
    },
};
