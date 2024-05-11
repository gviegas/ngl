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
    try testing.expect(ngl.flag.empty(ngl.flag.@"and"(f, f)));
    try testing.expect(!ngl.flag.full(ngl.flag.@"or"(f, f)));
    try testing.expect(ngl.flag.empty(ngl.flag.xor(f, f)));
    try testing.expect(ngl.flag.full(ngl.flag.not(f)));

    f.hi = true;
    try testing.expect(!ngl.flag.empty(f));
    try testing.expect(!ngl.flag.full(f));
    try testing.expect(ngl.flag.eql(
        ngl.flag.@"and"(f, .{ .hi = true, .bye = true }),
        f,
    ));
    try testing.expect(ngl.flag.eql(
        ngl.flag.@"or"(f, .{ .hi = true, .bye = true }),
        E.F{ .hi = true, .bye = true },
    ));
    try testing.expect(ngl.flag.eql(
        ngl.flag.xor(f, .{ .why = true }),
        E.F{ .hi = true, .why = true },
    ));
    try testing.expect(ngl.flag.eql(
        ngl.flag.not(f),
        E.F{ .bye = true, .why = true },
    ));

    f.why = true;
    try testing.expect(!ngl.flag.empty(f));
    try testing.expect(!ngl.flag.full(f));
    try testing.expect(ngl.flag.eql(
        ngl.flag.@"and"(f, .{ .why = true, .bye = true }),
        E.F{ .why = true },
    ));
    try testing.expect(ngl.flag.full(
        ngl.flag.@"or"(f, .{ .why = true, .bye = true }),
    ));
    try testing.expect(ngl.flag.eql(
        ngl.flag.xor(f, .{ .why = true }),
        E.F{ .hi = true },
    ));
    try testing.expect(ngl.flag.eql(
        ngl.flag.not(f),
        E.F{ .bye = true },
    ));

    f.bye = true;
    try testing.expect(!ngl.flag.empty(ngl.flag.@"and"(f, f)));
    try testing.expect(ngl.flag.full(ngl.flag.@"or"(f, f)));
    try testing.expect(ngl.flag.empty(ngl.flag.xor(f, f)));
    try testing.expect(ngl.flag.empty(ngl.flag.not(f)));
}
