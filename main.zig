const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const lexemes = try tokenizer.lexemize(init.gpa, code);
    defer init.gpa.free(lexemes);
    std.debug.print("{s}\n", .{code});
    for (lexemes) |l| {
        std.debug.print("{any} | {any}\n", .{ l, tokenizer.posToSymbol(l.position, code) });
    }
}
