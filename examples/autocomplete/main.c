#include <stdio.h>

void function1() {
    printf("testing");
}

int function2(int a, int b) {
    return a + b;
}

int main() {
    int a, b, c;
    a = 0;
    printf("Hello, World!\n");
    b = 1;
    a = 2;
    function1();
    c = 2;
    a = 3;
    function2(1, 2);
    return 0;
}