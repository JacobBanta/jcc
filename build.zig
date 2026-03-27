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
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));
    b.installArtifact(exe);
    const cmd = b.addRunArtifact(exe);
    cmd.addArg("-o");
    const asm_file = cmd.addOutputFileArg("a.asm");
    cmd.addFileArg(b.path("test.c"));
    const nasm = b.addSystemCommand(&.{ "nasm", "-felf64", "-o" });
    const obj_file = nasm.addOutputFileArg("a.o");
    nasm.addFileArg(asm_file);
    const compile = b.step("compile", "Compile test.c");
    compile.dependOn(&nasm.step);
    const ld = b.addSystemCommand(&.{ "ld", "-o" });
    const out = ld.addOutputFileArg("a.out");
    ld.addFileArg(obj_file);
    const testc = b.addSystemCommand(&.{ "sh", "-c" });
    testc.addFileArg(out);
    const run = b.step("run", "Run test.c");
    run.dependOn(&testc.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
