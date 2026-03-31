# JCC
### Jacob's C Compiler
A C compiler that almost sort of works.
## Dependencies
Zig 0.16.0-dev.3059+42e33db9d, NASM, and ld
## Usage
```bash
jcc --help
jcc -o output.asm input.c
```

Only supports basic usage
```c
int main() {
    int x = 1;
    x = x * 2 + 3 - 4;
    if(x > 1) {
        return 0;
    } else {
        return 1;
    }
}
```
### Automatic
```bash
zig build run   # builds and runs test.c
```
### Manual
``` bash
zig build
./zig-out/bin/jcc -o a.asm test.c
nasm -felf64 -o a.o a.asm
ld -o a.out a.o
./a.out
```


