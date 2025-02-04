
#ifndef TINYPRINT_H__
#define TINYPRINT_H__

#include <stdint.h>

void putchar(char c);
void print(const char *p);
void print_hex(uint32_t v, int digits);
void print_dec(uint32_t v);
void print_reg_bit(int val, const char *name);
void print_reg(char *info, uint32_t val, int digits);

#endif