#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/timer.h>

#define RS_MILLISECONDS_PER_SECOND UINT64_C(1000)
#define RS_TIMER_MAX_DIVIDER       UINT64_C(65536)
#define RS_TIMER_COUNTER_VALUES    (UINT64_C(1) << 32U)

rs_status_t rs_timer_period_from_ms(uint32_t source_clock_hz, uint32_t milliseconds,
                                    rs_timer_period_t *period) {
    uint64_t product;
    uint64_t cycles;
    uint64_t divider;
    uint64_t ticks;

    if ((source_clock_hz == 0U) || (milliseconds == 0U) || (period == NULL)) {
        return RS_EINVAL;
    }
    product = (uint64_t)source_clock_hz * (uint64_t)milliseconds;
    if (product > (UINT64_MAX - (RS_MILLISECONDS_PER_SECOND - 1U))) {
        return RS_EINVAL;
    }
    cycles = (product + (RS_MILLISECONDS_PER_SECOND - 1U)) / RS_MILLISECONDS_PER_SECOND;
    divider = (cycles + (RS_TIMER_COUNTER_VALUES - 1U)) / RS_TIMER_COUNTER_VALUES;
    if (divider == 0U) {
        divider = 1U;
    }
    if (divider > RS_TIMER_MAX_DIVIDER) {
        return RS_EINVAL;
    }
    ticks = (cycles + (divider - 1U)) / divider;
    if ((ticks == 0U) || (ticks > RS_TIMER_COUNTER_VALUES)) {
        return RS_EINVAL;
    }
    period->prescale = (uint16_t)(divider - 1U);
    period->load = (uint32_t)(ticks - 1U);
    return RS_OK;
}
