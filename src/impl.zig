const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const Dummy = @import("dummy.zig").DummyImpl;
const Error = @import("main.zig").Error;

// TODO

pub const Impl = struct {
    const Self = @This();

    var lock = Mutex{};
    var dummy = struct {
        impl: ?Self = null,
        count: u64 = 0,
    }{};

    name: Name,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Name = enum {
        dummy,
        // TODO
    };

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        initDevice: *const fn (*anyopaque, Allocator, Device.Config) Error!Device,
    };

    pub fn get(name: ?Name) Error!*Self {
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

    pub fn unget(self: *Self) void {
        lock.lock();
        defer lock.unlock();
        switch (self.name) {
            .dummy => {
                if (dummy.count == 1) {
                    self.vtable.deinit(self.ptr);
                    dummy.impl = null;
                    dummy.count = 0;
                } else dummy.count -|= 1;
            },
        }
        self.* = undefined;
    }

    pub fn initDevice(self: Self, allocator: Allocator, config: Device.Config) Error!Device {
        return self.vtable.initDevice(self.ptr, allocator, config);
    }
};

pub const Device = struct {
    kind: Kind,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Config = @import("Device.zig").Config;
    pub const Kind = @import("Device.zig").Kind;

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator) void,
        initBuffer: *const fn (*anyopaque, Allocator, Buffer.Config) Error!Buffer,
        initTexture: *const fn (*anyopaque, Allocator, Texture.Config) Error!Texture,
        initSampler: *const fn (*anyopaque, Allocator, Sampler.Config) Error!Sampler,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.vtable.deinit(self.ptr, allocator);
        self.* = undefined;
    }

    pub fn initBuffer(self: Self, allocator: Allocator, config: Buffer.Config) Error!Buffer {
        return self.vtable.initBuffer(self.ptr, allocator, config);
    }

    pub fn initTexture(self: Self, allocator: Allocator, config: Texture.Config) Error!Texture {
        return self.vtable.initTexture(self.ptr, allocator, config);
    }

    pub fn initSampler(self: Self, allocator: Allocator, config: Sampler.Config) Error!Sampler {
        return self.vtable.initSampler(self.ptr, allocator, config);
    }
};

pub const Buffer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Config = @import("Buffer.zig").Config;

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator, Device) void,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator, device: Device) void {
        self.vtable.deinit(self.ptr, allocator, device);
        self.* = undefined;
    }
};

pub const Texture = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Config = @import("Texture.zig").Config;

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator, Device) void,
        initView: *const fn (*anyopaque, Allocator, Device, TexView.Config) Error!TexView,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator, device: Device) void {
        self.vtable.deinit(self.ptr, allocator, device);
        self.* = undefined;
    }

    pub fn initView(
        self: Self,
        allocator: Allocator,
        device: Device,
        config: TexView.Config,
    ) Error!TexView {
        return self.vtable.initView(self.ptr, allocator, device, config);
    }
};

pub const TexView = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Config = @import("TexView.zig").Config;

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator, Device, Texture) void,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator, device: Device, texture: Texture) void {
        self.vtable.deinit(self.ptr, allocator, device, texture);
        self.* = undefined;
    }
};

pub const Sampler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Config = @import("Sampler.zig").Config;

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator, Device) void,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator, device: Device) void {
        self.vtable.deinit(self.ptr, allocator, device);
        self.* = undefined;
    }
};
