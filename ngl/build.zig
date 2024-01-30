const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var ngl = b.addModule("ngl", .{
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
    });

    var tests = addTests(b, target, optimize);

    // TODO: This module should be private to this package, but if
    // another package depends on this one and translates the same
    // C headers, there's a conflict because identical definitions
    // are found in the global cache
    const c = b.addModule("c", .{
        .root_source_file = addTranslateC(b, target, optimize).getOutput(),
        .target = target,
        .optimize = optimize,
    });
    linkPlatformSpecific(c);

    ngl.addImport("c", c);
    tests.root_module.addImport("c", c);
}

fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    return tests;
}

fn addTranslateC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.TranslateC {
    return b.addTranslateC(.{
        .root_source_file = .{ .path = "src/inc.h" },
        .target = target,
        .optimize = optimize,
    });
}

// TODO
fn linkPlatformSpecific(c_module: *std.Build.Module) void {
    if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c_module.linkSystemLibrary("xcb", .{});
}
