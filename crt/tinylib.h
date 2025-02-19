#ifndef TINYLIB_H__
#define TINYLIB_H__

#include <firmware.h>
#include <tinyuart.h>
#include <tinystring.h>
#include <tinyprintf.h>
#include <tinyflash.h>
#include <tinygpio.h>
#include <tinyhkspi.h>
#include <tinytim.h>
#include <tinyarchinfo.h>
#include <tinyrng.h>
#include <tinyhpuart.h>
#include <tinypwm.h>
#include <tinyps2.h>
#include <tinyi2c.h>
#include <tinylcd.h>
#include <tinypsram.h>
#include <tinybench.h>
#include <tinysh.h>

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
