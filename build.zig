const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    addMainTests(b);

    addStandalone(b, "ads.zig", b.step("ads", "Run ADS shading standalone"));
    addStandalone(b, "pbr.zig", b.step("pbr", "Run PBR shading standalone"));
    addStandalone(b, "pcf.zig", b.step("pcf", "Run PCF shadows standalone"));
    addStandalone(b, "vsm.zig", b.step("vsm", "Run VSM shadows standalone"));
    addStandalone(b, "srgb.zig", b.step("srgb", "Run sRGB standalone"));
    addStandalone(b, "mag.zig", b.step("mag", "Run alpha test standalone"));
    addStandalone(b, "cube.zig", b.step("cube", "Run cube map standalone"));
    addStandalone(b, "ssao.zig", b.step("ssao", "Run SSAO standalone"));
    addStandalone(b, "hdr.zig", b.step("hdr", "Run HDR standalone"));
}

fn addMainTests(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/ngl.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkPlatformSpecific(main_tests);

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_main_tests.step);
}

fn addStandalone(b: *std.Build, comptime root_file_name: []const u8, step: *std.Build.Step) void {
    const base_path = "src/standalone/";

    const standalone = b.addExecutable(.{
        .name = root_file_name[0..std.mem.indexOfScalar(u8, root_file_name, '.').?],
        .root_source_file = .{ .path = base_path ++ root_file_name },
        .link_libc = true,
        .main_mod_path = .{ .path = "src/" },
    });
    linkPlatformSpecific(standalone);

    const run_standalone = b.addRunArtifact(standalone);
    step.dependOn(&run_standalone.step);
}

// TODO
fn linkPlatformSpecific(compile_step: *std.Build.Step.Compile) void {
    if (builtin.os.tag == .linux and !builtin.target.isAndroid())
        compile_step.linkSystemLibrary2("xcb", .{});
}

/// Creates the module.
pub fn createModule(b: *std.Build) *std.Build.Module {
    const dir = comptime fs.path.dirname(@src().file) orelse ".";
    const path = dir ++ "/src/ngl.zig";
    return b.createModule(.{ .source_file = .{ .path = path } });
}
