#ifndef TINYPSRAM_H__
#define TINYPSRAM_H__

#include <stdint.h>

uint32_t xorshift32(uint32_t *state);
void ip_psram_selftest(uint32_t addr, uint32_t range);

#endif