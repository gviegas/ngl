const Device = @import("Device.zig");
const Inner = @import("impl.zig").Buffer;
const Error = @import("main.zig").Error;

device: *Device,
inner: Inner,
size: u64,
visible: bool,
usage: Usage,

pub const Usage = struct {
    copy_src: bool = false,
    copy_dst: bool = false,
    storage: bool = false,
    uniform: bool = false,
    index: bool = false,
    vertex: bool = false,
    indirect: bool = false,
};

pub const Config = struct {
    size: u64,
    visible: bool,
    usage: Usage,
};

const Self = @This();

pub fn init(device: *Device, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .device = device,
        .inner = try device.inner.initBuffer(device.allocator, config),
        .size = config.size,
        .visible = config.visible,
        .usage = config.usage,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.device.allocator, self.device.inner);
}
