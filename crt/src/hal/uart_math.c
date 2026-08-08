#include <limits.h>

#include <retrosoc/hal/uart.h>

rs_status_t rs_uart_timing_calculate(uint32_t source_clock_hz, uint32_t baud_rate,
                                     rs_uart_timing_t *timing) {
    uint64_t scaled_period;

    if ((source_clock_hz == 0U) || (baud_rate == 0U) || (timing == NULL)) {
        return RS_EINVAL;
    }

    scaled_period =
        (((uint64_t)source_clock_hz * UINT64_C(256)) + ((uint64_t)baud_rate / UINT64_C(2))) /
        (uint64_t)baud_rate;
    if ((scaled_period < UINT64_C(4096)) ||
        (scaled_period > ((UINT64_C(0xFFFFFF) * UINT64_C(256)) + UINT64_C(255)))) {
        return RS_EINVAL;
    }

    timing->baud_integer = (uint32_t)(scaled_period >> 8U);
    timing->baud_fraction = (uint32_t)(scaled_period & UINT64_C(0xFF));
    return RS_OK;
}
