const std = @import("std");
const testing = std.testing;

const ngl = @import("../ngl.zig");

test "Flags" {
    const E = enum {
        hi,
        bye,
        why,

        const F = ngl.Flags(@This());
    };

    var f = E.F{};
    try testing.expect(ngl.noFlagsSet(ngl.andFlags(f, f)));
    try testing.expect(!ngl.allFlagsSet(ngl.orFlags(f, f)));
    try testing.expect(ngl.noFlagsSet(ngl.xorFlags(f, f)));
    try testing.expect(ngl.allFlagsSet(ngl.notFlags(f)));

    f.hi = true;
    try testing.expect(!ngl.noFlagsSet(f));
    try testing.expect(!ngl.allFlagsSet(f));
    try testing.expect(ngl.eqlFlags(
        ngl.andFlags(f, .{ .hi = true, .bye = true }),
        f,
    ));
    try testing.expect(ngl.eqlFlags(
        ngl.orFlags(f, .{ .hi = true, .bye = true }),
        E.F{ .hi = true, .bye = true },
    ));
    try testing.expect(ngl.eqlFlags(
        ngl.xorFlags(f, .{ .why = true }),
        E.F{ .hi = true, .why = true },
    ));
    try testing.expect(ngl.eqlFlags(
        ngl.notFlags(f),
        E.F{ .bye = true, .why = true },
    ));

    f.why = true;
    try testing.expect(!ngl.noFlagsSet(f));
    try testing.expect(!ngl.allFlagsSet(f));
    try testing.expect(ngl.eqlFlags(
        ngl.andFlags(f, .{ .why = true, .bye = true }),
        E.F{ .why = true },
    ));
    try testing.expect(ngl.allFlagsSet(
        ngl.orFlags(f, .{ .why = true, .bye = true }),
    ));
    try testing.expect(ngl.eqlFlags(
        ngl.xorFlags(f, .{ .why = true }),
        E.F{ .hi = true },
    ));
    try testing.expect(ngl.eqlFlags(
        ngl.notFlags(f),
        E.F{ .bye = true },
    ));

    f.bye = true;
    try testing.expect(!ngl.noFlagsSet(ngl.andFlags(f, f)));
    try testing.expect(ngl.allFlagsSet(ngl.orFlags(f, f)));
    try testing.expect(ngl.noFlagsSet(ngl.xorFlags(f, f)));
    try testing.expect(ngl.noFlagsSet(ngl.notFlags(f)));
}
