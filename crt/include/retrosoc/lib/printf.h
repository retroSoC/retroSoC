#ifndef RETROSOC_LIB_PRINTF_H
#define RETROSOC_LIB_PRINTF_H

#include <stdarg.h>
#include <stddef.h>

int rs_printf(const char *format, ...);
int rs_vsnprintf(char *dst, size_t dst_size, const char *format, va_list args);
int rs_snprintf(char *dst, size_t dst_size, const char *format, ...);

/* Freestanding libc compatibility required by FatFs and CoreMark ports. */
int printf(const char *format, ...);
int vsnprintf(char *dst, size_t dst_size, const char *format, va_list args);
int snprintf(char *dst, size_t dst_size, const char *format, ...);

#endif
