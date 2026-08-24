#ifndef RETROSOC_HAL_ONCHIP_SRAM_H
#define RETROSOC_HAL_ONCHIP_SRAM_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/onchip_sram_regs.h>

typedef struct {
    uint32_t capability;
    uint32_t memory_bytes;
    uint32_t bank_count;
    uint32_t bank_bytes;
    uint8_t max_burst_beats;
    uint8_t data_bytes;
    bool present;
} rs_onchip_sram_info_t;

typedef struct {
    uint32_t read_requests;
    uint32_t write_requests;
    uint32_t read_beats;
    uint32_t write_beats;
    uint32_t stall_cycles;
    uint32_t error_responses;
} rs_onchip_sram_perf_t;

rs_status_t rs_onchip_sram_probe(rs_onchip_sram_info_t *info);
rs_status_t rs_onchip_sram_read_performance(rs_onchip_sram_perf_t *performance);

#endif
