#ifndef TINYLIB_H__
#define TINYLIB_H__

#include <firmware.h>
#include <tinyver.h>
#include <tinyuart.h>
#include <tinystring.h>
#include <tinyprintf.h>
#include <tinygpio.h>
#include <tinytim.h>
#include <tinyarchinfo.h>
#include <tinyrng.h>
#include <tinyhpuart.h>
#include <tinypwm.h>
#include <tinyps2.h>
#include <tinyi2c.h>
#include <tinylcd.h>
#include <tinypsram.h>
#include <tinyspisd.h>
#include <tinybench.h>
#include <tinysh.h>
#include <AT24C64.h>
#include <PCF8563B.h>
#include <ES8388.h>

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
