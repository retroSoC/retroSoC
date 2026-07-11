#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/lib/console.h>

void putchar(char c) {
    if (c == '\n') {
        reg_uart0_data = '\r';
    }
    reg_uart0_data = c;
}

char getchar(void) {
    return reg_uart0_data;
}

void print(const char *p) {
    if (p == NULL) {
        return;
    }
    while (*p != '\0') {
        putchar(*p++);
    }
}
