#ifndef RETROSOC_HAL_NPU_H
#define RETROSOC_HAL_NPU_H

#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/npu_regs.h>

typedef struct {
    uint32_t descriptor_address;
    uint32_t descriptor_count;
    uint32_t job_id;
    uint32_t timeout_cycles;
} rs_npu_job_t;

typedef struct {
    uint32_t ip_id;
    uint32_t ip_version;
    uint32_t flags;
    uint32_t numeric_profile;
    uint32_t local_bytes;
    uint32_t dense_macs;
    uint32_t depthwise_macs;
    uint32_t max_k_slice;
    uint32_t max_dimension;
    uint32_t op_mask;
} rs_npu_capability_t;

typedef struct {
    uint32_t flags;
    uint32_t job_id;
    uint32_t result_code;
    uint32_t completed_descriptors;
    uint32_t recovery_generation;
} rs_npu_status_t;

typedef struct {
    uint32_t code;
    uint32_t address;
    uint32_t descriptor_index;
    uint32_t info;
} rs_npu_error_t;

typedef struct {
    uint32_t job_id;
    uint32_t recovery_generation;
    uint64_t active_cycles;
    uint64_t clock_pause_cycles;
    uint64_t useful_macs;
    uint64_t pack_cycles;
    uint64_t local_bank_stall_cycles;
    uint64_t dma_read_bytes;
    uint64_t dma_write_bytes;
    uint64_t dma_stall_cycles;
    uint64_t requant_stall_cycles;
    uint64_t retired_descriptors;
} rs_npu_counters_t;

rs_status_t rs_npu_get_capability(rs_npu_capability_t *capability);
rs_status_t rs_npu_submit(const rs_npu_job_t *job);
rs_status_t rs_npu_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status);
rs_status_t rs_npu_abort_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status);
rs_status_t rs_npu_reset(rs_timeout_t timeout);
rs_status_t rs_npu_get_status(rs_npu_status_t *status);
rs_status_t rs_npu_get_error(rs_npu_error_t *error);
rs_status_t rs_npu_snapshot_counters(rs_timeout_t timeout, rs_npu_counters_t *counters);
rs_status_t rs_npu_irq_enable(uint32_t events);
rs_status_t rs_npu_irq_pending(uint32_t *events);
rs_status_t rs_npu_irq_ack(uint32_t events);

#endif
