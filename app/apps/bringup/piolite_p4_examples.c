#include "piolite_p4_examples.h"

#include <stddef.h>

static rs_status_t rs_piolite_p4_configure(rs_piolite_p4_session_t *handle, uint32_t sm,
                                           const rs_piolite_p4_sm_options_t *options,
                                           rs_piolite_allocation_t *allocation) {
    const rs_piolite_program_t *program =
        options == NULL ? handle->allocations[0]->program : options->program;
    rs_piolite_sm_config_t config;
    rs_status_t status = rs_piolite_program_config(program, allocation, sm, &config);
    if (status != RS_OK) {
        return status;
    }
    if (options == NULL) {
        config.divider = 1U;
        config.in_pins = 0U;
        config.out_pins = 0U;
        config.set_pins = 0U;
        config.claim_mask = 0U;
        config.output_mask = 0U;
        config.initial_value = 0U;
        config.initial_oe = 0U;
        config.initial_xy = 0U;
        config.test_select = 0U;
        config.config &= ~(UINT32_C(1) << RS_PIOLITE_ABI_CONFIG_TEST_PIN_ENABLE);
    } else {
        config.divider = options->divider;
        config.initial_value = options->initial_value;
        config.initial_oe = config.output_mask;
        config.initial_xy = options->initial_xy;
        if (options->tx_bits != 0U) {
            config.shift_limits = (config.shift_limits & UINT32_C(0x3F00)) | options->tx_bits;
        }
    }
    return rs_piolite_configure(&handle->session, sm, &config);
}

rs_status_t rs_piolite_p4_close(rs_piolite_p4_session_t *handle, rs_timeout_t timeout) {
    rs_status_t first = RS_OK;
    if ((handle == NULL) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (handle->session.active) {
        handle->open_stage = 8U;
        if (handle->session.claimed || handle->session.bound[0] || handle->session.bound[1]) {
            first = rs_piolite_abort_reset(&handle->session, 3U, timeout);
        }
        handle->open_stage = 9U;
        if ((first == RS_OK) && handle->session.claimed) {
            first = rs_piolite_release(&handle->session, timeout);
        }
        handle->open_stage = 10U;
        for (uint32_t index = handle->allocation_count; (first == RS_OK) && (index-- > 0U);) {
            rs_piolite_allocation_t *allocation = handle->allocations[index];
            if ((allocation != NULL) && allocation->published) {
                first = rs_piolite_program_unload(&handle->session, allocation);
            }
        }
        handle->open_stage = 11U;
        if (first == RS_OK) {
            first = rs_piolite_session_release(&handle->session);
        }
    }
    handle->cleanup_status = first;
    if (first == RS_OK) {
        const rs_status_t cleanup_status = handle->cleanup_status;
        *handle = (rs_piolite_p4_session_t){0};
        handle->cleanup_status = cleanup_status;
    }
    return first;
}

rs_status_t rs_piolite_p4_open(rs_piolite_p4_session_t *handle,
                               const rs_piolite_p4_sm_options_t *sm0,
                               const rs_piolite_p4_sm_options_t *sm1, rs_timeout_t timeout) {
    rs_status_t status;
    if ((handle == NULL) || (sm0 == NULL) || (sm0->program == NULL) || (sm0->divider == 0U) ||
        ((sm1 != NULL) && ((sm1->program == NULL) || (sm1->divider == 0U))) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    *handle = (rs_piolite_p4_session_t){0};
    handle->open_stage = 1U;
    status = rs_piolite_session_init(&handle->session);
    if (status == RS_OK) {
        handle->open_stage = 2U;
        status = rs_piolite_program_load(&handle->session, sm0->program, RS_PIOLITE_ALLOCATE_ANY,
                                         &handle->allocations[0]);
    }
    if (status == RS_OK) {
        handle->allocation_count = 1U;
        if (sm1 != NULL) {
            handle->open_stage = 3U;
            status = rs_piolite_program_load(&handle->session, sm1->program,
                                             RS_PIOLITE_ALLOCATE_ANY, &handle->allocations[1]);
            handle->allocation_count = 2U;
        }
    }
    if (status == RS_OK) {
        handle->open_stage = 4U;
        status = rs_piolite_p4_configure(handle, 0U, sm0, handle->allocations[0]);
    }
    if (status == RS_OK) {
        rs_piolite_allocation_t *allocation =
            sm1 == NULL ? handle->allocations[0] : handle->allocations[1];
        handle->open_stage = 5U;
        status = rs_piolite_p4_configure(handle, 1U, sm1, allocation);
    }
    if (status == RS_OK) {
        handle->open_stage = 6U;
        status = rs_piolite_claim(&handle->session, timeout);
    }
    if (status == RS_OK) {
        handle->open_stage = 7U;
    } else {
        const uint8_t open_stage = handle->open_stage;
        const rs_status_t cleanup = rs_piolite_p4_close(handle, timeout);
        handle->open_stage = open_stage;
        handle->cleanup_status = cleanup;
    }
    return status;
}

rs_status_t rs_piolite_p4_dma_begin(rs_piolite_p4_session_t *handle, uint32_t direction,
                                    uint32_t sm, uint32_t channel, const rs_dma_config_t *config,
                                    rs_timeout_t timeout) {
    rs_status_t status;
    if ((handle == NULL) || (config == NULL) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    status = rs_piolite_dma_bind(&handle->session, direction, sm, channel, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_dma_start(&handle->session, direction, config);
    if (status != RS_OK) {
        const rs_status_t cleanup = rs_piolite_dma_unbind(&handle->session, direction, timeout);
        if (cleanup != RS_OK) {
            handle->cleanup_status = cleanup;
        }
    }
    return status;
}
