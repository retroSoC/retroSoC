#ifndef TINYLIB_H__
#define TINYLIB_H__

#include <tinyuart.h>
#include <tinystring.h>
#include <tinyprintf.h>
#include <tinyflash.h>
#include <firmware.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define putstr(s) \
  ({ for (const char *p = s; *p; p++) putch(*p); })

// assert.h
#define assert(cond)                                           \
  do                                                           \
  {                                                            \
    if (!(cond))                                               \
    {                                                          \
      printf("Assertion fail at %s:%d\n", __FILE__, __LINE__); \
      halt(1);                                                 \
    }                                                          \
  } while (0)

#ifdef __cplusplus
}
#endif

#endif
