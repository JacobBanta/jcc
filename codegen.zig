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
                    const scope = try genCode(allocator, ast[0].children, ctx);
                    defer allocator.free(scope);
                    try code.appendSlice(allocator, scope);
                } else unreachable;
            },
            .scope => {
                const declarationsLength = ctx.?.declarations.items.len;
                defer ctx.?.declarations.shrinkRetainingCapacity(declarationsLength);

                for (node.children) |child| {
                    const childCode = try genCode(allocator, &.{child}, ctx);
                    defer allocator.free(childCode);
                    try code.appendSlice(allocator, childCode);
                }
            },
            .statement => {
                if (node.tokens[0].is("return")) {
                    try code.appendSlice(allocator, "mov rax, ");
                    if (node.children[0].nodeType == .literal) {
                        try code.appendSlice(allocator, node.children[0].tokens[0].lexeme.value);
                    } else {
                        for (ctx.?.declarations.items, 0..) |decl, i| {
                            if (decl.tokens[0].is(node.children[0].tokens[0].lexeme.value)) {
                                try code.print(allocator, "[rbp - {d}]", .{(i + 1) * 8});
                                break;
                            }
                        } else return error.UnexpectedIdentifier;
                    }
                    try code.appendSlice(allocator, "\n" ++ epilogue);
                } else unreachable;
            },
            .declaration => {
                if (node.children.len == 2) {
                    try ctx.?.declarations.append(allocator, node.children[0]);
                    if (node.children[1].nodeType == .literal) {
                        const m = try move(
                            allocator,
                            .{ .literal = node.children[1].tokens[0].lexeme.value },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        );
                        defer allocator.free(m);
                        try code.appendSlice(allocator, m);
                    } else if (node.children[1].nodeType == .variable) {
                        const m = try move(
                            allocator,
                            .{ .variable = node.children[1].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        );
                        defer allocator.free(m);
                        try code.appendSlice(allocator, m);
                        const m2 = try move(
                            allocator,
                            .{ .register = .rax },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        );
                        defer allocator.free(m2);
                        try code.appendSlice(allocator, m2);
                    } else unreachable;
                } else if (node.children.len == 1) {
                    try ctx.?.declarations.append(allocator, node.children[0]);
                } else unreachable;
            },
            .binary_expression => {
                if (node.children[1].tokens[0].is("=")) {
                    if (node.children[2].nodeType == .literal) {
                        try code.appendSlice(allocator, "mov ");
                        for (ctx.?.declarations.items, 0..) |decl, i| {
                            if (decl.tokens[0].is(node.children[0].tokens[0].lexeme.value)) {
                                try code.print(allocator, "[rbp - {d}], ", .{(i + 1) * 8});
                                break;
                            }
                        } else return error.UnexpectedIdentifier;
                        assert(node.children[2].tokens.len == 1);
                        try code.appendSlice(allocator, node.children[2].tokens[0].lexeme.value);
                        try code.appendSlice(allocator, "\n");
                    } else if (node.children[2].nodeType == .variable) {
                        try code.appendSlice(allocator, "mov ");
                        for (ctx.?.declarations.items, 0..) |decl, i| {
                            if (decl.tokens[0].is(node.children[2].tokens[0].lexeme.value)) {
                                try code.print(allocator, "rax, [rbp - {d}]\n", .{(i + 1) * 8});
                                break;
                            }
                        } else return error.UnexpectedIdentifier;
                        try code.appendSlice(allocator, "mov ");
                        for (ctx.?.declarations.items, 0..) |decl, i| {
                            if (decl.tokens[0].is(node.children[0].tokens[0].lexeme.value)) {
                                try code.print(allocator, "[rbp - {d}], rax\n", .{(i + 1) * 8});
                                break;
                            }
                        } else return error.UnexpectedIdentifier;
                    } else unreachable;
                } else unreachable;
            },
            else => unreachable,
        }
    }
    return code.toOwnedSlice(allocator);
}

fn move(allocator: std.mem.Allocator, from: Location, to: Location, ctx: *Context) ![]const u8 {
    var code = std.ArrayList(u8).empty;
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
