const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const tokens = try tokenizer.lex(init.gpa, code);
    defer init.gpa.free(tokens);
    std.debug.print("{s}\n", .{code});
    for (tokens) |t| {
        std.debug.print("{any}:       \t{s}\n", .{ t.type, t.lexeme.value });
    }
}
