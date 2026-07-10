#ifndef LIBDEF_H__
#define LIBDEF_H__

#include <stddef.h>
#include <stdint.h>
#include <firmware.h>
#include <socver.h>
#include <rs_booter.h>
#include <rs_uart.h>
#include <rs_string.h>
#include <rs_printf.h>
#include <rs_gpio.h>
#include <rs_tim.h>
#include <rs_archinfo.h>
#include <rs_rng.h>
#include <rs_hpuart.h>
#include <rs_pwm.h>
#include <rs_ps2.h>
#include <rs_i2c.h>
#include <rs_1wire.h>
#include <rs_dma.h>
#include <rs_lcd.h>
#include <rs_psram.h>
#include <rs_spisd.h>
#include <rs_qspi.h>
#include <rs_i2s.h>
#include <rs_rtc.h>
#include <rs_wdg.h>
#include <rs_crc.h>
#include <rs_advtim.h>
#include <rs_bench.h>
#include <rs_sh.h>
#include <at24cxx.h>
#include <pcf8563b.h>
#include <es8388.h>
#include <w25q128jvxim.h>
#include <wav_audio.h>
#include <video_player.h>
#include <donut.h>

#ifdef CSR_ENABLE
#include <rs_irq.h>
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
