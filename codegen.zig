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
pub const main_epilogue = "mov rax, 0\n" ++ epilogue;

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
                if (node.children.len == 1) {
                    try code.appendSlice(allocator, "global ");
                    try code.appendSlice(allocator, node.tokens[1].lexeme.value);
                    try code.appendSlice(allocator, "\n");
                    try code.appendSlice(allocator, node.tokens[1].lexeme.value);
                    try code.appendSlice(allocator, ":\n" ++ prologue);
                    try append(
                        allocator,
                        &code,
                        try genCode(allocator, ast[0].children, ctx),
                    );
                    if (node.tokens[1].is("main")) {
                        try code.appendSlice(allocator, main_epilogue);
                    }
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
                    } else if (node.children[0].nodeType == .expression) {
                        try append(allocator, &code, try genExpression(
                            allocator,
                            node.children[0],
                            .{ .register = .rax },
                            ctx.?,
                        ));
                    } else unreachable;
                    try code.appendSlice(allocator, epilogue);
                } else if (node.tokens[0].is("if")) {
                    try append(allocator, &code, try genExpression(
                        allocator,
                        node.children[0],
                        .{ .register = .rax },
                        ctx.?,
                    ));
                    const else_label = try std.fmt.allocPrint(allocator, "__internal_label_{d}__", .{uniqueID.fetchAdd(1, .acq_rel)});
                    defer allocator.free(else_label);
                    const end_if = try std.fmt.allocPrint(allocator, "__internal_label_{d}__", .{uniqueID.fetchAdd(1, .acq_rel)});
                    defer allocator.free(end_if);

                    const inner = try genCode(allocator, &.{node.children[1]}, ctx);
                    defer allocator.free(inner);
                    const else_code = if (node.children.len == 3) try genCode(allocator, &.{node.children[2]}, ctx) else "";
                    defer if (node.children.len == 3) allocator.free(else_code);
                    try code.print(
                        allocator,
                        \\cmp rax, 0
                        \\je {0s}
                        \\{2s}
                        \\jmp {1s}
                        \\{0s}:
                        \\{3s}
                        \\{1s}:
                    ,
                        .{ else_label, end_if, inner, else_code },
                    );
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
                    } else if (node.children[1].nodeType == .expression) {
                        try append(allocator, &code, try genExpression(
                            allocator,
                            node.children[1],
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
                } else if (node.children[1].tokens[0].is("+=") or
                    node.children[1].tokens[0].is("-=") or
                    node.children[1].tokens[0].is("*="))
                {
                    if (node.children[2].nodeType == .literal) {
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                        assert(node.children[2].tokens.len == 1);
                        if (node.children[1].tokens[0].is("+="))
                            try code.appendSlice(allocator, "add rax, ");
                        if (node.children[1].tokens[0].is("-="))
                            try code.appendSlice(allocator, "sub rax, ");
                        if (node.children[1].tokens[0].is("*="))
                            try code.appendSlice(allocator, "imul rax, ");
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
                        if (node.children[1].tokens[0].is("+="))
                            try code.appendSlice(allocator, "add rax, rdx\n");
                        if (node.children[1].tokens[0].is("-="))
                            try code.appendSlice(allocator, "sub rax, rdx\n");
                        if (node.children[1].tokens[0].is("*="))
                            try code.appendSlice(allocator, "mul rax, rdx\n");
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .register = .rax },
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            ctx.?,
                        ));
                    } else if (node.children[2].nodeType == .expression) {
                        try append(allocator, &code, try genExpression(
                            allocator,
                            node.children[2],
                            .{ .register = .rdx },
                            ctx.?,
                        ));
                        try append(allocator, &code, try move(
                            allocator,
                            .{ .variable = node.children[0].tokens[0].lexeme.value },
                            .{ .register = .rax },
                            ctx.?,
                        ));
                        if (node.children[1].tokens[0].is("+="))
                            try code.appendSlice(allocator, "add rax, rdx\n");
                        if (node.children[1].tokens[0].is("-="))
                            try code.appendSlice(allocator, "sub rax, rdx\n");
                        if (node.children[1].tokens[0].is("*="))
                            try code.appendSlice(allocator, "mul rax, rdx\n");
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
    if (std.meta.eql(from, to)) return "";
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
fn getOffset(ctx: *Context, name: []const u8) !usize {
    for (ctx.declarations.items, 0..) |decl, i| {
        if (decl.tokens[0].is(name)) {
            return i * 8;
        }
    }
    return error.UnexpectedIdentifier;
}
var uniqueID: std.atomic.Value(usize) = .init(0);
fn genExpression(allocator: std.mem.Allocator, exp: ASTNode, to: Location, ctx: *Context) ![]const u8 {
    var code = std.ArrayList(u8).empty;
    defer code.deinit(allocator);
    switch (exp.nodeType) {
        .expression => {
            return genExpression(allocator, exp.children[0], to, ctx);
        },
        .literal => {
            try append(allocator, &code, try move(
                allocator,
                .{ .literal = exp.tokens[0].lexeme.value },
                .{ .register = .rax },
                ctx,
            ));
        },
        .variable => {
            try append(allocator, &code, try move(
                allocator,
                .{ .variable = exp.tokens[0].lexeme.value },
                .{ .register = .rax },
                ctx,
            ));
        },
        .binary_expression => {
            const declarationsLength = ctx.declarations.items.len;
            defer ctx.declarations.shrinkRetainingCapacity(declarationsLength);
            const lhs = exp.children[0];
            const op = exp.children[1];
            const rhs = exp.children[2];
            const name = try std.fmt.allocPrint(allocator, "__internal_expression_var_{d}__", .{uniqueID.fetchAdd(1, .acq_rel)});
            defer allocator.free(name);
            try ctx.declarations.append(allocator, .{ .nodeType = .variable, .tokens = &.{.{ .lexeme = .{ .value = name, .position = undefined }, .info = .identifier }} });
            try append(allocator, &code, try genExpression(allocator, lhs, .{ .register = .rax }, ctx));
            try append(allocator, &code, try move(
                allocator,
                .{ .register = .rax },
                .{ .variable = name },
                ctx,
            ));
            // try code.appendSlice(allocator, "push rax\n");
            try append(allocator, &code, try genExpression(allocator, rhs, .{ .register = .rdx }, ctx));
            try append(allocator, &code, try move(
                allocator,
                .{ .variable = name },
                .{ .register = .rax },
                ctx,
            ));
            // try code.appendSlice(allocator, "pop rax\n");
            const inst: []const u8 = if (op.tokens[0].is("+"))
                "add rax, rdx\n"
            else if (op.tokens[0].is("-"))
                "sub rax, rdx\n"
            else if (op.tokens[0].is("*"))
                "imul rax, rdx\n"
            else if (op.tokens[0].is("/"))
                "mov rcx, rdx\ncqo\nidiv rcx\n"
            else if (op.tokens[0].is("%"))
                "mov rcx, rdx\ncqo\nidiv rcx\nmov rax, rdx\n"
            else if (op.tokens[0].is("=="))
                "cmp rax, rdx\nsete al\nmovzx rax, al\n"
            else if (op.tokens[0].is("!="))
                "cmp rax, rdx\nsetne al\nmovzx rax, al\n"
            else if (op.tokens[0].is(">="))
                "cmp rax, rdx\nsetge al\nmovzx rax, al\n"
            else if (op.tokens[0].is("<="))
                "cmp rax, rdx\nsetle al\nmovzx rax, al\n"
            else if (op.tokens[0].is(">"))
                "cmp rax, rdx\nsetg al\nmovzx rax, al\n"
            else if (op.tokens[0].is("<"))
                "cmp rax, rdx\nsetl al\nmovzx rax, al\n"
            else
                unreachable;
            try code.appendSlice(allocator, inst);
        },
        .unary_expression => {
            const is_prefix = exp.children[0].nodeType == .operator;
            if (is_prefix) {
                const op = exp.children[0];
                const operand = exp.children[1];
                try append(allocator, &code, try genExpression(allocator, operand, .{ .register = .rax }, ctx));
                if (op.tokens[0].is("-")) {
                    try code.appendSlice(allocator, "neg rax\n");
                } else if (op.tokens[0].is("++")) {
                    try code.appendSlice(allocator, "inc rax\n");
                    try append(allocator, &code, try move(
                        allocator,
                        .{ .register = .rax },
                        .{ .variable = operand.tokens[0].lexeme.value },
                        ctx,
                    ));
                } else if (op.tokens[0].is("--")) {
                    try code.appendSlice(allocator, "dec rax\n");
                    try append(allocator, &code, try move(
                        allocator,
                        .{ .register = .rax },
                        .{ .variable = operand.tokens[0].lexeme.value },
                        ctx,
                    ));
                } else unreachable;
            } else {
                const operand = exp.children[0];
                const op = exp.children[1];
                try append(allocator, &code, try genExpression(allocator, operand, .{ .register = .rax }, ctx));
                std.log.debug("{s}", .{op.tokens[0].lexeme.value});
                if (op.tokens[0].is("++")) {
                    try code.print(
                        allocator,
                        "inc qword [rbp - {d}]\n",
                        .{try getOffset(ctx, operand.tokens[0].lexeme.value)},
                    );
                } else if (op.tokens[0].is("--")) {
                    try code.print(
                        allocator,
                        "dec qword [rbp - {d}]\n",
                        .{try getOffset(ctx, operand.tokens[0].lexeme.value)},
                    );
                } else unreachable;
            }
        },
        else => unreachable,
    }

    try append(allocator, &code, try move(
        allocator,
        .{ .register = .rax },
        to,
        ctx,
    ));
    return code.toOwnedSlice(allocator);
}
