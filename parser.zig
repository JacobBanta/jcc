//! Transform tokens into an AST
const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const assert = std.debug.assert;

const ASTNode = struct {
    tokens: []Token = &.{},
    nodeType: enum {
        declaration,
        expression,
        unary_expression,
        binary_expression,
        function_call,
        function,
        statement,
        literal,
        type,
        variable,
        scope,
        operator,
    },
    children: []ASTNode = &.{},
    pub fn deinit(self: *ASTNode, allocator: std.mem.Allocator) void {
        if (self.children.len > 0) {
            for (self.children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(self.children);
        }
    }
    pub fn format(self: ASTNode, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.print(0, writer);
    }
    fn print(self: ASTNode, offset: usize, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (0..offset) |_| {
            try writer.print(" ", .{});
        }
        try writer.print(".{s}\n", .{@tagName(self.nodeType)});
        for (self.children) |child| {
            try child.print(offset + 1, writer);
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []Token) !ASTNode {
    for (tokens, 0..) |t, i| {
        if (t.is("int") and tokens[i + 2].is("(")) {
            const end = blk: {
                var depth: usize = 0;
                for (tokens[i..], i..) |t2, ind| {
                    if (t2.is("{")) {
                        depth += 1;
                    } else if (t2.is("}")) {
                        if (depth == 1) {
                            break :blk ind;
                        } else depth -= 1;
                    }
                }
                unreachable;
            };
            return try parseFunction(allocator, tokens[i .. end + 1]);
        } else unreachable;
    }
    unreachable;
}

fn parseFunction(allocator: std.mem.Allocator, tokens: []Token) !ASTNode {
    var children = std.ArrayList(ASTNode).empty;
    const endArgs = blk: {
        var depth: usize = 0;
        for (tokens, 0..) |t, i| {
            if (t.is("(")) {
                depth += 1;
            } else if (t.is(")")) {
                if (depth == 1) {
                    break :blk i;
                } else depth -= 1;
            }
        }
        unreachable;
    };
    if (!tokens[3].is(")") and !tokens[3].is("void")) {
        try parseArgs(allocator, tokens[3..endArgs], &children);
    }
    if (!tokens[endArgs + 1].is("{")) return error.ExpectedOpenParam;
    try children.append(allocator, try parseScope(allocator, tokens[endArgs + 1 ..]));
    return .{
        .tokens = tokens,
        .nodeType = .function,
        .children = try children.toOwnedSlice(allocator),
    };
}
fn parseArgs(allocator: std.mem.Allocator, tokens: []Token, fill: *std.ArrayList(ASTNode)) !void {
    _ = allocator;
    _ = tokens;
    _ = fill;
    unreachable;
}
fn parseScope(allocator: std.mem.Allocator, tokens: []Token) !ASTNode {
    assert(tokens[0].is("{"));
    assert(tokens[tokens.len - 1].is("}"));
    var node: ASTNode = .{ .nodeType = .scope, .tokens = tokens };
    var children = std.ArrayList(ASTNode).empty;
    var i: usize = 1;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].is("{")) {
            const end = blk: {
                var depth: usize = 0;
                for (tokens[i..], i..) |t, ind| {
                    if (t.is("{")) {
                        depth += 1;
                    } else if (t.is("}")) {
                        if (depth == 1) {
                            break :blk ind;
                        } else depth -= 1;
                    }
                }
                unreachable;
            };

            try children.append(allocator, try parseScope(allocator, tokens[i..end]));
            i = end;
        }
        if (tokens[i].info == .keyword) {
            const semicolon = blk: {
                for (tokens[i..], i..) |t, ind| {
                    if (t.is(";")) {
                        break :blk ind;
                    }
                }
                unreachable;
            };
            switch (tokens[i].info.keyword) {
                .@"return" => {
                    var a: ASTNode = .{ .tokens = tokens[i .. semicolon + 1], .nodeType = .statement };
                    a.children = try allocator.alloc(ASTNode, 1);
                    a.children[0] = try parseExpression(allocator, tokens[i + 1 .. semicolon]);
                    try children.append(allocator, a);
                },
                else => unreachable,
            }
        }
    }
    node.children = try children.toOwnedSlice(allocator);
    return node;
}
fn parseExpression(allocator: std.mem.Allocator, tokens: []Token) !ASTNode {
    _ = allocator;
    if (tokens.len == 1) {
        return .{ .tokens = tokens, .nodeType = .literal };
    } else unreachable;
}
