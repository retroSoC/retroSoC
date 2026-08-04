#ifndef RETROSOC_HAL_PERF_H
#define RETROSOC_HAL_PERF_H

#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint64_t mgmt_wait;
    uint64_t user_wait;
    uint64_t dma_wait;
    uint64_t ribp_wait;
    uint64_t apb_wait;
    uint64_t sdram_wait;
    uint64_t psram_wait;
    uint64_t flash_wait;
} rs_perf_snapshot_t;

rs_status_t rs_perf_start(void);
rs_status_t rs_perf_stop(void);
rs_status_t rs_perf_snapshot(rs_perf_snapshot_t *snapshot);

#endif
