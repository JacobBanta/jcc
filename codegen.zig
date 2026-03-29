const std = @import("std");
const ASTNode = @import("parser.zig").ASTNode;
const assert = std.debug.assert;
pub const _start =
    \\global _start
    \\_start:
    \\and rsp, -16
    \\call main
    \\mov rdi, rax
    \\mov rax, 60
    \\syscall
    \\
;
pub const prologue =
    \\push rbp
    \\mov rbp, rsp
    \\
;
pub const epilogue =
    \\mov rsp, rbp
    \\pop rbp
    \\ret
    \\
;

const Context = struct {
    declarations: std.ArrayList(ASTNode) = .empty,
};
const Location = union(enum) {
    register: enum { rax, rdi, rbx, rcx, rdx },
    variable: []const u8,
    literal: []const u8,
};
pub fn genCode(allocator: std.mem.Allocator, ast: []const ASTNode, ctx: ?*Context) ![]const u8 {
    if (ctx == null) {
        var c = try allocator.create(Context);
        defer allocator.destroy(c);
        c.declarations = .empty;
        defer c.declarations.deinit(allocator);
        return try genCode(allocator, ast, c);
    }
    var code = std.ArrayList(u8).empty;

    for (ast) |node| {
        switch (node.nodeType) {
            .function => {
                if (ast[0].children.len == 1) {
                    try code.appendSlice(allocator, "global ");
                    try code.appendSlice(allocator, ast[0].tokens[1].lexeme.value);
                    try code.appendSlice(allocator, "\n");
                    try code.appendSlice(allocator, ast[0].tokens[1].lexeme.value);
                    try code.appendSlice(allocator, ":\n" ++ prologue);
                    try append(
                        allocator,
                        &code,
                        try genCode(allocator, ast[0].children, ctx),
                    );
                } else unreachable;
            },
            .scope => {
                const declarationsLength = ctx.?.declarations.items.len;
                defer ctx.?.declarations.shrinkRetainingCapacity(declarationsLength);

                for (node.children) |child| {
                    try append(
                        allocator,
                        &code,
                        try genCode(allocator, &.{child}, ctx),
                    );
                }
            },
            .statement => {
                if (node.tokens[0].is("return")) {
                    if (node.children[0].nodeType == .literal) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .literal = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                    } else if (node.children[0].nodeType == .variable) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                    } else unreachable;
                    try code.appendSlice(allocator, epilogue);
                } else unreachable;
            },
            .declaration => {
                if (node.children.len == 2) {
                    try ctx.?.declarations.append(allocator, node.children[0]);
                    if (node.children[1].nodeType == .literal) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .literal = node.children[1].tokens[0].lexeme.value },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else if (node.children[1].nodeType == .variable) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[1].tokens[0].lexeme.value },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else unreachable;
                } else if (node.children.len == 1) {
                    try ctx.?.declarations.append(allocator, node.children[0]);
                } else unreachable;
            },
            .binary_expression => {
                if (node.children[1].tokens[0].is("=")) {
                    if (node.children[2].nodeType == .literal) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .literal = node.children[2].tokens[0].lexeme.value },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else if (node.children[2].nodeType == .variable) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[2].tokens[0].lexeme.value },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else unreachable;
                } else if (node.children[1].tokens[0].is("+=")) {
                    if (node.children[2].nodeType == .literal) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                        assert(node.children[2].tokens.len == 1);
                        try code.appendSlice(allocator, "add rax, ");
                        try code.appendSlice(allocator, node.children[2].tokens[0].lexeme.value);
                        try code.appendSlice(allocator, "\n");
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .register = .rax },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else if (node.children[2].nodeType == .variable) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                        assert(node.children[2].tokens.len == 1);
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[2].tokens[0].lexeme.value },
                            .{ .register = .rdx },
                            ctx.?,
                        ));
                        try code.appendSlice(allocator, "add rax, rdx");
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .register = .rax },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else unreachable;
                } else unreachable;
            },
            else => unreachable,
        }
    }
    return code.toOwnedSlice(allocator);
}

fn append(allocator: std.mem.Allocator, arraylist: *std.ArrayList(u8), items: []const u8) !void {
    defer allocator.free(items);
    try arraylist.appendSlice(allocator, items);
}

fn move(allocator: std.mem.Allocator, from: Location, to: Location, ctx: *Context) ![]const u8 {
    var code = std.ArrayList(u8).empty;
    if (from == .variable and to == .variable) {
        const one = try move(allocator, from, .{ .register = .rax }, ctx);
        defer allocator.free(one);
        const two = try move(allocator, .{ .register = .rax }, to, ctx);
        defer allocator.free(two);
        return std.mem.join(allocator, "", &.{ one, two });
    }
    try code.appendSlice(allocator, "mov ");
    if (to == .variable) {
        assert(from != .variable);
        if (from == .register) {
            for (ctx.declarations.items, 0..) |decl, i| {
                if (decl.tokens[0].is(to.variable)) {
                    try code.print(
                        allocator,
                        "[rbp - {d}], {s}\n",
                        .{ (i + 1) * 8, @tagName(from.register) },
                    );
                    break;
                }
            } else return error.UnexpectedIdentifier;
        } else if (from == .literal) {
            for (ctx.declarations.items, 0..) |decl, i| {
                if (decl.tokens[0].is(to.variable)) {
                    try code.print(allocator, "[rbp - {d}], {s}\n", .{ (i + 1) * 8, from.literal });
                    break;
                }
            } else return error.UnexpectedIdentifier;
        } else unreachable;
    } else if (from == .variable) {
        assert(to == .register);
        for (ctx.declarations.items, 0..) |decl, i| {
            if (decl.tokens[0].is(from.variable)) {
                try code.print(allocator, "{s}, [rbp - {d}]\n", .{ @tagName(to.register), (i + 1) * 8 });
                break;
            }
        } else return error.UnexpectedIdentifier;
    } else {
        assert(to == .register);
        if (from == .register) {
            try code.print(allocator, "{s}, {s}\n", .{ @tagName(to.register), @tagName(from.register) });
        } else if (from == .literal) {
            try code.print(allocator, "{s}, {s}\n", .{ @tagName(to.register), from.literal });
        } else unreachable;
    }
    return code.toOwnedSlice(allocator);
}
