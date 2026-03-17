//! Handles the lexical anaylsis phase.
const std = @import("std");
pub const Token = struct {
    type: enum {
        keyword,
        literal,
        punctuation,
        identifier,
    },
    value: []const u8,
    /// Positions are tracked to allow compiler errors.
    position: Position,
};
/// Position functions as both a lexeme,
/// and as a part of the Token.
pub const Position = struct {
    row: usize,
    col: usize,
    length: usize,
};
/// These characters are the main whitespace characters.
/// This does not include form feed or vertical tab.
const whitespace = " \n\r\t";
/// These are the operators that (mostly) indicate the end of a lexeme.
const operators = "+-*/%<=>!~&|^";

/// Generate a list of lexemes associated with a source file.
/// Returns an owned slice of Position.
pub fn lexemize(allocator: std.mem.Allocator, source: []const u8) ![]Position {
    // 50 was chosen arbitrarily.
    // I just thought it would be enough without being too wasteful.
    var positions = try std.ArrayList(Position).initCapacity(allocator, 50);
    var row: usize = 0;
    var col: usize = 0;
    // Index into source.
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        switch (source[i]) {
            // Newline makes a new row.
            // Other whitespace just adds to col.
            ' ', '\r', '\t' => {
                col += 1;
            },
            '\n' => {
                row += 1;
                col = 0;
            },
            // Numbers are complex.
            // They start with a digit,
            // but may contain letters (0x00, 123456789ULL, etc),
            // and even have the symbols + and - (314e-2).
            // The lexemes returned here are not guaranteed to be valid numbers.
            '0'...'9' => {
                // TODO: remove `.?` in place of better error handling
                var end = std.mem.findAny(u8, source[i..], whitespace ++ ",()[];" ++ operators).?;
                if (std.ascii.toLower(source[i + end - 1]) == 'e') {
                    if (source[i + end] == '+' or source[i + end] == '-') {
                        end += 1;
                        end += std.mem.findAny(u8, source[i + end ..], whitespace ++ ",()[];" ++ operators).?;
                    }
                }
                try positions.append(allocator, .{
                    .col = col,
                    .row = row,
                    .length = end,
                });
                col += end;
                i += end - 1;
            },
            'a'...'z', 'A'...'Z', '_' => {
                const end = std.mem.findAny(u8, source[i..], whitespace ++ ".,()[]{};" ++ operators).?;
                try positions.append(allocator, .{
                    .col = col,
                    .row = row,
                    .length = end,
                });
                col += end;
                i += end - 1;
            },
            // This does NOT include division because of comments.
            '+', '-', '*', '%', '<', '=', '>', '!', '~', '&', '|', '^' => {
                const end = std.mem.findAny(u8, source[i..], whitespace ++ std.ascii.letters ++ "_0123456789.,()[]{};").?;
                try positions.append(allocator, .{
                    .col = col,
                    .row = row,
                    .length = end,
                });
                col += end;
                i += end - 1;
            },
            '(', ')', '[', ']', '{', '}', ',', '.', ';' => {
                try positions.append(allocator, .{
                    .col = col,
                    .row = row,
                    .length = 1,
                });
                col += 1;
            },
            '"', '\'' => |c| {
                var len: usize = 0;
                while (i < source.len) {
                    i += 1;
                    len += 1;
                    if (source[i] == '\\') {
                        i += 1;
                        len += 1;
                        continue;
                    }
                    if (source[i] == c) {
                        len += 1;
                        break;
                    }
                }

                try positions.append(allocator, .{
                    .col = col,
                    .row = row,
                    .length = len,
                });
                col += len;
            },
            // This is comments, multiline comments and division.
            '/' => {
                // TODO: bounds check.
                if (source[i + 1] == '/') {
                    const end = std.mem.findScalar(u8, source[i..], '\n').?;
                    try positions.append(allocator, .{
                        .col = col,
                        .row = row,
                        .length = end,
                    });
                    col += end;
                    i += end - 1;
                } else if (source[i + 1] == '*') {
                    const end = std.mem.find(u8, source[i..], "*/").?;
                    try positions.append(allocator, .{
                        .col = col,
                        .row = row,
                        .length = end + 2,
                    });
                    // Row and col need to be properly set after a multiline comment.
                    row += std.mem.countScalar(u8, source[i .. i + end], '\n');
                    col = end - (std.mem.findScalarLast(u8, source[i .. i + end], '\n') orelse 0) + 1;
                    i += end + 1;
                } else {
                    try positions.append(allocator, .{
                        .col = col,
                        .row = row,
                        .length = 1,
                    });
                    col += 1;
                }
            },

            else => |c| {
                std.debug.print("unhandled char: 0x{x} : {c}\n", .{ c, c });
            },
        }
    }
    return positions.toOwnedSlice(allocator);
}

pub fn posToSymbol(pos: Position, source: []const u8) []const u8 {
    var i: usize = 0;
    for (0..pos.row) |_| {
        i = std.mem.findScalarPos(u8, source, i, '\n').? + 1;
    }
    i += pos.col;
    return source[i .. i + pos.length];
}
