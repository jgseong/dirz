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
    const copy_html = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p public && cp src/index.html public/index.html" });
    b.getInstallStep().dependOn(&copy_html.step);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run dirz");
    run_step.dependOn(&run.step);

    const clean = b.addRemoveDirTree(b.path("zig-out"));
    const clean_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    const clean_public = b.addRemoveDirTree(b.path("public"));
    const clean_step = b.step("clean", "Remove zig-out, .zig-cache, and public");
    clean_step.dependOn(&clean.step);
    clean_step.dependOn(&clean_cache.step);
    clean_step.dependOn(&clean_public.step);
}
