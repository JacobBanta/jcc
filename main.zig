const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");
const clap = @import("clap");
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const help_text =
        \\-h, --help        Display this help and exit.
        \\-o, --out <FILE>  Output destination.
        \\-d, --debug       Enable debug outputs on stderr.
        \\<FILE>            Input file
        \\
    ;
    const params = comptime clap.parseParamsComptime(help_text);

    const parsers = comptime .{
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .assignment_separators = "=:",
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        std.debug.print(help_text, .{});
        return;
    }

    if (res.positionals[0] == null) {
        std.debug.print("No input file provided\n", .{});
        return;
    }
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(init.io, res.positionals[0].?, .{ .mode = .read_only });
    defer file.close(init.io);
    var reader = file.readerStreaming(init.io, &.{});
    const code = try reader.interface.readAlloc(allocator, (try file.stat(init.io)).size);
    defer allocator.free(code);
    const tokens = try tokenizer.lex(allocator, code);
    defer allocator.free(tokens);
    if (res.args.debug != 0) {
        std.debug.print("{s}\n", .{code});
        for (tokens) |t| {
            std.debug.print("{any}: {s}\n", .{ t.info, t.lexeme.value });
        }
    }
    const ast = try parser.parse(allocator, tokens);
    defer {
        for (ast) |*node| {
            node.deinit(allocator);
        }
        allocator.free(ast);
    }

    if (res.args.debug != 0) {
        for (ast) |node| {
            std.debug.print("{f}", .{node});
        }
    }
    const @"asm" = try codegen.genCode(allocator, ast, null);
    defer allocator.free(@"asm");
    const file_out = try cwd.createFile(init.io, res.args.out orelse "a.out.asm", .{});
    defer file_out.close(init.io);
    try file_out.writeStreamingAll(init.io, codegen._start);
    try file_out.writeStreamingAll(init.io, @"asm");
}

/// test only function
fn compileAndRun(source: []const u8) !u8 {
    // if verify is true, then use clang to run the tests
    const verify = false;
    if (!verify) {
        const allocator = std.testing.allocator;
        const tokens = try tokenizer.lex(allocator, source);
        defer allocator.free(tokens);
        const ast = try parser.parse(allocator, tokens);
        defer {
            for (ast) |*node| {
                node.deinit(allocator);
            }
            allocator.free(ast);
        }
        const @"asm" = try codegen.genCode(allocator, ast, null);
        defer allocator.free(@"asm");
        const asm_source = try std.mem.join(allocator, "", &.{ codegen._start, @"asm" });
        defer allocator.free(asm_source);

        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.asm", .data = asm_source });

        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const tmp_path_len = try tmp.dir.realPath(std.testing.io, &buf);
        const tmp_path = buf[0..tmp_path_len];
        const asm_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test.asm" });
        defer allocator.free(asm_path);
        const obj_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test.o" });
        defer allocator.free(obj_path);
        const exe_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test" });
        defer allocator.free(exe_path);
        var nasm_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{ "nasm", "-f", "elf64", "-o", obj_path, asm_path } });
        _ = try nasm_exe.wait(std.testing.io);
        var ld_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{ "ld", "-o", exe_path, obj_path } });
        _ = try ld_exe.wait(std.testing.io);
        var exe_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{exe_path} });
        const result = try exe_exe.wait(std.testing.io);
        return result.exited;
    } else {
        const allocator = std.testing.allocator;
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.c", .data = source });

        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const tmp_path_len = try tmp.dir.realPath(std.testing.io, &buf);
        const tmp_path = buf[0..tmp_path_len];
        const src_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test.c" });
        defer allocator.free(src_path);
        const exe_path = try std.Io.Dir.path.join(allocator, &.{ tmp_path, "test" });
        defer allocator.free(exe_path);
        var nasm_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{ "clang", "-o", exe_path, src_path } });
        _ = try nasm_exe.wait(std.testing.io);
        var exe_exe = try std.process.spawn(std.testing.io, .{ .argv = &.{exe_path} });
        const result = try exe_exe.wait(std.testing.io);
        return result.exited;
    }
}

test "return" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 42;}"));
}

test "implicit return from main" {
    try std.testing.expectEqual(0, try compileAndRun("int main(){}"));
}

test "declare variable" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 42; return x;}"));
}

test "assign variable" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x; x = 42; return x;}"));
}

test "reassign variable" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 1; x = 42; return x;}"));
}

test "assign variable from variable" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 42; int y = x; return y;}"));
}

test "add" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 40; x += 2; return x;}"));
}

test "sub" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 50; x -= 8; return x;}"));
}

test "mul" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 7; x *= 6; return x;}"));
}

test "direct expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 40 + 2; return x;}"));
}

test "add negative" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 50; x += -8; return x;}"));
}

test "return expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 40 + 2;}"));
}

test "return add negative" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 43 + -1;}"));
}

test "return long expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 40 + 1 + 1;}"));
}

test "sub expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 50 - 8;}"));
}

test "mul expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 7 * 6;}"));
}

test "arithmetic with variables" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 7; int y = 6; x *= y; return x;}"));
}

test "return expression with variables" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 7; int y = 6; return x * y;}"));
}

test "complex subtraction" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 44 - 1 - 1;}"));
}

test "operator precedence mul before add" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 2 + 5 * 8;}"));
}

test "operator precedence mul before sub" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 50 - 2 * 4;}"));
}

test "operator precedence multiple terms" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 2 * 11 + 4 * 5;}"));
}

test "parentheses override precedence" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return (4 + 3) * 6;}"));
}

test "parentheses left side" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 6 * (3 + 4);}"));
}

test "nested parentheses" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return (2 + (4 * 5)) * 2 - 2;}"));
}

test "complex expression with variables and precedence" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 4; int y = 5; return 2 + x * y + 20;}"));
}

test "parentheses with variables" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 4; int y = 8; return ((x + y) * (y - 2) - 30);}"));
}

test "division" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 84 / 2;}"));
}

test "integer division truncates" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 85 / 2;}"));
}

test "division in expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 10 + 64 / 2;}"));
}

test "modulo" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 128 % 86;}"));
}

test "modulo in expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 100 % 58 + 0 * 3;}"));
}

test "complex expression with all operators" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){return 4 + 8 * 6 - 20 / 2;}"));
}

test "basic if" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1){return 42;} return 1;}"));
}

test "if one line" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1) return 42;}"));
}

test "basic else" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0){return 1;}else{return 42;}}"));
}

test "if expr" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0 + 1 * 0 + 7){return 42;}}"));
}

test "if eq" {
    try std.testing.expectEqual(42, try compileAndRun("int main() {if(0 == 0) {return 42;}}"));
}

test "if ne" {
    try std.testing.expectEqual(42, try compileAndRun("int main() {if(0 != 1) {return 42;}}"));
}

test "if gt" {
    try std.testing.expectEqual(42, try compileAndRun("int main() {if(2 > 1) {return 42;}}"));
}

test "if lt" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1 < 2){return 42;}return 1;}"));
}

test "if le equal" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1 <= 1){return 42;}return 1;}"));
}

test "if le less" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0 <= 1){return 42;}return 1;}"));
}

test "if ge equal" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(2 >= 2){return 42;}return 1;}"));
}

test "if ge greater" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(3 >= 2){return 42;}return 1;}"));
}

test "if variable condition" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 7; if(x){return 42;}return 1;}"));
}

test "if zero variable condition" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; if(x){return 1;}return 42;}"));
}

test "else if chain" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 2; if(x == 1){return 1;}else if(x == 2){return 42;}else{return 3;}}"));
}

test "comparison stored in variable" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int a = 5; int b = 3; int c = a > b; if(c){return 42;}return 1;}"));
}

test "logical and true" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1 && 1){return 42;}return 1;}"));
}

test "logical and false" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0 && 1){return 1;}return 42;}"));
}

test "logical or true" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0 || 1){return 42;}return 1;}"));
}

test "logical or false" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(0 || 0){return 1;}return 42;}"));
}

test "logical not false" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(!0){return 42;}return 1;}"));
}

test "logical not true" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(!1){return 1;}return 42;}"));
}

test "compound logical" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int a = 5; int b = 8; if(a > 1 && b < 10){return 42;}return 1;}"));
}

test "while basic" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; while(x < 42){x += 1;}return x;}"));
}

test "while never executes" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 42; while(0){x = 1;}return x;}"));
}

test "while break" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; while(1){if(x == 42){break;}x += 1;}return x;}"));
}

test "while continue" {
    try std.testing.expectEqual(25, try compileAndRun("int main(){int x = 0; int sum = 0; while(x < 10){x += 1; if(x % 2 == 0){continue;}sum += x;}return sum;}"));
}

test "for basic" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int s = 0; for(int i = 0; i < 7; i++){s += 6;}return s;}"));
}

test "for break" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int s = 0; for(int i = 0; i < 100; i++){s += 1; if(s == 42){break;}}return s;}"));
}

test "for continue" {
    try std.testing.expectEqual(25, try compileAndRun("int main(){int s = 0; for(int i = 1; i <= 10; i++){if(i % 2 == 0){continue;}s += i;}return s;}"));
}

test "do while basic" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; do{x += 6;}while(x < 42);return x;}"));
}

test "do while executes at least once" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 42; do{x = 42;}while(0);return x;}"));
}

test "nested loops" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int s = 0; for(int i = 0; i < 6; i++){for(int j = 0; j < 7; j++){s += 1;}}return s;}"));
}

test "prefix increment statement" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 41; ++x; return x;}"));
}

test "postfix increment statement" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 41; x++; return x;}"));
}

test "prefix decrement statement" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 43; --x; return x;}"));
}

test "postfix decrement statement" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 43; x--; return x;}"));
}

test "prefix increment expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 41; int y = ++x; return y;}"));
}

test "postfix increment expression returns old value" {
    try std.testing.expectEqual(41, try compileAndRun("int main(){int x = 41; int y = x++; return y;}"));
}

test "postfix increment expression mutates" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 41; int y = x++; return x;}"));
}

test "prefix decrement expression" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 43; int y = --x; return y;}"));
}

test "postfix decrement expression returns old value" {
    try std.testing.expectEqual(43, try compileAndRun("int main(){int x = 43; int y = x--; return y;}"));
}

test "postfix decrement expression mutates" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 43; int y = x--; return x;}"));
}

test "increment in loop condition" {
    try std.testing.expectEqual(43, try compileAndRun("int main(){int x = 0; while(x++ < 42){}return x;}"));
}

test "variable shadow in nested block" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 1; {int x = 42; return x;}return x;}"));
}

test "outer variable unchanged after inner shadow" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 42; {int x = 1;}return x;}"));
}

test "variable declared inside if" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1){int x = 42; return x;}return 1;}"));
}

test "subtraction is left associative" {
    try std.testing.expectEqual(5, try compileAndRun("int main(){return 10 - 3 - 2;}"));
}

test "division is left associative" {
    try std.testing.expectEqual(3, try compileAndRun("int main(){return 24 / 4 / 2;}"));
}

test "modulo precedence over addition" {
    try std.testing.expectEqual(3, try compileAndRun("int main(){return 2 + 10 % 3;}"));
}

test "if else without braces" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; if(x == 0) return 42; else return 1;}"));
}

test "for loop condition is evaluated" {
    try std.testing.expectEqual(3, try compileAndRun("int main(){int s = 0; for(int i = 0; i < 3; i++) s += 1; return s;}"));
}

test "ne with expression rhs" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){if(1 != 0 + 0){return 42;}return 1;}"));
}

test "binary op after unary minus" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int a = 1; int b = 2; int c = 43; return a + -b + c;}"));
}

test "else if chain with expression bodies" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 3; if(x == 1) return 1; else if(x == 2) return 2; else if(x == 3) return 42; else return 4;}"));
}

test "else if braces-free chain" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 3; if(x == 1) return 1; else if(x == 2) return 2; else if(x == 3) return 42; else return 4;}"));
}

test "else if falls through to else" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 5; if(x == 1) return 1; else if(x == 2) return 2; else return 42;}"));
}

test "while without braces" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; while(x < 42) x += 1; return x;}"));
}

test "do while without braces" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 0; do x += 6; while(x < 42); return x;}"));
}

test "nested if else chains" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int x = 1; int y = 2; if(x == 1){if(y == 1) return 1; else if(y == 2) return 42; else return 3;} return 4;}"));
}

test "for without braces" {
    try std.testing.expectEqual(42, try compileAndRun("int main(){int s = 0; for(int i = 0; i < 7; i++) s += 6; return s;}"));
}

test "function call no args" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(){return 42;} int main(){return foo();}"));
}

test "function call with one arg" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int x){return x;} int main(){return foo(42);}"));
}

test "function call with multiple args" {
    try std.testing.expectEqual(42, try compileAndRun("int add(int a, int b){return a + b;} int main(){return add(40, 2);}"));
}

test "function call with expression arg" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int x){return x;} int main(){return foo(40 + 2);}"));
}

test "function call return value in expression" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(){return 21;} int main(){return foo() + foo();}"));
}

test "function call as argument" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int x){return x;} int main(){return foo(foo(42));}"));
}

test "recursive function" {
    try std.testing.expectEqual(42, try compileAndRun("int countdown(int x){if(x == 0) return 0; return countdown(x - 1) + 1;} int main(){return countdown(42);}"));
}

test "fibonacci" {
    try std.testing.expectEqual(55, try compileAndRun("int fib(int n){if(n <= 1) return n; return fib(n - 1) + fib(n - 2);} int main(){return fib(10);}"));
}

test "mutual recursion" {
    try std.testing.expectEqual(1, try compileAndRun("int is_odd(int n); int is_even(int n){if(n == 0) return 1; return is_odd(n - 1);} int is_odd(int n){if(n == 0) return 0; return is_even(n - 1);} int main(){return is_even(42);}"));
}

test "six args uses all registers" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int a, int b, int c, int d, int e, int f){return a + b + c + d + e + f;} int main(){return foo(2, 4, 6, 8, 10, 12);}"));
}

test "seven args spills to stack" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int a, int b, int c, int d, int e, int f, int g){return a + b + c + d + e + f + g;} int main(){return foo(1, 2, 3, 4, 5, 6, 21);}"));
}

test "callee saved registers preserved" {
    try std.testing.expectEqual(42, try compileAndRun("int bar(){return 1;} int main(){int x = 42; bar(); return x;}"));
}

test "function call in multiplication" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(){return 7;} int main(){return foo() * 6;}"));
}

test "nested function calls" {
    try std.testing.expectEqual(42, try compileAndRun("int bar(){return 40;} int foo(){return bar() + 2;} int main(){return foo();}"));
}

test "function call as argument to another function" {
    try std.testing.expectEqual(42, try compileAndRun("int add(int a, int b){return a + b;} int get_val(){return 21;} int main(){return add(get_val(), get_val());}"));
}

test "function call with arithmetic expression argument" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(int x){return x;} int main(){return foo(20 + 22);}"));
}

test "multiple function calls in complex expression" {
    try std.testing.expectEqual(42, try compileAndRun("int double_it(int x){return x * 2;} int add_five(int x){return x + 5;} int main(){return double_it(add_five(16));}"));
}

test "function call in assignment expression" {
    try std.testing.expectEqual(42, try compileAndRun("int foo(){return 42;} int main(){int x = foo(); return x;}"));
}

test "function call with function call as parameter" {
    try std.testing.expectEqual(30, try compileAndRun("int triple(int x){return x * 3;} int square(int x){return x * x;} int main(){return triple(square(3)) + triple(square(1));}"));
}

test "function call in bitwise expression" {
    try std.testing.expectEqual(42, try compileAndRun("int get_bits(){return 0b101010;} int main(){return get_bits() | 0b001010;}"));
}

test "bitwise OR with function calls" {
    try std.testing.expectEqual(0b1101, try compileAndRun("int get_a(){return 0b1001;} int get_b(){return 0b0101;} int main(){return get_a() | get_b();}"));
}

test "bitwise AND with function calls" {
    try std.testing.expectEqual(0b0001, try compileAndRun("int get_a(){return 0b1001;} int get_b(){return 0b0101;} int main(){return get_a() & get_b();}"));
}

test "bitwise XOR with function calls" {
    try std.testing.expectEqual(0b1100, try compileAndRun("int get_a(){return 0b1001;} int get_b(){return 0b0101;} int main(){return get_a() ^ get_b();}"));
}

test "left shift with function call" {
    try std.testing.expectEqual(32, try compileAndRun("int get_value(){return 8;} int main(){return get_value() << 2;}"));
}

test "right shift with function call" {
    try std.testing.expectEqual(2, try compileAndRun("int get_value(){return 8;} int main(){return get_value() >> 2;}"));
}

test "complex bitwise expression with multiple function calls" {
    try std.testing.expectEqual(0b1110, try compileAndRun("int get_a(){return 0b1010;} int get_b(){return 0b1100;} int get_mask(){return 0b0110;} int main(){return (get_a() & get_mask()) | get_b();}"));
}

test "bitwise operations with function call arguments" {
    try std.testing.expectEqual(14, try compileAndRun("int combine(int x, int y){return (x | y) & 0b1111;} int main(){return combine(0b1010, 0b0110);}"));
}

test "multiple shifts with function calls" {
    try std.testing.expectEqual(54, try compileAndRun("int get_val(){return 12;} int main(){return (get_val() << 2) | (get_val() >> 1);}"));
}

test "bitwise operations in assignment with function call" {
    try std.testing.expectEqual(10, try compileAndRun("int get_mask(){return 0b1110;} int main(){int flags = 0b1010; flags &= get_mask(); return flags;}"));
}
