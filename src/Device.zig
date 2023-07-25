const std = @import("std");
const Allocator = std.mem.Allocator;

const Impl = @import("Impl.zig");
const Inner = Impl.Device;
const Error = @import("main.zig").Error;

impl: *Impl,
inner: Inner,
allocator: Allocator,

pub const Config = struct {
    preferred_kind: Kind = .discrete,
};

pub const Kind = enum {
    discrete,
    unified,
    software,
    debug,
};

const Self = @This();

pub fn init(allocator: Allocator, config: Config) Error!Self {
    const impl = try Impl.get(null);
    const inner = try Inner.init(impl.*, allocator, config);
    return .{
        .impl = impl,
        .inner = inner,
        .allocator = allocator,
    };
}

pub fn initAll(_: Allocator) Error![]Self {
    @compileError("TODO");
}

pub fn kind(self: Self) Kind {
    return self.inner.kind;
}

pub fn deinit(self: *Self) void {
    self.inner.deinit(self.*, self.allocator);
    self.impl.unget();
    self.* = undefined;
}
