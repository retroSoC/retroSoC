#ifndef TINYLIB_H__
#define TINYLIB_H__

#include <stddef.h>
#include <stdint.h>
#include <firmware.h>
#include <tinyver.h>
#include <tinybooter.h>
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
#include <tiny1wire.h>
#include <tinydma.h>
#include <tinylcd.h>
#include <tinypsram.h>
#include <tinyspisd.h>
#include <tinyi2s.h>
#include <tinyrtc.h>
#include <tinywdg.h>
#include <tinycrc.h>
#include <tinyadvtim.h>
#include <tinybench.h>
#include <tinysh.h>
#include <at24cxx.h>
#include <pcf8563b.h>
#include <es8388.h>
#include <wav_decoder.h>

#ifdef __cplusplus
extern "C"
{
#endif

void *malloc(size_t size);
void free(void *ptr);

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
