#include <firmware.h>
#include <rs_print.h>

void putchar(char c) {
    if (c == '\n') putchar('\r');
    reg_uart0_data = c;
}

char getchar() {
    return reg_uart0_data;
}

void print(const char *p) {
    while (*p) putchar(*(p++));
}
