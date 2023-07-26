const Device = @import("Device.zig");
const Inner = @import("Impl.zig").Heap;
const Buffer = @import("Buffer.zig");
const Texture = @import("Texture.zig");
const Error = @import("main.zig").Error;

device: *Device,
inner: Inner,
size: u64,
cpu_access: CpuAccess,

pub const CpuAccess = enum {
    none,
    write_only,
    read_only,
};

pub const Config = struct {
    size: u64,
    cpu_access: CpuAccess,
};

const Self = @This();

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.device.allocator);
    self.* = undefined;
}

pub fn initBuffer(self: *Self, config: Buffer.Config) Error!Buffer {
    // TODO: Validation.
    return .{
        .heap = self,
        .inner = try Inner.initBuffer(self.*, self.device.allocator, config),
        .offset = config.offset,
        .size = config.size,
        .usage = config.usage,
    };
}

pub fn initTexture(self: *Self, config: Texture.Config) Error!Texture {
    // TODO: Validation.
    return .{
        .heap = self,
        .inner = try Inner.initTexture(self.*, self.device.allocator, config),
        .offset = config.offset,
        .dimension = config.dimension,
        .format = config.format,
        .width = config.width,
        .height = config.height,
        .depth_or_layers = config.depth_or_layers,
        .levels = config.levels,
        .samples = config.samples,
        .usage = config.usage,
    };
}
