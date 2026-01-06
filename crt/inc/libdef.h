#ifndef LIBDEF_H__
#define LIBDEF_H__

#include <stddef.h>
#include <stdint.h>
#include <firmware.h>
#include <socver.h>
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
#include <tinyqspi.h>
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
#include <w25q128jvxim.h>
#include <wav_audio.h>
#include <video_player.h>
#include <donut.h>

#ifdef CSR_ENABLE
#include <tinyirq.h>
#endif

#ifdef __cplusplus
extern "C"
{
#endif

// uint32_t system_runtime() {
//     uint32_t sys_cycle_val, sys_cycle_valh;
//     __asm__ volatile("rdcycle %0"    : "=r"(sys_cycle_val));
//     __asm__ volatile("rdcycleh %0"   : "=r"(sys_cycle_valh));

//     if(sys_cycle_valh == 0) return sys_cycle_val * CPU_FREQ / 1000;
//     else return (sys_cycle_val) * CPU_FREQ / 1000; // unit: ms
// }

uint32_t *irq_handler(uint32_t *regs, uint32_t irqs);

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
