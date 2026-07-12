#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/arch/riscv/system_csr.h>
#include <retrosoc/arch/riscv/system_timer.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/lib/printf.h>

#define RS_TIMER_DELTA_VALUE 360000UL
#define RS_IRQ_TEST_TIMEOUT_MS 6000U

static volatile uint32_t timer_irq_count;
static volatile uint32_t software_irq_count;
static volatile uint32_t software_irq_ready = 1U;

static void rs_timer_irq_handler(uintptr_t mcause, uintptr_t stack_pointer) {
    uint64_t now;

    (void)mcause;
    (void)stack_pointer;
    ++timer_irq_count;
    now = SysTimer_GetMtimeValue();
    SysTimer_SetMtimecmpValue(now + RS_TIMER_DELTA_VALUE);
}

static void rs_software_irq_handler(uintptr_t mcause, uintptr_t stack_pointer) {
    (void)mcause;
    (void)stack_pointer;
    SysTimer_ClearSoftwareIRQ();
    ++software_irq_count;
    software_irq_ready = 1U;
}

static rs_status_t rs_irq_wait_for_count(volatile uint32_t *counter, uint32_t target) {
    for (uint32_t elapsed = 0U; elapsed < RS_IRQ_TEST_TIMEOUT_MS; ++elapsed) {
        if (*counter >= target) {
            return RS_OK;
        }
        delay_ms(1U);
    }
    return RS_ETIMEOUT;
}

void irq_test(int argc, char **argv) {
    uint64_t now;

    (void)argc;
    (void)argv;
    timer_irq_count = 0U;
    software_irq_count = 0U;
    software_irq_ready = 1U;

    if (rs_irq_enable_core(IRQ_M_TIMER, rs_timer_irq_handler) != RS_OK) {
        printf("unable to register timer irq\n");
        return;
    }
    __enable_irq();
    now = SysTimer_GetMtimeValue();
    SysTimer_SetMtimecmpValue(now + RS_TIMER_DELTA_VALUE);

    if (rs_irq_wait_for_count(&timer_irq_count, 6U) != RS_OK) {
        printf("timer irq timed out\n");
        __disable_core_irq(IRQ_M_TIMER);
        return;
    }
    __disable_core_irq(IRQ_M_TIMER);

    if (rs_irq_enable_core(IRQ_M_SOFT, rs_software_irq_handler) != RS_OK) {
        printf("unable to register software irq\n");
        return;
    }
    for (uint32_t attempt = 0U; attempt < 6U; ++attempt) {
        if (software_irq_ready == 0U) {
            printf("software irq did not clear\n");
            return;
        }
        software_irq_ready = 0U;
        SysTimer_SetSoftwareIRQ();
        if (rs_irq_wait_for_count(&software_irq_count, attempt + 1U) != RS_OK) {
            printf("software irq timed out\n");
            return;
        }
    }
    __disable_core_irq(IRQ_M_SOFT);
    printf("timer and software irq tests passed\n");
}
