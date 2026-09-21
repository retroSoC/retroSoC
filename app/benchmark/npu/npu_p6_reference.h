#ifndef RETROSOC_APP_BENCHMARK_NPU_P6_REFERENCE_H
#define RETROSOC_APP_BENCHMARK_NPU_P6_REFERENCE_H

#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t base;
    uint32_t bytes;
    uint8_t *data;
} rs_npu_p6_region_t;

typedef struct {
    uint32_t base;
    uint32_t bytes;
    const uint8_t *data;
} rs_npu_p6_const_region_t;

typedef struct {
    rs_npu_p6_region_t arena;
    rs_npu_p6_const_region_t weights;
    rs_npu_p6_const_region_t params;
} rs_npu_p6_memory_t;

rs_status_t rs_npu_p6_reference_execute(const uint32_t *descriptors, uint32_t descriptor_count,
                                        const rs_npu_p6_memory_t *memory);

#endif
