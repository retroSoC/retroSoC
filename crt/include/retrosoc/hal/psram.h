#ifndef RETROSOC_PSRAM_H
#define RETROSOC_PSRAM_H

#include <stdint.h>

void ip_psram_boot(void);
uint32_t xorshift32(uint32_t *state);
void ip_psram_selftest(uint32_t addr, uint32_t range);
#endif
