
#ifndef RETROSOC_UART_H
#define RETROSOC_UART_H

#include <stdint.h>

void uart0_init(uint32_t freq, uint32_t bps);
void putch(char ch);
#endif
