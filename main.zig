const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const tokens = try tokenizer.lex(init.gpa, code);
    defer init.gpa.free(tokens);
    var ast = try parser.parse(init.gpa, tokens);
    defer ast.deinit(init.gpa);
    std.debug.print("{s}", .{code});
    for (tokens) |t| {
        std.debug.print("{any}: {s}\n", .{ t.info, t.lexeme.value });
    }
    std.debug.print("{f}\n", .{ast});
}
