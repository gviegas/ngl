const std = @import("std");

const ngl = @import("../ngl.zig");
const Device = ngl.Device;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const QueryType = enum {
    occlusion,
    /// `Feature.core.query.timestamp`.
    timestamp,

    pub const Layout = struct {
        size: u64,
        alignment: u64,
    };

    const Self = @This();

    pub fn getLayout(
        self: Self,
        device: *Device,
        query_count: u32,
        with_availability: bool,
    ) Layout {
        return Impl.get().getQueryLayout(device.impl, self, query_count, with_availability);
    }
};

pub const QueryPool = struct {
    impl: Impl.QueryPool,
    type: QueryType,

    pub const Desc = struct {
        query_type: QueryType,
        query_count: u32,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *Device, desc: Desc) Error!Self {
        return .{
            .impl = try Impl.get().initQueryPool(allocator, device.impl, desc),
            .type = desc.query_type,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: *Device) void {
        Impl.get().deinitQueryPool(allocator, device.impl, self.impl);
        self.* = undefined;
    }
};
