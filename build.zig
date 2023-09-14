const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_main_tests.step);
}

/// Creates the module.
pub fn createModule(b: *std.Build) *std.Build.Module {
    const dir = comptime fs.path.dirname(@src().file) orelse ".";
    const path = dir ++ "/src/ngl.zig";
    return b.createModule(.{ .source_file = .{ .path = path } });
}
