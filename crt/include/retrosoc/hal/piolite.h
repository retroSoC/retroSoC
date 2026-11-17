#ifndef RETROSOC_HAL_PIOLITE_H
#define RETROSOC_HAL_PIOLITE_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/piolite_regs.h>

typedef enum {
    RS_PIOLITE_DMA_TX = 0,
    RS_PIOLITE_DMA_RX = 1,
} rs_piolite_dma_direction_t;

typedef struct {
    uint32_t ip_id;
    uint32_t apb_version;
    uint32_t isa_version;
    uint32_t capability;
    uint32_t routable_mask;
    uint32_t clock_hz;
    uint32_t transport_status;
} rs_piolite_info_t;

typedef struct {
    uint32_t isa_version;
    const uint16_t *words;
    uint32_t word_count;
    const uint8_t *relocation_sites;
    uint32_t relocation_count;
    uint32_t entry;
    uint32_t wrap_bottom;
    uint32_t wrap_top;
} rs_piolite_image_t;

typedef struct {
    uint16_t *storage;
    uint32_t capacity;
    uint32_t base;
    uint32_t word_count;
    bool loaded;
} rs_piolite_program_t;

typedef struct {
    uint32_t sm;
    const rs_piolite_program_t *program;
    uint32_t divider;
    uint32_t entry;
    uint32_t wrap_bottom;
    uint32_t wrap_top;
    uint32_t in_base;
    uint32_t in_width;
    uint32_t out_base;
    uint32_t out_width;
    uint32_t set_base;
    uint32_t set_width;
    uint32_t claim_mask;
    uint32_t output_mask;
    uint32_t initial_value;
    uint32_t initial_oe;
    uint32_t initial_x;
    uint32_t initial_y;
    uint32_t tx_bits;
    uint32_t rx_bits;
    uint32_t test_pin;
    uint32_t test_flag;
    uint32_t tx_low;
    uint32_t rx_high;
    bool autopull;
    bool autopush;
    bool tx_right;
    bool rx_right;
    bool test_pin_enable;
} rs_piolite_config_t;

typedef struct {
    rs_dma_session_t *lease;
    uintptr_t buffer;
    uint32_t capacity_bytes;
    uint32_t word_count;
    bool acquired;
    bool bound;
} rs_piolite_dma_t;

typedef struct {
    uint32_t sm;
    const rs_piolite_program_t *program;
    uint32_t claim_mask;
    uint32_t recovery_mask;
    rs_piolite_dma_t dma[2];
    bool configured;
    bool claimed;
    bool started;
    bool closing;
    bool output_cleanup_pending;
} rs_piolite_session_t;

typedef struct {
    uint32_t status;
    uint32_t events;
    uint32_t fault;
    uint32_t fifo_levels;
    uint32_t transport_status;
    uint32_t owned_mask;
    uint32_t pc;
    bool complete;
} rs_piolite_status_t;

/* Keep program, session, lease and payload storage alive until release/recovery.
 * Quiesce native peripherals and clear their ALT routes before claiming pins. */
rs_status_t rs_piolite_discover(rs_piolite_info_t *info);
rs_status_t rs_piolite_configure(rs_piolite_session_t *session, const rs_piolite_config_t *config);
rs_status_t rs_piolite_program_load(rs_piolite_program_t *program, const rs_piolite_image_t *image,
                                    uint32_t base);
rs_status_t rs_piolite_program_unload(rs_piolite_program_t *program);
rs_status_t rs_piolite_claim(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_release(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_dma_bind(rs_piolite_session_t *session, rs_piolite_dma_direction_t direction,
                                rs_dma_session_t *lease, uintptr_t buffer, uint32_t capacity_bytes,
                                uint32_t word_count);
rs_status_t rs_piolite_dma_unbind(rs_piolite_session_t *session,
                                  rs_piolite_dma_direction_t direction);
rs_status_t rs_piolite_fifo_write(rs_piolite_session_t *session, const uint32_t *words,
                                  uint32_t word_count, rs_timeout_t timeout);
rs_status_t rs_piolite_fifo_read(rs_piolite_session_t *session, uint32_t *words,
                                 uint32_t word_count, rs_timeout_t timeout);
rs_status_t rs_piolite_start(rs_piolite_session_t *session);
rs_status_t rs_piolite_pause(rs_piolite_session_t *session);
rs_status_t rs_piolite_resume(rs_piolite_session_t *session);
rs_status_t rs_piolite_disable(rs_piolite_session_t *session);
rs_status_t rs_piolite_wait_done(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_abort_reset(rs_piolite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_piolite_get_status(const rs_piolite_session_t *session, rs_piolite_status_t *status);

#endif
