const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ngl = b.dependency("ngl", .{});

    const ctx = b.createModule(.{
        .root_source_file = .{ .path = "src/ctx.zig" },
        .target = target,
        .optimize = optimize,
    });
    ctx.addImport("ngl", ngl.module("ngl"));

    const plat = b.createModule(.{
        .root_source_file = .{ .path = "src/plat.zig" },
        .target = target,
        .optimize = optimize,
    });
    plat.addImport("ngl", ngl.module("ngl"));
    plat.addImport("c", ngl.module("c"));
    plat.addImport("ctx", ctx);

    const model = b.createModule(.{
        .root_source_file = .{ .path = "src/model.zig" },
        .target = target,
        .optimize = optimize,
    });
    model.addImport("ngl", ngl.module("ngl"));

    const idata = b.createModule(.{
        .root_source_file = .{ .path = "src/idata.zig" },
        .target = target,
        .optimize = optimize,
    });
    idata.addImport("ngl", ngl.module("ngl"));

    const util = b.createModule(.{
        .root_source_file = .{ .path = "src/util.zig" },
        .target = target,
        .optimize = optimize,
    });

    inline for (.{
        .{ "ads.zig", b.step("ads", "Run ADS sample") },
        // TODO
        //.{ "pbr.zig", b.step("pbr", "Run PBR sample") },
        //.{ "pcf.zig", b.step("pcf", "Run PCF sample") },
        //.{ "vsm.zig", b.step("vsm", "Run VSM sample") },
        //.{ "srgb.zig", b.step("srgb", "Run sRGB sample") },
        //.{ "mag.zig", b.step("mag", "Run alpha test sample") },
        //.{ "cube.zig", b.step("cube", "Run cube map sample") },
        //.{ "ssao.zig", b.step("ssao", "Run SSAO sample") },
        //.{ "hdr.zig", b.step("hdr", "Run HDR sample") },
    }) |e| {
        var exe = addExecutable(b, target, optimize, e[0], e[1]);
        exe.root_module.addImport("ngl", ngl.module("ngl"));
        exe.root_module.addImport("c", ngl.module("c"));
        exe.root_module.addImport("ctx", ctx);
        exe.root_module.addImport("plat", plat);
        exe.root_module.addImport("model", model);
        exe.root_module.addImport("idata", idata);
        exe.root_module.addImport("util", util);
    }
}

fn addExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime root_file_name: []const u8,
    step: *std.Build.Step,
) *std.Build.Step.Compile {
    const name = comptime root_file_name[0..std.mem.indexOfScalar(u8, root_file_name, '.').?];
    const exe = b.addExecutable(.{
        .name = name,
        .target = target,
        .root_source_file = .{ .path = "src/" ++ name ++ "/" ++ root_file_name },
        .optimize = optimize,
        .link_libc = true,
    });
    // TODO: Expects `data/` in the cwd.
    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args|
        run_exe.addArgs(args);
    step.dependOn(&run_exe.step);
    return exe;
}
