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
const DescLayout = Impl.DescLayout;
const DescPool = Impl.DescPool;
const DescSet = Impl.DescSet;
const ShaderCode = Impl.ShaderCode;
const PsLayout = Impl.PsLayout;
const Pipeline = Impl.Pipeline;
const Error = @import("main.zig").Error;

pub const impl = struct {
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
            .deinit = device.deinit,
            .heapBufferPlacement = device.heapBufferPlacement,
            .heapTexturePlacement = device.heapTexturePlacement,
            .initHeap = device.initHeap,
            .initSampler = device.initSampler,
            .initDescLayout = device.initDescLayout,
            .initDescPool = device.initDescPool,
            .initShaderCode = device.initShaderCode,
            .initPsLayout = device.initPsLayout,
            .initPipeline = device.initPipeline,
        },
        .heap = .{
            .deinit = heap.deinit,
            .initBuffer = heap.initBuffer,
            .initTexture = heap.initTexture,
        },
        .buffer = .{ .deinit = buffer.deinit },
        .texture = .{ .deinit = texture.deinit, .initView = texture.initView },
        .tex_view = .{ .deinit = tex_view.deinit },
        .sampler = .{ .deinit = sampler.deinit },
        .desc_layout = .{ .deinit = desc_layout.deinit },
        .desc_pool = .{ .deinit = desc_pool.deinit, .allocSets = desc_pool.allocSets },
        .desc_set = .{ .free = desc_set.free },
        .shader_code = .{ .deinit = shader_code.deinit },
        .ps_layout = .{ .deinit = ps_layout.deinit },
        .pipeline = .{ .deinit = pipeline.deinit },
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

const device = struct {
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

    fn initDescLayout(_: Device.Outer, _: DescLayout.Config) Error!DescLayout {
        log.debug("Dummy DescLayout initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initDescPool(_: Device.Outer, _: DescPool.Config) Error!DescPool {
        log.debug("Dummy DescPool initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initShaderCode(_: Device.Outer, _: ShaderCode.Config) Error!ShaderCode {
        log.debug("Dummy ShaderCode initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initPsLayout(_: Device.Outer, _: PsLayout.Config) Error!PsLayout {
        log.debug("Dummy PsLayout initialized", .{});
        return .{ .ptr = undefined };
    }

    fn initPipeline(_: Device.Outer, _: Pipeline.Config) Error!Pipeline {
        log.debug("Dummy Pipeline initialized", .{});
        return .{ .ptr = undefined };
    }
};

const heap = struct {
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

const buffer = struct {
    fn deinit(_: Buffer.Outer) void {
        log.debug("Dummy Buffer deinitialized", .{});
    }
};

const texture = struct {
    fn deinit(_: Texture.Outer) void {
        log.debug("Dummy Texture deinitialized", .{});
    }

    fn initView(_: Texture.Outer, _: TexView.Config) Error!TexView {
        log.debug("Dummy TexView initialized", .{});
        return .{ .ptr = undefined };
    }
};

const tex_view = struct {
    fn deinit(_: TexView.Outer) void {
        log.debug("Dummy TexView deinitialized", .{});
    }
};

const sampler = struct {
    fn deinit(_: Sampler.Outer) void {
        log.debug("Dummy Sampler deinitialized", .{});
    }
};

const desc_layout = struct {
    fn deinit(_: DescLayout.Outer) void {
        log.debug("Dummy DescLayout deinitialized", .{});
    }
};

const desc_pool = struct {
    fn deinit(_: DescPool.Outer) void {
        log.debug("Dummy DescPool deinitialized", .{});
    }

    fn allocSets(_: DescPool.Outer, dest: []DescSet.Outer, _: []const DescSet.Config) Error!void {
        log.debug("Dummy DescSet(s) allocated", .{});
        for (dest) |*d| {
            d.inner = .{ .ptr = undefined };
        }
    }
};

const desc_set = struct {
    fn free(_: DescSet.Outer) void {
        log.debug("Dummy DescSet freed", .{});
    }
};

const shader_code = struct {
    fn deinit(_: ShaderCode.Outer) void {
        log.debug("Dummy ShaderCode deinitialized", .{});
    }
};

const ps_layout = struct {
    fn deinit(_: PsLayout.Outer) void {
        log.debug("Dummy PsLayout deinitialized", .{});
    }
};

const pipeline = struct {
    fn deinit(_: Pipeline.Outer) void {
        log.debug("Dummy Pipeline deinitialized", .{});
    }
};
