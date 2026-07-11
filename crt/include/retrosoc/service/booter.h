#ifndef RETROSOC_BOOTER_H
#define RETROSOC_BOOTER_H

#include <stdint.h>

extern uint32_t _flash_wait_start, _flash_wait_end;
extern uint32_t _ram_lma, _ram_vma;
extern uint32_t _ram_start, _stack_point;
extern uint32_t _start, _etext;
extern uint32_t _psram_lma, _psram_vma, _edata;
extern uint32_t _sbss, _ebss;
extern uint32_t _heap_start;

void rs_app_info(void);
void rs_booter(void);

#endif
