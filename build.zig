const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "dirz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run dirz");
    run_step.dependOn(&run.step);

    const clean = b.addRemoveDirTree(b.path("zig-out"));
    const clean_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    const clean_step = b.step("clean", "Remove zig-out and .zig-cache");
    clean_step.dependOn(&clean.step);
    clean_step.dependOn(&clean_cache.step);
}
