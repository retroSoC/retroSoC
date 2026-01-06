#include <system_csr.h>
#include <system_timer.h>
#include <system_base.h>
#include <tinyprintf.h>
#include <tinytim.h>

#define TIMER_DELTA_VALUE 360000UL
/* Define the interrupt handler name same as vector table in case download mode is flashxip. */
// #define mtimer_irq_handler     core_mtip_handler
// #define mtimer_sw_irq_handler  core_msip_handler

static volatile uint32_t int0_cnt = 0;    /* msip timer interrupt test counter */
static volatile uint32_t int1_cnt = 0;    /* mtip timer interrupt test counter */
volatile unsigned int msip_trig_flag = 1; /* sw trigger mtimer sw interrupt flag */

void mtimer_irq_handler(void) {
    printf("MTimer IRQ handler %d\n\r", int0_cnt++);
    // printf("mtimecmp: %x_%x\n", reg_clint_mtimecmph, reg_clint_mtimecmpl);
    // printf("mtime: %x_%x\n", reg_clint_mtimeh, reg_clint_mtimel);
    uint64_t now = SysTimer_GetMtimeValue();
    SysTimer_SetMtimecmpValue(now + TIMER_DELTA_VALUE);
    delay_ms(1);
}

void mtimer_sw_irq_handler(void) {
    SysTimer_ClearSoftwareIRQ();
    int1_cnt++;
    printf("MTimer SW IRQ handler %d\n\r", int1_cnt);
    msip_trig_flag = 1;
}

void setup_timer() {
    printf("init timer and start\n\r");
    // for(int i = 0; i < 6; ++i) {
        // printf("clkdiv: %x msip: %x mtimecmp: %x_%x\n", reg_clint_clkdiv, reg_clint_msip, reg_clint_mtimecmph, reg_clint_mtimecmpl);
        // printf("mtime: %x_%x\n", reg_clint_mtimeh, reg_clint_mtimel);
        // printf("clkdiv: %x msip: %x mtimecmp: %lx\n", reg_clint_clkdiv, reg_clint_msip, reg_clint_mtimecmpl);
        // printf("mtime: %lx\n", reg_clint_mtimel);
    // }
    uint64_t now = SysTimer_GetMtimeValue();
    uint64_t then = now + TIMER_DELTA_VALUE;
    
    SysTimer_SetMtimecmpValue(then);
}

extern int32_t register_system_core_irq_factory(uint32_t id, void *handler);

void irq_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    register_system_core_irq_factory(IRQ_M_TIMER, mtimer_irq_handler);
    __enable_irq();
    setup_timer();

    while (int0_cnt < 6);
    __disable_core_irq(IRQ_M_TIMER);
    register_system_core_irq_factory(IRQ_M_SOFT, mtimer_sw_irq_handler);

    do {
        if (msip_trig_flag == 1) {
            msip_trig_flag = 0;
            SysTimer_SetSoftwareIRQ();
            delay_ms(1);
        }
    } while (int1_cnt < 6);

    printf("MTimer msip and mtip interrupt test finish and pass\r\n");
}