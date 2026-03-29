//! Transform tokens into an AST
const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const assert = std.debug.assert;

pub const ASTNode = struct {
    tokens: []const Token = &.{},
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
    while (i < tokens.len - 1) : (i += 1) {
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

            try children.append(allocator, try parseScope(allocator, tokens[i .. end + 1]));
            i = end;
        } else if (tokens[i].info == .keyword) {
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
                .int => {
                    var a: ASTNode = .{ .tokens = tokens[i .. semicolon + 1], .nodeType = .declaration };
                    if (tokens[i .. semicolon + 1].len == 3) {
                        a.children = try allocator.alloc(ASTNode, 1);
                        a.children[0] = .{ .tokens = tokens[i + 1 .. i + 2], .nodeType = .variable };
                    } else {
                        a.children = try allocator.alloc(ASTNode, 2);
                        a.children[0] = .{ .tokens = tokens[i + 1 .. i + 2], .nodeType = .variable };
                        a.children[1] = try parseExpression(allocator, tokens[i + 3 .. semicolon]);
                    }
                    try children.append(allocator, a);
                },
                //else => unreachable,
            }
            i = semicolon;
        } else if (tokens[i].info == .identifier) {
            const semicolon = blk: {
                for (tokens[i..], i..) |t, ind| {
                    if (t.is(";")) {
                        break :blk ind;
                    }
                }
                unreachable;
            };
            if (tokens[i + 1].info != .operator) unreachable;
            if (tokens[i + 1].is("=") or
                tokens[i + 1].is("+=") or
                tokens[i + 1].is("-=") or
                tokens[i + 1].is("*=") or
                tokens[i + 1].is("/="))
            {
                var a: ASTNode = .{ .tokens = tokens[i .. semicolon + 1], .nodeType = .binary_expression };
                a.children = try allocator.alloc(ASTNode, 3);
                a.children[0] = .{ .tokens = tokens[i .. i + 1], .nodeType = .variable };
                a.children[1] = .{ .tokens = tokens[i + 1 .. i + 2], .nodeType = .operator };
                a.children[2] = try parseExpression(allocator, tokens[i + 2 .. semicolon]);
                try children.append(allocator, a);
            } else unreachable;
            i = semicolon;
        } else {
            std.debug.print("{any}\n", .{tokens[i]});
            unreachable;
        }
    }
    node.children = try children.toOwnedSlice(allocator);
    return node;
}
fn parseExpression(allocator: std.mem.Allocator, tokens: []Token) !ASTNode {
    if (tokens.len == 1) {
        if (tokens[0].info == .identifier) {
            return .{ .tokens = tokens, .nodeType = .variable };
        }
        return .{ .tokens = tokens, .nodeType = .literal };
    }
    if (tokens[0].is("(")) {
        if (findClosingParen(tokens) == tokens.len - 1) return parseExpression(allocator, tokens[1 .. tokens.len - 1]);
    }
    if (tokens.len == 3) {
        assert(tokens[0].info != .operator);
        assert(tokens[1].info == .operator);
        assert(tokens[2].info != .operator);
        return binExpr(allocator, tokens[0..1], tokens[1], tokens[2..3]);
    } else {
        var min: usize = std.math.maxInt(usize);
        var minIndex: usize = std.math.maxInt(usize);
        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            if (tokens[i].is("(")) i += findClosingParen(tokens[i..]);
            if (tokens[i].info == .operator and min >= bindingPower(tokens, i).toValue()) {
                min = bindingPower(tokens, i).toValue();
                minIndex = i;
            }
        }
        i = minIndex;
        if (i == 0) {
            return unExprPre(allocator, tokens[0], tokens[1..]);
        }
        if (i == tokens.len - 1) {
            return unExprPost(allocator, tokens[0 .. tokens.len - 1], tokens[tokens.len - 1]);
        }
        return binExpr(allocator, tokens[0..i], tokens[i], tokens[i + 1 ..]);
    }
}
fn findClosingParen(tokens: []Token) usize {
    assert(tokens[0].is("("));
    var depth: usize = 0;
    for (tokens[0..], 0..) |t, i| {
        if (t.is("(")) depth += 1;
        if (t.is(")")) {
            if (depth == 1) return i;
            depth -= 1;
        }
    }
    unreachable;
}
/// returns an expression node
fn binExpr(
    allocator: std.mem.Allocator,
    lhs: []Token,
    op: Token,
    rhs: []Token,
) error{OutOfMemory}!ASTNode {
    assert(@intFromPtr(lhs.ptr) + @sizeOf(Token) * (lhs.len + 1) == @intFromPtr(rhs.ptr));
    assert(std.meta.eql(op, @as(*Token, @ptrFromInt(@intFromPtr(lhs.ptr) + @sizeOf(Token) * lhs.len)).*));
    var child = try allocator.alloc(ASTNode, 1);
    const tokens: []Token = @as([*c]Token, @ptrCast(lhs.ptr))[0 .. lhs.len + 1 + rhs.len];
    child[0] = ASTNode{ .tokens = tokens, .nodeType = .binary_expression };
    var children = try allocator.alloc(ASTNode, 3);
    children[0] = try parseExpression(allocator, lhs);
    children[1] = ASTNode{
        .tokens = @as([*]Token, @ptrFromInt(@intFromPtr(lhs.ptr) + @sizeOf(Token) * lhs.len))[0..1],
        .nodeType = .operator,
    };
    children[2] = try parseExpression(allocator, rhs);
    child[0].children = children;
    return .{ .children = child, .nodeType = .expression, .tokens = tokens };
}
/// returns an expression node
fn unExprPre(
    allocator: std.mem.Allocator,
    op: Token,
    rhs: []Token,
) error{OutOfMemory}!ASTNode {
    assert(std.meta.eql(op, @as(*Token, @ptrFromInt(@intFromPtr(rhs.ptr) - @sizeOf(Token))).*));
    var child = try allocator.alloc(ASTNode, 1);
    const tokens: []Token = @as([*c]Token, @ptrFromInt(@intFromPtr(rhs.ptr) - @sizeOf(Token)))[0 .. 1 + rhs.len];
    child[0] = ASTNode{ .tokens = tokens, .nodeType = .unary_expression };
    var children = try allocator.alloc(ASTNode, 2);
    children[0] = ASTNode{ .tokens = tokens[0..1], .nodeType = .operator };
    children[1] = try parseExpression(allocator, rhs);
    child[0].children = children;
    return .{ .children = child, .nodeType = .expression, .tokens = tokens };
}
/// returns an expression node
fn unExprPost(
    allocator: std.mem.Allocator,
    lhs: []Token,
    op: Token,
) error{OutOfMemory}!ASTNode {
    // assert(op.info == .operator);
    // assert(lhs[0].info != .operator);
    assert(std.meta.eql(op, @as(*Token, @ptrFromInt(@intFromPtr(lhs.ptr) + @sizeOf(Token) * lhs.len)).*));
    var child = try allocator.alloc(ASTNode, 1);
    const tokens: []Token = @as([*c]Token, @ptrCast(lhs.ptr))[0 .. lhs.len + 1];
    child[0] = ASTNode{ .tokens = tokens, .nodeType = .unary_expression };
    var children = try allocator.alloc(ASTNode, 2);
    children[0] = try parseExpression(allocator, lhs);
    children[1] = ASTNode{
        .tokens = @as([*]Token, @ptrFromInt(@intFromPtr(lhs.ptr) + @sizeOf(Token) * lhs.len))[0..1],
        .nodeType = .operator,
    };
    child[0].children = children;
    return .{ .children = child, .nodeType = .expression, .tokens = tokens };
}

const BindingPower = enum {
    none,
    add,
    sub,
    mul,
    div,
    paren,
    unary,
    fn toValue(self: BindingPower) usize {
        return switch (self) {
            .none => 0,
            .add, .sub => 10,
            .mul, .div => 20,
            .unary => std.math.maxInt(u16) - 1,
            .paren => std.math.maxInt(u16),
        };
    }
};

fn bindingPower(tokens: []Token, i: usize) BindingPower {
    if (i == tokens.len - 1) {
        return .none;
    }
    if (i > 0 and tokens[i].info == .operator and tokens[i - 1].info == .operator) {
        return .unary;
    }
    if (i == 0 and tokens[i].info == .operator) {
        return .unary;
    }
    if (tokens[i].info == .operator) {
        assert(tokens[i].lexeme.value.len == 1);
        return switch (tokens[i].lexeme.value[0]) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            else => unreachable,
        };
    }
    assert(tokens[i + 1].info == .operator);
    return bindingPower(tokens, i + 1);
}
