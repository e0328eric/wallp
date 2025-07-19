const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlap_dep = b.dependency("zlap", .{
        .target = target,
        .optimize = optimize,
    });

    const winzig_h = b.addTranslateC(.{
        .root_source_file = b.path("src/winzig.h"),
        .target = target,
        .optimize = optimize,
    });
    const winzig = b.createModule(.{
        .root_source_file = winzig_h.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    winzig.addCSourceFile(.{
        .file = b.path("src/winzig.c"),
    });

    const exe = b.addExecutable(.{
        .name = "wallp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zlap", .module = zlap_dep.module("zlap") },
                .{ .name = "win", .module = winzig },
            },
        }),
    });

    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("ole32");

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
