const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const code = @embedFile("test.c");
pub fn main(init: std.process.Init) !void {
    const positions = try tokenizer.lexemize(init.gpa, code);
    defer init.gpa.free(positions);
    std.debug.print("{s}\n", .{code});
    for (positions) |p| {
        std.debug.print("{any}: ", .{p});
        std.debug.print("\"{s}\"\n", .{tokenizer.posToSymbol(p, code)});
    }
}
