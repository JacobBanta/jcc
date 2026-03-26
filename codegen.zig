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
    \\pop rbp
    \\ret
    \\
;
pub fn genCode(allocator: std.mem.Allocator, ast: []const ASTNode) ![]const u8 {
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
                    const scope = try genCode(allocator, ast[0].children);
                    defer allocator.free(scope);
                    try code.appendSlice(allocator, scope);
                } else unreachable;
            },
            .scope => {
                for (node.children) |child| {
                    switch (child.nodeType) {
                        .statement => {
                            if (child.tokens[0].is("return")) {
                                try code.appendSlice(allocator, "mov rax, ");
                                try code.appendSlice(allocator, child.children[0].tokens[0].lexeme.value);
                                try code.appendSlice(allocator, "\n" ++ epilogue);
                            } else unreachable;
                        },
                        .scope => {
                            const scope = try genCode(allocator, &.{child});
                            defer allocator.free(scope);
                            try code.appendSlice(allocator, scope);
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
