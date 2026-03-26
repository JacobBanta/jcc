const std = @import("std");
const ASTNode = @import("parser.zig").ASTNode;
const assert = std.debig.assert;
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
pub fn genCode(allocator: std.mem.Allocator, ast: []const ASTNode, ctx: ?*Context) ![]const u8 {
    if (ctx == null) {
        var c = try allocator.create(Context);
        defer allocator.destroy(c);
        c.declarations = .empty;
        defer c.declarations.deinit(allocator);
        return try genCode(allocator, ast, c);
    }
    const declarationsLength = ctx.?.declarations.items.len;
    defer ctx.?.declarations.shrinkRetainingCapacity(declarationsLength);
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
                for (node.children) |child| {
                    switch (child.nodeType) {
                        .scope => {
                            const scope = try genCode(allocator, &.{child}, ctx);
                            defer allocator.free(scope);
                            try code.appendSlice(allocator, scope);
                        },
                        .statement => {
                            if (child.tokens[0].is("return")) {
                                try code.appendSlice(allocator, "mov rax, ");
                                if (child.children[0].nodeType == .literal) {
                                    try code.appendSlice(allocator, child.children[0].tokens[0].lexeme.value);
                                } else {
                                    for (ctx.?.declarations.items, 0..) |decl, i| {
                                        if (decl.tokens[0].is(child.children[0].tokens[0].lexeme.value)) {
                                            try code.print(allocator, "[rbp - {d}]", .{(i + 1) * 8});
                                            break;
                                        }
                                    } else return error.UnexpectedIdentifier;
                                }
                                try code.appendSlice(allocator, "\n" ++ epilogue);
                            } else unreachable;
                        },
                        .declaration => {
                            if (child.children.len == 2) {
                                try ctx.?.declarations.append(allocator, child.children[0]);
                                try code.appendSlice(allocator, "push ");
                                try code.appendSlice(allocator, child.children[1].tokens[0].lexeme.value);
                                try code.appendSlice(allocator, "\n");
                            } else if (child.children.len == 1) {
                                try ctx.?.declarations.append(allocator, child.children[0]);
                                try code.appendSlice(allocator, "push 0\n");
                            } else unreachable;
                        },
                        else => unreachable,
                    }
                }
            },
            else => unreachable,
        }
    }
    return code.toOwnedSlice(allocator);
}
