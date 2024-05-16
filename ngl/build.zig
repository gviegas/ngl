const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ngl = b.addModule("ngl", .{
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
    });

    const tests = addTests(b, target, optimize);

    // TODO: This module should be private to this package,
    // but if another package that has a dependency on `ngl`
    // translates the same C headers, it will find duplicate
    // definitions in the global cache.
    const c = b.addModule("c", .{
        .root_source_file = .{ .path = "src/inc.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkPlatformSpecific(c);

    ngl.addImport("c", c);
    tests.root_module.addImport("c", c);

    _ = addDocs(b, target, optimize);
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
        //.use_llvm = false,
        //.use_lld = false,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    return tests;
}

// TODO
fn linkPlatformSpecific(c_module: *std.Build.Module) void {
    if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        c_module.linkSystemLibrary("xcb", .{});
}

fn addDocs(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const docs = b.addObject(.{
        .name = "ngl",
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc/ngl",
    });
    const docs_step = b.step("docs", "Build and install ngl documentation");
    docs_step.dependOn(&install_docs.step);
    return docs;
}
