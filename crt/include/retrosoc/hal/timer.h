#ifndef RETROSOC_TIM_H
#define RETROSOC_TIM_H

#include <stdint.h>

void delay_ms(uint32_t val);
void tim1_init(void);
uint32_t tim1_get_value(void);
void ip_tim_test(int argc, char **argv);
#endif
