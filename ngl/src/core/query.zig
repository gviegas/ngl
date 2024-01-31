const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

// TODO: Disclose which queries are supported in `Feature.core`

pub const QueryType = enum {
    occlusion,
    timestamp,
};

pub const QueryPool = struct {
    impl: Impl.QueryPool,

    pub const Desc = struct {
        query_type: QueryType,
        query_count: u32,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{ .impl = try Impl.get().initQueryPool(allocator, device.impl, desc) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitQueryPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
