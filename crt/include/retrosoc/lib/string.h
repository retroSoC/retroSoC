#ifndef RETROSOC_LIB_STRING_H
#define RETROSOC_LIB_STRING_H

#include <stddef.h>
#include <stdint.h>

void *memset(void *dst, int value, size_t count);
void *memcpy(void *dst, const void *src, size_t count);
void *memmove(void *dst, const void *src, size_t count);
int memcmp(const void *lhs, const void *rhs, size_t count);
size_t strlen(const char *str);
char *strcpy(char *dst, const char *src);
char *strncpy(char *dst, const char *src, size_t count);
char *strcat(char *dst, const char *src);
int strcmp(const char *lhs, const char *rhs);
int strncmp(const char *lhs, const char *rhs, size_t count);
char *strchr(const char *str, int value);

size_t rs_strlcpy(char *dst, const char *src, size_t dst_size);
size_t rs_strlcat(char *dst, const char *src, size_t dst_size);
void rs_trim_whitespace(char *str);
void rs_remove_suffix(char *dst, size_t dst_size, const char *src, char separator);

#endif
