#ifndef RETROSOC_LIB_STDLIB_H
#define RETROSOC_LIB_STDLIB_H

#include <stdint.h>

#include <retrosoc/core/status.h>

#ifndef RAND_MAX
#define RAND_MAX 32767
#endif

rs_status_t rs_strtoi32(const char *str, int32_t *value);
rs_status_t rs_utoa(uint32_t value, char *dst, uint32_t base);
int atoi(const char *str);
char *itoa(unsigned int value, char *dst, int base);
int abs(int value);
int rand(void);
void srand(unsigned int seed);

#endif
