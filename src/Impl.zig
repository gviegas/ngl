const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const dummy_impl = @import("dummy.zig").impl;
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
allocator: Allocator,

pub const Name = enum {
    dummy,
    // TODO
};

pub fn get(allocator: Allocator, name: ?Name) Error!*Impl {
    lock.lock();
    defer lock.unlock();
    // TODO
    const nm = name orelse .dummy;
    switch (nm) {
        .dummy => {
            dummy.impl = dummy_impl.init(allocator);
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

pub fn initDevice(self: Impl, config: Device.Config) Error!Device {
    return self.vtable.impl.initDevice(self, config);
}

pub const Device = struct {
    pub const Outer = @import("Device.zig");
    pub const Config = Outer.Config;
    pub const PlacementInfo = Outer.PlacementInfo;

    high_performance: bool,
    low_power: bool,
    fallback: bool,
    ptr: *anyopaque,

    pub fn deinit(self: *Device, device: Outer) void {
        device.impl.vtable.device.deinit(device);
        self.* = undefined;
    }

    pub fn heapBufferPlacement(device: Outer, config: Buffer.Config) Error!PlacementInfo {
        return device.impl.vtable.device.heapBufferPlacement(device, config);
    }

    pub fn heapTexturePlacement(device: Outer, config: Texture.Config) Error!PlacementInfo {
        return device.impl.vtable.device.heapTexturePlacement(device, config);
    }

    pub fn initHeap(device: Outer, config: Heap.Config) Error!Heap {
        return device.impl.vtable.device.initHeap(device, config);
    }

    pub fn initSampler(device: Outer, config: Sampler.Config) Error!Sampler {
        return device.impl.vtable.device.initSampler(device, config);
    }

    pub fn initDescLayout(device: Outer, config: DescLayout.Config) Error!DescLayout {
        return device.impl.vtable.device.initDescLayout(device, config);
    }

    pub fn initDescPool(device: Outer, config: DescPool.Config) Error!DescPool {
        return device.impl.vtable.device.initDescPool(device, config);
    }

    pub fn initShaderCode(device: Outer, config: ShaderCode.Config) Error!ShaderCode {
        return device.impl.vtable.device.initShaderCode(device, config);
    }

    pub fn initPsLayout(device: Outer, config: PsLayout.Config) Error!PsLayout {
        return device.impl.vtable.device.initPsLayout(device, config);
    }

    pub fn initPipeline(device: Outer, config: Pipeline.Config) Error!Pipeline {
        return device.impl.vtable.device.initPipeline(device, config);
    }

    pub fn initCmdPool(device: Outer, config: CmdPool.Config) Error!CmdPool {
        return device.impl.vtable.device.initCmdPool(device, config);
    }
};

pub const Heap = struct {
    pub const Outer = @import("Heap.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Heap, heap: Outer) void {
        heap.impl().vtable.heap.deinit(heap);
        self.* = undefined;
    }

    pub fn initBuffer(heap: Outer, config: Buffer.Config) Error!Buffer {
        return heap.impl().vtable.heap.initBuffer(heap, config);
    }

    pub fn initTexture(heap: Outer, config: Texture.Config) Error!Texture {
        return heap.impl().vtable.heap.initTexture(heap, config);
    }
};

pub const Buffer = struct {
    pub const Outer = @import("Buffer.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Buffer, buffer: Outer) void {
        buffer.impl().vtable.buffer.deinit(buffer);
        self.* = undefined;
    }
};

pub const Texture = struct {
    pub const Outer = @import("Texture.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Texture, texture: Outer) void {
        texture.impl().vtable.texture.deinit(texture);
        self.* = undefined;
    }

    pub fn initView(texture: Outer, config: TexView.Config) Error!TexView {
        return texture.impl().vtable.texture.initView(texture, config);
    }
};

pub const TexView = struct {
    pub const Outer = @import("TexView.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *TexView, tex_view: Outer) void {
        tex_view.impl().vtable.tex_view.deinit(tex_view);
        self.* = undefined;
    }
};

pub const Sampler = struct {
    pub const Outer = @import("Sampler.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Sampler, sampler: Outer) void {
        sampler.impl().vtable.sampler.deinit(sampler);
        self.* = undefined;
    }
};

pub const DescLayout = struct {
    pub const Outer = @import("DescLayout.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *DescLayout, desc_layout: Outer) void {
        desc_layout.impl().vtable.desc_layout.deinit(desc_layout);
        self.* = undefined;
    }
};

pub const DescPool = struct {
    pub const Outer = @import("DescPool.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *DescPool, desc_pool: Outer) void {
        desc_pool.impl().vtable.desc_pool.deinit(desc_pool);
        self.* = undefined;
    }

    pub fn allocSets(
        desc_pool: Outer,
        dest: []DescSet.Outer,
        configs: []const DescSet.Config,
    ) Error!void {
        return desc_pool.impl().vtable.desc_pool.allocSets(desc_pool, dest, configs);
    }
};

pub const DescSet = struct {
    pub const Outer = @import("DescSet.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn free(self: *DescSet, desc_set: Outer) void {
        desc_set.impl().vtable.desc_set.free(desc_set);
        self.* = undefined;
    }
};

pub const ShaderCode = struct {
    pub const Outer = @import("ShaderCode.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *ShaderCode, shader_code: Outer) void {
        shader_code.impl().vtable.shader_code.deinit(shader_code);
        self.* = undefined;
    }
};

pub const PsLayout = struct {
    pub const Outer = @import("PsLayout.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *PsLayout, ps_layout: Outer) void {
        ps_layout.impl().vtable.ps_layout.deinit(ps_layout);
        self.* = undefined;
    }
};

pub const Pipeline = struct {
    pub const Outer = @import("Pipeline.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *Pipeline, pipeline: Outer) void {
        pipeline.impl().vtable.pipeline.deinit(pipeline);
        self.* = undefined;
    }
};

pub const CmdPool = struct {
    pub const Outer = @import("CmdPool.zig");
    pub const Config = Outer.Config;

    ptr: *anyopaque,

    pub fn deinit(self: *CmdPool, cmd_pool: Outer) void {
        cmd_pool.impl().vtable.cmd_pool.deinit(cmd_pool);
        self.* = undefined;
    }
};

pub const VTable = struct {
    impl: struct {
        deinit: *const fn (*anyopaque) void,
        initDevice: *const fn (Impl, Device.Config) Error!Device,
    },

    device: struct {
        deinit: *const fn (Device.Outer) void,
        heapBufferPlacement: *const fn (Device.Outer, Buffer.Config) Error!Device.PlacementInfo,
        heapTexturePlacement: *const fn (Device.Outer, Texture.Config) Error!Device.PlacementInfo,
        initHeap: *const fn (Device.Outer, Heap.Config) Error!Heap,
        initSampler: *const fn (Device.Outer, Sampler.Config) Error!Sampler,
        initDescLayout: *const fn (Device.Outer, DescLayout.Config) Error!DescLayout,
        initDescPool: *const fn (Device.Outer, DescPool.Config) Error!DescPool,
        initShaderCode: *const fn (Device.Outer, ShaderCode.Config) Error!ShaderCode,
        initPsLayout: *const fn (Device.Outer, PsLayout.Config) Error!PsLayout,
        initPipeline: *const fn (Device.Outer, Pipeline.Config) Error!Pipeline,
        initCmdPool: *const fn (Device.Outer, CmdPool.Config) Error!CmdPool,
    },

    heap: struct {
        deinit: *const fn (Heap.Outer) void,
        initBuffer: *const fn (Heap.Outer, Buffer.Config) Error!Buffer,
        initTexture: *const fn (Heap.Outer, Texture.Config) Error!Texture,
    },

    buffer: struct {
        deinit: *const fn (Buffer.Outer) void,
    },

    texture: struct {
        deinit: *const fn (Texture.Outer) void,
        initView: *const fn (Texture.Outer, TexView.Config) Error!TexView,
    },

    tex_view: struct {
        deinit: *const fn (TexView.Outer) void,
    },

    sampler: struct {
        deinit: *const fn (Sampler.Outer) void,
    },

    desc_layout: struct {
        deinit: *const fn (DescLayout.Outer) void,
    },

    desc_pool: struct {
        deinit: *const fn (DescPool.Outer) void,
        allocSets: *const fn (DescPool.Outer, []DescSet.Outer, []const DescSet.Config) Error!void,
    },

    desc_set: struct {
        free: *const fn (DescSet.Outer) void,
    },

    shader_code: struct {
        deinit: *const fn (ShaderCode.Outer) void,
    },

    ps_layout: struct {
        deinit: *const fn (PsLayout.Outer) void,
    },

    pipeline: struct {
        deinit: *const fn (Pipeline.Outer) void,
    },

    cmd_pool: struct {
        deinit: *const fn (CmdPool.Outer) void,
    },
};
