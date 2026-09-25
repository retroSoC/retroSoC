#ifndef RETROSOC_MCU_ACCEPTANCE_H
#define RETROSOC_MCU_ACCEPTANCE_H

#include <stdint.h>

uint32_t rs_mcu_compressed_probe(void);
void rs_mcu_atomic_probe(uint32_t *address);
void rs_mcu_unmapped_probe(void);

#endif
