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

pub fn QueryResolve(comptime query_type: QueryType) type {
    return struct {
        /// `null` means the given result wasn't available.
        resolved_results: switch (query_type) {
            .occlusion => []struct { samples_passed: ?u64 },
            .timestamp => []struct { ns: ?u64 },
        } = &.{},

        const Self = @This();

        /// Resolves results obtained from `Cmd.copyQueryPoolResults`.
        /// `unresolved_results` must be aligned as required by
        /// `QueryType.getLayout`, and must refer to the beginning of
        /// the data copied by the aforementioned command.
        /// `with_availability` must match what was specified in the
        /// command's `Cmd.QueryResult`.
        /// One must use the same `allocator` until `free` is called.
        pub fn resolve(
            self: *Self,
            allocator: std.mem.Allocator,
            device: *Device,
            first_query: u32,
            query_count: u32,
            with_availability: bool,
            unresolved_results: []const u8,
        ) Error!void {
            if (query_count != self.resolved_results.len)
                self.resolved_results = try allocator.realloc(self.resolved_results, query_count);
            const impl_fn = switch (query_type) {
                .occlusion => Impl.resolveQueryOcclusion,
                .timestamp => Impl.resolveQueryTimestamp,
            };
            try @call(.auto, impl_fn, .{
                Impl.get(),
                device.impl,
                first_query,
                with_availability,
                unresolved_results,
                self.resolved_results,
            });
        }

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            //if (self.len == 0) return;
            allocator.free(self.resolved_results);
            self.resolved_results = &.{};
        }
    };
}
