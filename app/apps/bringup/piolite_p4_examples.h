#ifndef RETROSOC_PIOLITE_P4_EXAMPLES_H
#define RETROSOC_PIOLITE_P4_EXAMPLES_H

#include <retrosoc/hal/piolite.h>

typedef struct {
    const rs_piolite_program_t *program;
    uint16_t divider;
    uint32_t initial_value;
    uint32_t initial_xy;
    uint8_t tx_bits;
} rs_piolite_p4_sm_options_t;

typedef struct {
    rs_piolite_session_t session;
    rs_piolite_allocation_t *allocations[RS_PIOLITE_SM_COUNT];
    uint32_t allocation_count;
    rs_status_t cleanup_status;
    uint8_t open_stage;
} rs_piolite_p4_session_t;

rs_status_t rs_piolite_p4_open(rs_piolite_p4_session_t *handle,
                               const rs_piolite_p4_sm_options_t *sm0,
                               const rs_piolite_p4_sm_options_t *sm1, rs_timeout_t timeout);
rs_status_t rs_piolite_p4_close(rs_piolite_p4_session_t *handle, rs_timeout_t timeout);
rs_status_t rs_piolite_p4_dma_begin(rs_piolite_p4_session_t *handle, uint32_t direction,
                                    uint32_t sm, uint32_t channel, const rs_dma_config_t *config,
                                    rs_timeout_t timeout);

#endif
