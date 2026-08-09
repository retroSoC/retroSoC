#include <stddef.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/console.h>

void putchar(char c) {
    if (c == '\n') {
        putch('\r');
    }
    putch(c);
}

char getchar(void) {
    rs_uart_rx_data_t data;

    while (rs_uart_read(&data, 1U, RS_TIMEOUT_DEFAULT) != RS_OK) {
    }
    return (char)data.data;
}

void print(const char *p) {
    if (p == NULL) {
        return;
    }
    while (*p != '\0') {
        putchar(*p++);
    }
}
