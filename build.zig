const std = @import("std");

pub fn build(b: *std.Build) !void {
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
    cmd.has_side_effects = true;
    cmd.stdio_limit = .unlimited;
    const @"asm" = cmd.captureStdOut(.{ .basename = "a.asm" });
    const nasm = b.addSystemCommand(&.{ "nasm", "-felf64", "-o" });
    const obj = nasm.addOutputFileArg("a.o");
    nasm.addFileArg(@"asm");
    const compile = b.step("compile", "Compile test.c");
    compile.dependOn(&nasm.step);
    const ld = b.addSystemCommand(&.{ "ld", "-o" });
    const out = ld.addOutputFileArg("a.out");
    ld.addFileArg(obj);
    const testc = b.addSystemCommand(&.{ "sh", "-c" });
    testc.addFileArg(out);
    const run = b.step("run", "Run test.c");
    run.dependOn(&testc.step);
}
