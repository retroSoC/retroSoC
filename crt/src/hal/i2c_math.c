#include <limits.h>

#include <retrosoc/hal/i2c.h>

typedef struct {
    uint32_t maximum_hz;
    uint32_t low_ns;
    uint32_t high_ns;
    uint32_t start_hold_ns;
    uint32_t start_setup_ns;
    uint32_t data_setup_ns;
    uint32_t stop_setup_ns;
    uint32_t bus_free_ns;
} rs_i2c_mode_t;

static uint64_t rs_i2c_divide_ceil(uint64_t dividend, uint64_t divisor) {
    return (dividend + divisor - UINT64_C(1)) / divisor;
}

static uint64_t rs_i2c_cycles_from_ns(uint32_t source_clock_hz, uint32_t period_ns) {
    return rs_i2c_divide_ceil((uint64_t)source_clock_hz * (uint64_t)period_ns,
                              UINT64_C(1000000000));
}

static rs_i2c_mode_t rs_i2c_mode_for_rate(uint32_t bus_hz) {
    rs_i2c_mode_t mode;

    if (bus_hz <= UINT32_C(100000)) {
        mode = (rs_i2c_mode_t){UINT32_C(100000), UINT32_C(4700), UINT32_C(4000), UINT32_C(4000),
                               UINT32_C(4700),   UINT32_C(250),  UINT32_C(4000), UINT32_C(4700)};
    } else if (bus_hz <= UINT32_C(400000)) {
        mode = (rs_i2c_mode_t){UINT32_C(400000), UINT32_C(1300), UINT32_C(600), UINT32_C(600),
                               UINT32_C(600),    UINT32_C(100),  UINT32_C(600), UINT32_C(1300)};
    } else {
        mode = (rs_i2c_mode_t){UINT32_C(1000000), UINT32_C(500), UINT32_C(260), UINT32_C(260),
                               UINT32_C(260),     UINT32_C(50),  UINT32_C(260), UINT32_C(500)};
    }
    return mode;
}

rs_status_t rs_i2c_timing_calculate(uint32_t source_clock_hz, uint32_t bus_hz,
                                    rs_i2c_timing_t *timing) {
    rs_i2c_mode_t mode;
    uint64_t low_cycles;
    uint64_t high_cycles;
    uint64_t target_cycles;
    uint64_t start_hold_cycles;
    uint64_t start_setup_cycles;
    uint64_t data_setup_cycles;
    uint64_t stop_setup_cycles;
    uint64_t bus_free_cycles;

    if ((source_clock_hz == 0U) || (bus_hz == 0U) || (bus_hz > UINT32_C(1000000)) ||
        (timing == NULL)) {
        return RS_EINVAL;
    }
    mode = rs_i2c_mode_for_rate(bus_hz);
    if (bus_hz > mode.maximum_hz) {
        return RS_EINVAL;
    }
    low_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.low_ns);
    high_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.high_ns);
    target_cycles = rs_i2c_divide_ceil((uint64_t)source_clock_hz, (uint64_t)bus_hz);
    if ((low_cycles + high_cycles) < target_cycles) {
        low_cycles += target_cycles - (low_cycles + high_cycles);
    }
    start_hold_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.start_hold_ns);
    start_setup_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.start_setup_ns);
    data_setup_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.data_setup_ns);
    stop_setup_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.stop_setup_ns);
    bus_free_cycles = rs_i2c_cycles_from_ns(source_clock_hz, mode.bus_free_ns);
    if ((low_cycles == 0U) || (high_cycles == 0U) || (start_hold_cycles == 0U) ||
        (start_setup_cycles == 0U) || (data_setup_cycles == 0U) || (stop_setup_cycles == 0U) ||
        (bus_free_cycles == 0U) || (low_cycles > UINT16_MAX) || (high_cycles > UINT16_MAX) ||
        (start_hold_cycles > UINT16_MAX) || (start_setup_cycles > UINT16_MAX) ||
        (data_setup_cycles > UINT16_MAX) || (stop_setup_cycles > UINT16_MAX) ||
        (bus_free_cycles > UINT16_MAX)) {
        return RS_EINVAL;
    }
    timing->scl_low_cycles = (uint16_t)low_cycles;
    timing->scl_high_cycles = (uint16_t)high_cycles;
    timing->start_hold_cycles = (uint16_t)start_hold_cycles;
    timing->start_setup_cycles = (uint16_t)start_setup_cycles;
    timing->data_hold_cycles = 0U;
    timing->data_setup_cycles = (uint16_t)data_setup_cycles;
    timing->stop_setup_cycles = (uint16_t)stop_setup_cycles;
    timing->bus_free_cycles = (uint16_t)bus_free_cycles;
    return RS_OK;
}
