#ifndef RETROSOC_HAL_PIOLITE_H
#define RETROSOC_HAL_PIOLITE_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/piolite_regs.h>

#define RS_PIOLITE_SM_COUNT          2U
#define RS_PIOLITE_IMEM_WORDS        32U
#define RS_PIOLITE_DMA_CHANNEL_COUNT 8U
#define RS_PIOLITE_ALLOCATE_ANY      UINT32_C(0xFFFFFFFF)
#define RS_PIOLITE_TEST_PIN_NONE     UINT8_C(0xFF)
#define RS_PIOLITE_TX                0U
#define RS_PIOLITE_RX                1U
#define RS_PIOLITE_TAIL_ZERO         0U
#define RS_PIOLITE_TAIL_APPLICATION  1U

typedef struct {
    uint32_t isa_version;
    const uint16_t *words;
    uint32_t word_count;
    uint8_t entry;
    uint8_t wrap_bottom;
    uint8_t wrap_top;
    const uint8_t *relocation_sites;
    uint32_t relocation_count;
    uint8_t in_base;
    uint8_t in_width;
    uint8_t out_base;
    uint8_t out_width;
    uint8_t set_base;
    uint8_t set_width;
    uint8_t tx_bits;
    uint8_t tx_right;
    uint8_t autopull;
    uint8_t rx_bits;
    uint8_t rx_right;
    uint8_t autopush;
    uint8_t test_pin;
    uint8_t test_flag;
    uint8_t test_pin_enable;
    uint32_t claim_mask;
    uint32_t flag_mask;
    uint32_t tx_items;
    uint32_t rx_items;
    uint8_t item_bits;
    uint32_t clock_ticks;
    uint8_t stretchable;
} rs_piolite_program_t;

typedef struct {
    uint32_t config;
    uint16_t divider;
    uint32_t program;
    uint32_t wrap;
    uint32_t in_pins;
    uint32_t out_pins;
    uint32_t set_pins;
    uint32_t claim_mask;
    uint32_t output_mask;
    uint32_t initial_value;
    uint32_t initial_oe;
    uint32_t initial_xy;
    uint32_t shift_limits;
    uint32_t test_select;
    uint32_t watermarks;
    uint32_t tx_items;
    uint32_t rx_items;
    uint32_t item_bits;
    uint8_t tx_tail_policy;
    uint8_t rx_tail_policy;
} rs_piolite_sm_config_t;

typedef struct {
    const rs_piolite_program_t *program;
    uint32_t base;
    uint32_t handle;
    uint16_t references;
    uint8_t word_count;
    bool published;
} rs_piolite_allocation_t;

typedef struct {
    rs_piolite_allocation_t allocations[RS_PIOLITE_IMEM_WORDS];
    rs_piolite_sm_config_t sm[RS_PIOLITE_SM_COUNT];
    rs_dma_session_t dma[2];
    uint32_t expected_dma_bytes[2];
    uint32_t claim_mask;
    uint32_t next_handle;
    bool active;
    bool claimed;
    bool bound[2];
    bool dma_started[2];
    bool recovery_failed;
} rs_piolite_session_t;

typedef struct {
    uint32_t ip_id;
    uint32_t apb_version;
    uint32_t isa_version;
    uint32_t capability;
    uint32_t routable_mask;
    uint32_t clock_hz;
} rs_piolite_info_t;

typedef struct {
    uint32_t status;
    uint32_t fault;
    uint32_t fifo_levels;
    uint32_t transport_status;
    uint32_t owned_mask;
    uint32_t events;
    uint32_t pc;
    uint32_t shift_counts;
    uint32_t tick_count;
    uint32_t tx_stall_count;
    uint32_t rx_stall_count;
    uint32_t retired_count;
} rs_piolite_status_t;

rs_status_t rs_piolite_probe(rs_piolite_info_t *info);
rs_status_t rs_piolite_session_init(rs_piolite_session_t *session);
rs_status_t rs_piolite_session_release(rs_piolite_session_t *session);
rs_status_t rs_piolite_program_config(const rs_piolite_program_t *program,
                                      const rs_piolite_allocation_t *allocation, uint32_t sm,
                                      rs_piolite_sm_config_t *config);
rs_status_t rs_piolite_configure(rs_piolite_session_t *session, uint32_t sm,
                                 const rs_piolite_sm_config_t *config);
rs_status_t rs_piolite_program_load(rs_piolite_session_t *session,
                                    const rs_piolite_program_t *program, uint32_t requested_base,
                                    rs_piolite_allocation_t **allocation);
rs_status_t rs_piolite_program_unload(rs_piolite_session_t *session,
                                      rs_piolite_allocation_t *allocation);
rs_status_t rs_piolite_claim(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_release(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_dma_bind(rs_piolite_session_t *session, uint32_t direction, uint32_t sm,
                                uint32_t channel, rs_timeout_t timeout);
rs_status_t rs_piolite_dma_unbind(rs_piolite_session_t *session, uint32_t direction,
                                  rs_timeout_t timeout);
rs_status_t rs_piolite_dma_start(rs_piolite_session_t *session, uint32_t direction,
                                 const rs_dma_config_t *config);
rs_status_t rs_piolite_dma_submit_tcd_chain(rs_piolite_session_t *session, uint32_t direction,
                                            rs_dma_tcd_t *first, uint32_t max_tcds,
                                            rs_timeout_t timeout);
rs_status_t rs_piolite_write(rs_piolite_session_t *session, uint32_t sm, uint32_t value);
rs_status_t rs_piolite_read(rs_piolite_session_t *session, uint32_t sm, uint32_t *value);
rs_status_t rs_piolite_start(rs_piolite_session_t *session, uint32_t sm_mask);
rs_status_t rs_piolite_pause(rs_piolite_session_t *session, uint32_t sm_mask);
rs_status_t rs_piolite_resume(rs_piolite_session_t *session, uint32_t sm_mask);
rs_status_t rs_piolite_disable(rs_piolite_session_t *session, uint32_t sm_mask);
rs_status_t rs_piolite_wait_done(rs_piolite_session_t *session, uint32_t sm, rs_timeout_t timeout);
rs_status_t rs_piolite_abort_reset(rs_piolite_session_t *session, uint32_t sm_mask,
                                   rs_timeout_t timeout);
rs_status_t rs_piolite_get_status(const rs_piolite_session_t *session, uint32_t sm,
                                  rs_piolite_status_t *status);
rs_status_t rs_piolite_flag_set(rs_piolite_session_t *session, uint32_t flag_mask);
rs_status_t rs_piolite_flag_clear(rs_piolite_session_t *session, uint32_t flag_mask);

#endif
