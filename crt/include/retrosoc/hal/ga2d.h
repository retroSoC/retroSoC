#ifndef RETROSOC_HAL_GA2D_H
#define RETROSOC_HAL_GA2D_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/ga2d_regs.h>

typedef enum {
    RS_GA2D_OP_FILL = 0,
    RS_GA2D_OP_COPY = 1,
    RS_GA2D_OP_CONVERT = 2,
    RS_GA2D_OP_BLEND = 3,
} rs_ga2d_operation_t;

typedef enum {
    RS_GA2D_FORMAT_RGB565 = 0,
    RS_GA2D_FORMAT_RGB888 = 1,
    RS_GA2D_FORMAT_XRGB8888 = 2,
    RS_GA2D_FORMAT_ARGB8888 = 3,
    RS_GA2D_FORMAT_A8 = 4,
} rs_ga2d_format_t;

typedef struct {
    uintptr_t address;
    uint32_t pitch;
    rs_ga2d_format_t format;
} rs_ga2d_surface_t;

typedef struct {
    rs_ga2d_operation_t operation;
    rs_ga2d_surface_t foreground;
    rs_ga2d_surface_t background;
    rs_ga2d_surface_t destination;
    uint16_t width;
    uint16_t height;
    uint8_t global_alpha;
    uint32_t color;
} rs_ga2d_job_t;

typedef struct {
    uint32_t version;
    uint32_t features;
    uint32_t limits;
    uint32_t formats;
} rs_ga2d_capability_t;

typedef struct {
    bool busy;
    bool draining;
    bool quiesced;
    bool data_ready;
    bool done;
    bool aborted;
    bool error;
    bool recovery_required;
    uint32_t irq_state;
} rs_ga2d_status_t;

typedef struct {
    bool valid;
    uint8_t code;
    uint8_t stage;
    uint8_t axi_response;
    uintptr_t address;
} rs_ga2d_error_t;

typedef struct {
    uint64_t cycles;
    uint64_t read_bytes;
    uint64_t write_bytes;
    uint64_t read_stalls;
    uint64_t write_stalls;
    uint64_t pipe_stalls;
    uint16_t lines_done;
} rs_ga2d_stats_t;

rs_status_t rs_ga2d_get_capability(rs_ga2d_capability_t *capability);
rs_status_t rs_ga2d_job_validate(const rs_ga2d_job_t *job);
rs_status_t rs_ga2d_configure(const rs_ga2d_job_t *job);
rs_status_t rs_ga2d_start(void);
rs_status_t rs_ga2d_wait(rs_timeout_t timeout);
rs_status_t rs_ga2d_abort_wait(rs_timeout_t timeout);
rs_status_t rs_ga2d_reset(void);
rs_status_t rs_ga2d_get_status(rs_ga2d_status_t *status);
rs_status_t rs_ga2d_get_error(rs_ga2d_error_t *error);
rs_status_t rs_ga2d_get_stats(rs_ga2d_stats_t *stats);
rs_status_t rs_ga2d_irq_enable(uint32_t mask);
rs_status_t rs_ga2d_irq_pending(uint32_t *pending);
rs_status_t rs_ga2d_irq_clear(uint32_t mask);

#endif
