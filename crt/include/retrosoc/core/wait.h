#ifndef RETROSOC_CORE_WAIT_H
#define RETROSOC_CORE_WAIT_H

#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

static inline rs_status_t rs_wait_mask(volatile const uint32_t *reg, uint32_t mask,
                                       uint32_t expected, rs_timeout_t timeout) {
    if ((reg == NULL) || (mask == 0U)) {
        return RS_EINVAL;
    }

    while (timeout-- != 0U) {
        if ((*reg & mask) == expected) {
            return RS_OK;
        }
    }

    return RS_ETIMEOUT;
}

static inline rs_status_t rs_wait_value(volatile const uint32_t *reg, uint32_t expected,
                                        rs_timeout_t timeout) {
    if (reg == NULL) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        if (*reg == expected) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static inline rs_status_t rs_wait_not_value(volatile const uint32_t *reg, uint32_t value,
                                            rs_timeout_t timeout) {
    if (reg == NULL) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        if (*reg != value) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

#endif
