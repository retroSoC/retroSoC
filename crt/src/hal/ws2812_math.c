#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/ws2812.h>

#define RS_NANOSECONDS_PER_SECOND UINT64_C(1000000000)

static rs_status_t rs_ws2812_cycles_nearest(uint32_t frequency_hz, uint32_t duration_ns,
                                            uint32_t maximum, uint32_t *cycles) {
    uint64_t product;
    uint64_t rounded;

    if ((frequency_hz == 0U) || (duration_ns == 0U) || (cycles == NULL)) {
        return RS_EINVAL;
    }
    product = (uint64_t)frequency_hz * (uint64_t)duration_ns;
    if (product > (UINT64_MAX - (RS_NANOSECONDS_PER_SECOND / 2U))) {
        return RS_EINVAL;
    }
    rounded = (product + (RS_NANOSECONDS_PER_SECOND / 2U)) / RS_NANOSECONDS_PER_SECOND;
    if ((rounded == 0U) || (rounded > maximum)) {
        return RS_EINVAL;
    }
    *cycles = (uint32_t)rounded;
    return RS_OK;
}

static rs_status_t rs_ws2812_cycles_ceil(uint32_t frequency_hz, uint32_t duration_ns,
                                         uint32_t *cycles) {
    uint64_t product;
    uint64_t rounded;

    if ((frequency_hz == 0U) || (duration_ns == 0U) || (cycles == NULL)) {
        return RS_EINVAL;
    }
    product = (uint64_t)frequency_hz * (uint64_t)duration_ns;
    if (product > (UINT64_MAX - (RS_NANOSECONDS_PER_SECOND - 1U))) {
        return RS_EINVAL;
    }
    rounded = (product + (RS_NANOSECONDS_PER_SECOND - 1U)) / RS_NANOSECONDS_PER_SECOND;
    if ((rounded == 0U) || (rounded > UINT32_MAX)) {
        return RS_EINVAL;
    }
    *cycles = (uint32_t)rounded;
    return RS_OK;
}

uint32_t rs_ws2812_pack_grb(uint8_t red, uint8_t green, uint8_t blue) {
    return ((uint32_t)green << 16U) | ((uint32_t)red << 8U) | (uint32_t)blue;
}

rs_status_t rs_ws2812_timing_from_ns(const rs_ws2812_config_t *config, rs_ws2812_timing_t *timing) {
    uint32_t bit_cycles;
    uint32_t t0h_cycles;
    uint32_t t1h_cycles;
    uint32_t reset_cycles;

    if ((config == NULL) || (timing == NULL) ||
        (rs_ws2812_cycles_nearest(config->source_clock_hz, config->bit_period_ns, UINT16_MAX,
                                  &bit_cycles) != RS_OK) ||
        (rs_ws2812_cycles_nearest(config->source_clock_hz, config->t0h_ns, UINT16_MAX,
                                  &t0h_cycles) != RS_OK) ||
        (rs_ws2812_cycles_nearest(config->source_clock_hz, config->t1h_ns, UINT16_MAX,
                                  &t1h_cycles) != RS_OK) ||
        (rs_ws2812_cycles_ceil(config->source_clock_hz, config->reset_ns, &reset_cycles) !=
         RS_OK) ||
        (t0h_cycles >= t1h_cycles) || (t1h_cycles >= bit_cycles)) {
        return RS_EINVAL;
    }

    timing->bit_cycles = (uint16_t)bit_cycles;
    timing->t0h_cycles = (uint16_t)t0h_cycles;
    timing->t1h_cycles = (uint16_t)t1h_cycles;
    timing->reset_cycles = reset_cycles;
    return RS_OK;
}
