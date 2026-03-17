int /* block
comment */ main(void) {
    char *s = "hello\nworld\t\"quoted\"";
    int x = 0xFF + 0777 + 42;
    float f = 3.14e-2;
    if (x == 0 || x != 1 && x <= 10 || x >= 3) {
        x++;
        x--;
        x += 1;
        x >>= 2;
        x <<= 1;
    }
    int *p = &x;
    p->next;
    return 0; // line comment
}
