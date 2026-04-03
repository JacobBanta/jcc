//! Handles the lexical anaylsis phase.
const std = @import("std");

/// Turns source into []Token.
pub fn lex(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    const lexemes = try lexemize(allocator, source);
    defer allocator.free(lexemes);
    const tokens = try allocator.alloc(Token, lexemes.len);
    for (0..tokens.len) |i| {
        tokens[i] = tokenize(lexemes[i]) catch std.debug.panic("Failed to tokenize lexeme: `{s}`\n", .{lexemes[i].value});
    }
    return tokens;
}

/// A lexeme is a chunk of code before it has been assigned a type.
/// They are not always syntactically correct.
pub const Lexeme = struct {
    position: Position,
    value: []const u8,
};
/// The position of each token is kept for debugging and error messages
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
/// Returns an owned slice of Lexeme.
fn lexemize(allocator: std.mem.Allocator, source: []const u8) ![]Lexeme {
    // 50 was chosen arbitrarily.
    // I just thought it would be enough without being too wasteful.
    var lexemes = try std.ArrayList(Lexeme).initCapacity(allocator, 50);
    var row: usize = 0;
    var col: usize = 0;
    // Index into source.
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        sw: switch (source[i]) {
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
                try lexemes.append(allocator, .{
                    .position = .{
                        .col = col,
                        .row = row,
                        .length = end,
                    },
                    .value = source[i .. i + end],
                });
                col += end;
                i += end - 1;
            },
            'a'...'z', 'A'...'Z', '_' => {
                const end = std.mem.findAny(u8, source[i..], whitespace ++ ".,()[]{}:;" ++ operators).?;
                try lexemes.append(allocator, .{
                    .position = .{
                        .col = col,
                        .row = row,
                        .length = end,
                    },
                    .value = source[i .. i + end],
                });
                col += end;
                i += end - 1;
            },
            // This does NOT include division because of comments.
            '+', '-', '*', '%', '<', '=', '>', '!', '~', '&', '|', '^' => {
                const end = std.mem.findAny(u8, source[i..], whitespace ++ std.ascii.letters ++ "_0123456789.,()[]{};").?;
                try lexemes.append(allocator, .{
                    .position = .{
                        .col = col,
                        .row = row,
                        .length = end,
                    },
                    .value = source[i .. i + end],
                });
                col += end;
                i += end - 1;
            },
            '(', ')', '[', ']', '{', '}', ',', '.', ':', ';' => {
                try lexemes.append(allocator, .{
                    .position = .{
                        .col = col,
                        .row = row,
                        .length = 1,
                    },
                    .value = source[i .. i + 1],
                });
                col += 1;
            },
            '"', '\'' => |c| {
                const start = i;
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

                try lexemes.append(allocator, .{
                    .position = .{
                        .col = col,
                        .row = row,
                        .length = len,
                    },
                    .value = source[start .. i + 1],
                });
                col += len;
            },
            // This is comments, multiline comments and division.
            '/' => {
                // TODO: bounds check.
                if (source[i + 1] == '/') {
                    const end = std.mem.findScalar(u8, source[i..], '\n').?;
                    // Dont use the comment as a lexeme.
                    col += end;
                    i += end - 1;
                } else if (source[i + 1] == '*') {
                    const end = std.mem.find(u8, source[i..], "*/").?;
                    // Dont use the comment as a lexeme.
                    // Row and col need to be properly set after a multiline comment.
                    row += std.mem.countScalar(u8, source[i .. i + end], '\n');
                    col = end - (std.mem.findScalarLast(u8, source[i .. i + end], '\n') orelse 0) + 1;
                    i += end + 1;
                } else {
                    // Treat division the same as multiplication.
                    continue :sw '*';
                }
            },

            else => |c| {
                std.debug.print("unhandled char: 0x{x} : {c}\n", .{ c, c });
            },
        }
    }
    return lexemes.toOwnedSlice(allocator);
}

pub const Keyword = enum {
    int,
    @"return",
    @"if",
    @"else",
    @"for",
    @"while",
    do,
    goto,
    @"break",
    @"continue",
};
pub const Punctuation = enum {
    @"(",
    @")",
    @"[",
    @"]",
    @"{",
    @"}",
    @",",
    @".",
    @";",
    @":",
    pub fn fromChar(c: u8) Punctuation {
        return switch (c) {
            '(' => .@"(",
            ')' => .@")",
            '[' => .@"[",
            ']' => .@"]",
            '{' => .@"{",
            '}' => .@"}",
            ',' => .@",",
            '.' => .@".",
            ';' => .@";",
            ':' => .@":",
            else => unreachable,
        };
    }
};

/// Contains the type information of a lexeme.
pub const Token = struct {
    info: union(enum) {
        keyword: Keyword,
        numericLiteral: void,
        stringLiteral: void,
        charLiteral: void,
        punctuation: Punctuation,
        identifier: void,
        operator: void,
    },
    lexeme: Lexeme,
    pub fn is(self: Token, token: []const u8) bool {
        return std.mem.eql(u8, self.lexeme.value, token);
    }
};

/// Turns a lexeme into a token.
/// Does some basic validation.
fn tokenize(lexeme: Lexeme) !Token {
    switch (lexeme.value[0]) {
        '0'...'9' => {
            try validateNumber(lexeme.value);
            return .{ .lexeme = lexeme, .info = .numericLiteral };
        },
        'a'...'z', 'A'...'Z', '_' => {
            inline for (std.meta.tags(Keyword)) |k| {
                if (std.mem.eql(u8, lexeme.value, @tagName(k))) {
                    return .{ .lexeme = lexeme, .info = .{ .keyword = k } };
                }
            }
            return .{ .lexeme = lexeme, .info = .identifier };
        },
        '+', '-', '*', '/', '%', '<', '=', '>', '!', '~', '&', '|', '^' => {
            return .{ .lexeme = lexeme, .info = .operator };
        },
        '(', ')', '[', ']', '{', '}', ',', '.', ':', ';' => |p| {
            return .{ .lexeme = lexeme, .info = .{ .punctuation = .fromChar(p) } };
        },
        '"' => {
            return .{ .lexeme = lexeme, .info = .stringLiteral };
        },
        '\'' => {
            return .{ .lexeme = lexeme, .info = .charLiteral };
        },
        else => unreachable,
    }
}

fn validateNumber(number: []const u8) !void {
    var base: enum { dec, hex, bin, oct } = .dec;
    var i: usize = 0;
    while (i < number.len) : (i += 1) {
        const digit = number[i];
        if (digit != '0') {
            if (digit == 'o') {
                base = .oct;
            } else if (digit == 'x') {
                base = .hex;
            } else if (digit == 'b') {
                base = .bin;
            } else if (digit >= '1' and digit <= '9') {
                // Could be octal. Not my problem.
                base = .dec;
            }
        }
    }
    i += 1;
    while (i < number.len) : (i += 1) {
        // TODO: make thes checks handle edge cases
        if (base == .bin) {
            if (number[i] != '0' and number[i] != '1') {
                return error.InvalidNumber;
            }
        } else if (base == .oct) {
            if (number[i] < '0' or number[i] > '7') {
                return error.InvalidNumber;
            }
        } else if (base == .dec) {
            if (number[i] < '0' or number[i] > '9') {
                return error.InvalidNumber;
            }
        } else if (base == .hex) {
            if (number[i] < '0' or number[i] > '9' and number[i] < 'A' or number[i] > 'F') {
                return error.InvalidNumber;
            }
        }
    }
}

// TODO: add tests
