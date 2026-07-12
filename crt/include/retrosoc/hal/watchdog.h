#ifndef RETROSOC_WDG_H
#define RETROSOC_WDG_H

#include <stdint.h>

#define WDG_MAGIC_NUM (uint32_t)0x5F3759DF

void ip_wdg_test(int argc, char **argv);
#endif
