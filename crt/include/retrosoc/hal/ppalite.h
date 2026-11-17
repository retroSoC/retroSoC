#ifndef RETROSOC_HAL_PPALITE_H
#define RETROSOC_HAL_PPALITE_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/ppalite_regs.h>

typedef enum {
    RS_PPALITE_ROUTE_RAW = 0,
    RS_PPALITE_ROUTE_PROCESS = 1,
} rs_ppalite_route_t;

typedef enum {
    RS_PPALITE_INPUT_RGB565_BE = 0,
    RS_PPALITE_INPUT_RGB565_LE = 1,
    RS_PPALITE_INPUT_YUYV = 2,
    RS_PPALITE_INPUT_UYVY = 3,
    RS_PPALITE_INPUT_YVYU = 4,
    RS_PPALITE_INPUT_VYUY = 5,
} rs_ppalite_input_format_t;

typedef struct {
    rs_ppalite_input_format_t input_format;
    rs_dvp_config_t source;
    uint8_t step_x;
    uint8_t step_y;
    uint8_t phase_x;
    uint8_t phase_y;
    bool output_gray8;
    bool rgb_swap;
    bool output_byte_swap;
} rs_ppalite_config_t;

typedef struct {
    uint16_t width;
    uint16_t height;
    uint32_t row_bytes;
    uint32_t stride_bytes;
    uint32_t valid_bytes;
    uint32_t transport_bytes;
    uint32_t expected_words;
} rs_ppalite_layout_t;

typedef struct {
    uint32_t version;
    uint32_t capability;
    uint32_t buffer_capability;
    uint32_t clock_hz;
    uint32_t dma_binding;
} rs_ppalite_info_t;

typedef struct {
    uint32_t status;
    uint32_t irq_state;
    uint32_t first_error;
    uint32_t source_error;
    uint32_t dma_error;
    bool owned;
    bool result_valid;
} rs_ppalite_status_t;

typedef struct {
    uint32_t input_words;
    uint32_t input_pixels;
    uint32_t input_lines;
    uint32_t output_words;
    uint32_t output_lines;
    uint32_t input_stall_cycles;
    uint32_t output_stall_cycles;
    uint32_t fifo_levels;
} rs_ppalite_measurements_t;

typedef struct {
    uintptr_t base;
    uint32_t capacity_bytes;
    uint16_t width;
    uint16_t height;
    rs_ppalite_input_format_t input_format;
    uint32_t result_config;
    uint32_t row_bytes;
    uint32_t stride_bytes;
    uint32_t valid_bytes;
    uint32_t transport_bytes;
    uint32_t job_sequence;
    uint32_t source_sequence;
    uint32_t error_status;
    bool output_byte_swap;
    bool valid;
} rs_ppalite_frame_t;

typedef struct {
    rs_dma_session_t dma_session;
    rs_ppalite_config_t config;
    rs_ppalite_layout_t layout;
    uintptr_t destination;
    uint32_t capacity_bytes;
    bool acquired;
    bool started;
    bool stop_requested;
    bool finalized;
} rs_ppalite_session_t;

rs_status_t rs_ppalite_probe(rs_ppalite_info_t *info);
rs_status_t rs_ppalite_layout(const rs_ppalite_config_t *config, uintptr_t destination,
                              uint32_t capacity_bytes, rs_ppalite_layout_t *layout);
rs_status_t rs_ppalite_configure(const rs_ppalite_config_t *config);
rs_status_t rs_ppalite_select_route(rs_ppalite_route_t route, rs_timeout_t timeout);
rs_status_t rs_ppalite_capture_begin(rs_ppalite_session_t *session,
                                     const rs_ppalite_config_t *config, uintptr_t destination,
                                     uint32_t capacity_bytes, rs_timeout_t timeout);
rs_status_t rs_ppalite_capture_start(rs_ppalite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_ppalite_capture_wait(rs_ppalite_session_t *session, rs_ppalite_frame_t *frame,
                                    rs_timeout_t timeout);
rs_status_t rs_ppalite_get_status(rs_ppalite_status_t *status);
rs_status_t rs_ppalite_get_measurements(rs_ppalite_measurements_t *measurements);
rs_status_t rs_ppalite_abort(rs_ppalite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_ppalite_recover(rs_ppalite_session_t *session, rs_timeout_t timeout);
rs_status_t rs_ppalite_release(rs_ppalite_session_t *session, rs_timeout_t timeout);

#endif
