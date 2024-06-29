const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ngl = b.dependency("ngl", .{});

    const ctx = b.createModule(.{
        .root_source_file = b.path("src/Ctx.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx.addImport("ngl", ngl.module("ngl"));

    const mdata = b.createModule(.{
        .root_source_file = b.path("src/mdata.zig"),
        .target = target,
        .optimize = optimize,
    });
    mdata.addImport("ngl", ngl.module("ngl"));

    const idata = b.createModule(.{
        .root_source_file = b.path("src/idata.zig"),
        .target = target,
        .optimize = optimize,
    });
    idata.addImport("ngl", ngl.module("ngl"));

    const gmath = b.createModule(.{
        .root_source_file = b.path("src/gmath.zig"),
        .target = target,
        .optimize = optimize,
    });

    inline for (.{
        .{ "ads.zig", b.step("ads", "Run ADS sample") },
        .{ "pbr.zig", b.step("pbr", "Run PBR sample") },
        .{ "pcf.zig", b.step("pcf", "Run PCF sample") },
        .{ "vsm.zig", b.step("vsm", "Run VSM sample") },
        .{ "ssao.zig", b.step("ssao", "Run SSAO sample") },
    }) |x| {
        var exe = addExecutable(b, target, optimize, x[0], x[1]);
        exe.root_module.addImport("ngl", ngl.module("ngl"));
        exe.root_module.addImport("Ctx", ctx);
        exe.root_module.addImport("mdata", mdata);
        exe.root_module.addImport("idata", idata);
        exe.root_module.addImport("gmath", gmath);
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
        .root_source_file = b.path("src/" ++ name ++ "/" ++ root_file_name),
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
