const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const mod = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("main.zig"),
    });
    const exe = b.addExecutable(.{
        .name = "jcc",
        .root_module = mod,
    });
    b.installArtifact(exe);
    const cmd = b.addRunArtifact(exe);
    const run = b.step("run", "Run jcc");
    run.dependOn(&cmd.step);
}
