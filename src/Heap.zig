const Device = @import("Device.zig");
const Inner = @import("impl.zig").Heap;
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

pub fn init(device: *Device, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .device = device,
        .inner = try device.inner.initHeap(device.allocator, config),
        .size = config.size,
        .cpu_access = config.cpu_access,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.device.allocator, self.device.inner);
    self.* = undefined;
}
