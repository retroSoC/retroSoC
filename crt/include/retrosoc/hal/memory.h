#ifndef RETROSOC_HAL_MEMORY_H
#define RETROSOC_HAL_MEMORY_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_MEMORY_SRAM = 0,
    RS_MEMORY_SDRAM = 1,
    RS_MEMORY_QPI_PSRAM = 2,
    RS_MEMORY_OPI_PSRAM = 3,
    RS_MEMORY_XPI = 4,
} rs_memory_target_t;

typedef enum {
    RS_MEMORY_PAD_NONE = 0,
    RS_MEMORY_PAD_QPI = 1,
    RS_MEMORY_PAD_OPI = 2,
} rs_memory_pad_mode_t;

typedef enum {
    RS_MEMORY_LATENCY_ONCHIP = 0,
    RS_MEMORY_LATENCY_PARALLEL = 1,
    RS_MEMORY_LATENCY_SERIAL = 2,
} rs_memory_latency_t;

typedef struct {
    uintptr_t base;
    uint32_t size;
    uint32_t fault_code;
    rs_memory_target_t target;
    rs_memory_pad_mode_t pad_mode;
    rs_memory_latency_t latency;
    bool controller_present;
    bool device_present;
    bool initialized;
    bool ready;
    bool active;
    bool cacheable;
    bool dma_visible;
    bool fault;
} rs_memory_info_t;

rs_status_t rs_memory_get_info(rs_memory_target_t target, rs_memory_info_t *info);

#endif
