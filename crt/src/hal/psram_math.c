#include <stddef.h>

#include <retrosoc/hal/psram.h>

#define RS_NANOSECONDS_PER_SECOND UINT64_C(1000000000)

static bool rs_psram_ceil_cycles(uint32_t frequency_hz, uint32_t nanoseconds, uint32_t *cycles) {
    uint64_t numerator;
    uint64_t result;

    numerator = ((uint64_t)frequency_hz * (uint64_t)nanoseconds) +
                (RS_NANOSECONDS_PER_SECOND - UINT64_C(1));
    result = numerator / RS_NANOSECONDS_PER_SECOND;
    if (result > UINT32_MAX) {
        return false;
    }
    *cycles = (uint32_t)result;
    return true;
}

rs_status_t rs_psram_timing_from_hz(uint32_t source_clock_hz, uint32_t sclk_hz,
                                    rs_psram_timing_t *timing) {
    uint64_t divider;
    uint64_t actual_hz;
    uint64_t period_ns;
    uint32_t setup_cycles;
    uint32_t high_cycles;
    uint32_t hold_cycles;
    uint32_t output_hold_cycles;
    uint64_t max_low_cycles;

    if ((source_clock_hz == 0U) || (sclk_hz == 0U) || (timing == NULL) ||
        (sclk_hz > RS_PSRAM_MAX_SCLK_HZ)) {
        return RS_EINVAL;
    }

    divider = ((uint64_t)source_clock_hz + ((uint64_t)sclk_hz * UINT64_C(2)) - UINT64_C(1)) /
              ((uint64_t)sclk_hz * UINT64_C(2));
    if ((divider == 0U) || (divider > UINT16_MAX)) {
        return RS_EINVAL;
    }
    actual_hz = (uint64_t)source_clock_hz / (divider * UINT64_C(2));
    if ((actual_hz == 0U) || (actual_hz > RS_PSRAM_MAX_SCLK_HZ)) {
        return RS_EINVAL;
    }

    period_ns = (RS_NANOSECONDS_PER_SECOND + actual_hz - UINT64_C(1)) / actual_hz;
    if (!rs_psram_ceil_cycles(source_clock_hz, 3U, &setup_cycles) ||
        !rs_psram_ceil_cycles(source_clock_hz, 50U, &high_cycles) ||
        !rs_psram_ceil_cycles(source_clock_hz, 20U, &hold_cycles) ||
        !rs_psram_ceil_cycles(source_clock_hz, (uint32_t)(period_ns + UINT64_C(6)),
                              &output_hold_cycles) ||
        !rs_psram_ceil_cycles(source_clock_hz, 150000U, &timing->powerup_cycles) ||
        (setup_cycles > UINT16_MAX) || (high_cycles > UINT16_MAX) || (hold_cycles > UINT16_MAX) ||
        (output_hold_cycles > UINT16_MAX)) {
        return RS_EINVAL;
    }
    if (output_hold_cycles > hold_cycles) {
        hold_cycles = output_hold_cycles;
    }

    max_low_cycles = ((uint64_t)source_clock_hz * UINT64_C(8000)) / RS_NANOSECONDS_PER_SECOND;
    if ((max_low_cycles == 0U) || (max_low_cycles > UINT32_MAX)) {
        return RS_EINVAL;
    }

    timing->half_period_cycles = (uint16_t)divider;
    timing->cs_setup_cycles = (uint16_t)setup_cycles;
    timing->cs_high_cycles = (uint16_t)high_cycles;
    timing->cs_hold_cycles = (uint16_t)hold_cycles;
    timing->cs_max_low_cycles = (uint32_t)max_low_cycles;
    timing->access_timeout_cycles = source_clock_hz / 100U;
    if (timing->access_timeout_cycles <= timing->cs_max_low_cycles) {
        timing->access_timeout_cycles = timing->cs_max_low_cycles + 1U;
    }
    timing->actual_sclk_hz = (uint32_t)actual_hz;
    timing->above_84mhz = actual_hz > RS_PSRAM_PAGE_CROSS_MAX_HZ;
    return RS_OK;
}
