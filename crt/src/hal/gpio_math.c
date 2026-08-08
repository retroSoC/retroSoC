#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/gpio.h>

#define RS_GPIO_MICROSECONDS_PER_SECOND UINT64_C(1000000)
#define RS_GPIO_MAX_SAMPLE_CYCLES       UINT64_C(65536)

rs_status_t rs_gpio_filter_timing_from_us(uint32_t source_clock_hz, uint32_t sample_period_us,
                                          uint8_t stable_samples, rs_gpio_filter_timing_t *timing) {
    uint64_t product;
    uint64_t cycles;

    if ((source_clock_hz == 0U) || (sample_period_us == 0U) || (stable_samples == 0U) ||
        (stable_samples > 15U) || (timing == NULL)) {
        return RS_EINVAL;
    }
    product = (uint64_t)source_clock_hz * (uint64_t)sample_period_us;
    cycles = (product + RS_GPIO_MICROSECONDS_PER_SECOND - 1U) / RS_GPIO_MICROSECONDS_PER_SECOND;
    if ((cycles == 0U) || (cycles > RS_GPIO_MAX_SAMPLE_CYCLES)) {
        return RS_EINVAL;
    }
    timing->divider = (uint16_t)(cycles - 1U);
    timing->stable_samples = stable_samples;
    return RS_OK;
}
