const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const tokens = try tokenizer.lex(allocator, code);
    defer allocator.free(tokens);
    //std.debug.print("{s}\n", .{code});
    //for (tokens) |t| {
    //std.debug.print("{any}: {s}\n", .{ t.info, t.lexeme.value });
    //}
    var ast = try parser.parse(allocator, tokens);
    defer ast.deinit(allocator);
    //std.debug.print("{f}", .{ast});
    const @"asm" = try codegen.genCode(allocator, &.{ast}, null);
    defer allocator.free(@"asm");
    try std.Io.File.stdout().writeStreamingAll(init.io, codegen._start);
    try std.Io.File.stdout().writeStreamingAll(init.io, @"asm");
}

/// test only function
fn compileAndRun(source: []const u8) !u8 {
    const allocator = std.testing.allocator;
    const tokens = try tokenizer.lex(allocator, source);
    defer allocator.free(tokens);
    var ast = try parser.parse(allocator, tokens);
    defer ast.deinit(allocator);
    const @"asm" = try codegen.genCode(allocator, &.{ast}, null);
    defer allocator.free(@"asm");
    const asm_source = try std.mem.join(allocator, "", &.{ codegen._start, @"asm" });
    defer allocator.free(asm_source);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.asm", .data = asm_source });

    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const tmp_path_len = try tmp.dir.realPath(std.testing.io, &buf);
    const tmp_path = buf[0..tmp_path_len];
    const asm_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test.asm" });
    defer allocator.free(asm_path);
    const obj_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test.o" });
    defer allocator.free(obj_path);
    const exe_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test" });
    defer allocator.free(exe_path);
    var nasm_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{ "nasm", "-f", "elf64", "-o", obj_path, asm_path } });
    _ = try nasm_exe.wait(std.testing.io);
    var ld_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{ "ld", "-o", exe_path, obj_path } });
    _ = try ld_exe.wait(std.testing.io);
    var exe_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{exe_path} });
    const result = try exe_exe.wait(std.testing.io);
    return result.exited;
}

test "return" {
    try std.testing.expectEqual(try compileAndRun("int main(){return 42;}"), 42);
}

test "declare variable" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 42; return x;}"), 42);
}

test "assign variable" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x; x = 42; return x;}"), 42);
}

test "reassign variable" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 1; x = 42; return x;}"), 42);
}

test "add" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 40; x += 2; return x;}"), 42);
}

test "sub" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 50; x -= 8; return x;}"), 42);
}

test "mul" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 7; x *= 6; return x;}"), 42);
}

test "direct expression" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 40 + 2; return x;}"), 42);
}

test "return expression" {
    try std.testing.expectEqual(try compileAndRun("int main(){return 40 + 2;}"), 42);
}

test "sub expression" {
    try std.testing.expectEqual(try compileAndRun("int main(){return 50 - 8;}"), 42);
}

test "mul expression" {
    try std.testing.expectEqual(try compileAndRun("int main(){return 7 * 6;}"), 42);
}

test "arithmetic with variables" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 7; int y = 6; x *= y; return x;}"), 42);
}

test "return expression with variables" {
    try std.testing.expectEqual(try compileAndRun("int main(){int x = 7; int y = 6; return x * y;}"), 42);
}
