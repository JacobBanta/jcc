# JCC
### Jacob's C Compiler
A C compiler that almost sort of works.
## Dependencies
Zig 0.16.0-dev.2905+5d71e3051, NASM, and ld
## Usage
Only compiles `test.c`

Only supports basic usage
```c
int main() {
    int x = 1;
    x = 0;
    return x;
}
```
### Automatic
```bash
zig build run              # builds and runs test.c
```
### Manual
``` bash
zig build                  # builds the compiler
./zig-out/bin/jcc > a.asm  # builds test.c
nasm -felf64 -o a.o a.asm
ld -o a.out a.o
./a.out                    # runs test.c
```


