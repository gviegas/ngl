const Heap = @import("Heap.zig");
const Inner = @import("Impl.zig").Buffer;
const Error = @import("main.zig").Error;

heap: *Heap,
inner: Inner,
offset: u64,
size: u64,
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
    offset: u64,
    size: u64,
    usage: Usage,
};

const Self = @This();

pub fn init(heap: *Heap, config: Config) Error!Self {
    // TODO: Validation.
    return .{
        .heap = heap,
        .inner = try Inner.init(heap.*, heap.device.allocator, config),
        .offset = config.offset,
        .size = config.size,
        .usage = config.usage,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.heap.device.allocator);
    self.* = undefined;
}
