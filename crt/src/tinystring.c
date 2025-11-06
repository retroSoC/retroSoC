#include <tinystring.h>

size_t strlen(const char *s)
{
  const char *p = s;
  while (*p)
  {
    p++;
  }

  return p - s;
}

char *strcpy(char *dst, const char *src)
{
  char *d = dst;
  while ((*d++ = *src++))
  {
  }

  return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
  char *d = dst;
  while ((n--) > 0 && (*d++ = *src++))
  {
  }
  while ((n--) > 0)
  {
    *d++ = 0;
  }

  return dst;
}

char *strcat(char *dst, const char *src)
{
  char *d = dst;

  while (*d++)
  {
  }
  d--;
  while ((*d++ = *src++))
  {
  }

  return dst;
}

int strcmp(const char *s1, const char *s2)
{
  // unsigned char type is very important
  unsigned char c1, c2;

  do
  {
    c1 = *s1++;
    c2 = *s2++;
  } while (c1 != 0 && c1 == c2);

  return c1 - c2;
}

int strncmp(const char *s1, const char *s2, size_t n)
{
  unsigned char c1, c2;

  do
  {
    c1 = *s1++;
    c2 = *s2++;
  } while ((n--) > 0 && c1 != 0 && c1 == c2);

  if (!n)
    return 0;
  return c1 - c2;
}

void *memset(void *dst, int c, size_t n)
{
  char *cdst = (char *)dst;

  for (uint32_t i = 0; i < n; i++)
  {
    cdst[i] = c;
  }

  return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
  const char *s = src;
  char *d = dst;

  if (s < d && s + n > d)
  {
    s += n;
    d += n;
    while (n-- > 0)
    {
      *--d = *--s;
    }
  }
  else
  {
    while (n-- > 0)
    {
      *d++ = *s++;
    }
  }

  return dst;
}

void *memcpy(void *out, const void *in, size_t n)
{
  return memmove(out, in, n);
}

int memcmp(const void *s1, const void *s2, size_t n)
{
  const unsigned char *v1 = s1;
  const unsigned char *v2 = s2;

  while ((n--) > 0)
  {
    if (*v1 != *v2)
    {
      return *v1 - *v2;
    }
    v1++, v2++;
  }

  return 0;
}

char *strchr(const char *s, int c) {
    const char ch = (char)c;

    do {
        if (*s == ch) return (char *)s;
    } while (*s++ != '\0');

    return 0;
}


void trim_whitespace(char *str) {
    char *start = str;
    while (*start && *start == ' ') start++;
    
    if (*start == '\0') {
        *str = '\0';
        return;
    }
    
    char *end = start + strlen(start) - 1;
    while (end > start && (*end == ' ' || *end == '\n' || *end == '\r')) {
        *end = '\0';
        end--;
    }
    
    if (start != str) {
        memmove(str, start, (end - start) + 2);
    }
}

void remove_suffix(char *dst, char *src, char sign) {
    // "a/asdf/bb/asdfa"
    uint8_t idx = 0;
    for(uint8_t i = strlen(src) - 1; i >= 1; --i) {
      if(src[i] == sign) {
        idx = i; break;
      }
    }

    for(uint8_t i = 0; i < idx; ++i) dst[i] = src[i];

    dst[idx] = 0;
}