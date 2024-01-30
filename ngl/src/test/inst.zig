const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");
const gpa = @import("test.zig").gpa;

test "Instance.init/deinit" {
    var inst = try ngl.Instance.init(gpa, .{});
    inst.deinit(gpa);
}

test "Instance.listDevices" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    const dev_descs = try inst.listDevices(gpa);
    defer gpa.free(dev_descs);

    // Should have returned an error if no devices are available
    try testing.expect(dev_descs.len > 0);

    for (dev_descs) |d| {
        // Must expose at least one queue
        for (d.queues) |q| {
            if (q) |_| break;
        } else try testing.expect(false);

        for (d.queues) |q| if (q) |x|
            // Exposed queues must have at least one capability
            try testing.expect(
                x.capabilities.graphics or x.capabilities.compute or x.capabilities.transfer,
            );
    }
}

test "Instance.getDriverApi" {
    var inst = try ngl.Instance.init(gpa, .{});
    defer inst.deinit(gpa);

    const dapi = inst.getDriverApi();
    try testing.expectEqual(dapi, inst.getDriverApi());

    if (@import("test.zig").writer) |writer|
        writer.print("{}\n", .{dapi}) catch {};
}
