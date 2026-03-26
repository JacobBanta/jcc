const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const tokens = try tokenizer.lex(allocator, code);
    defer init.gpa.free(tokens);
    var ast = try parser.parse(allocator, tokens);
    defer ast.deinit(allocator);
    std.debug.print("{s}\n", .{code});
    for (tokens) |t| {
        std.debug.print("{any}: {s}\n", .{ t.info, t.lexeme.value });
    }
    std.debug.print("{f}", .{ast});
    const @"asm" = try codegen.genCode(allocator, &.{ast});
    defer allocator.free(@"asm");
    try std.Io.File.stdout().writeStreamingAll(init.io, codegen._start);
    try std.Io.File.stdout().writeStreamingAll(init.io, @"asm");
}
