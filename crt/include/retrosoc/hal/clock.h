#ifndef RETROSOC_HAL_CLOCK_H
#define RETROSOC_HAL_CLOCK_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_CLOCK_FREQ_24MHZ = 0,
    RS_CLOCK_FREQ_48MHZ = 1,
    RS_CLOCK_FREQ_72MHZ = 2,
    RS_CLOCK_FREQ_96MHZ = 3,
    RS_CLOCK_FREQ_120MHZ = 4,
    RS_CLOCK_FREQ_144MHZ = 5,
    RS_CLOCK_FREQ_168MHZ = 6,
    RS_CLOCK_FREQ_192MHZ = 7,
} rs_clock_frequency_t;

typedef struct {
    rs_clock_frequency_t requested_frequency;
    rs_clock_frequency_t active_frequency;
    uint8_t error_reason;
    bool active_valid;
    bool busy;
    bool safe_clock;
    bool pll_locked;
    bool capable;
} rs_clock_status_t;

rs_status_t rs_clock_get_status(rs_clock_status_t *status);
rs_status_t rs_clock_set_frequency(rs_clock_frequency_t frequency, rs_timeout_t timeout);

#endif
