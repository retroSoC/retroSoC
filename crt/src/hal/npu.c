#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/npu.h>

#if defined(RS_NPU_TEST_MMIO)
extern volatile uint32_t rs_npu_test_mmio[1024];
#undef RS_NPU_REG
#define RS_NPU_REG(offset) rs_npu_test_mmio[(offset) / 4U]
#endif

#if defined(RS_NPU_REG)

static void rs_npu_fence(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

static uint32_t rs_npu_poll_count(rs_timeout_t timeout) {
    return (timeout == 0U) ? 1U : timeout;
}

static rs_status_t rs_npu_require_shell(void) {
    rs_npu_capability_t capability;

    return rs_npu_get_capability(&capability);
}

static rs_status_t rs_npu_require_irq(void) {
    rs_npu_capability_t capability;
    rs_status_t status;

    status = rs_npu_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    return ((capability.flags & RS_NPU_CAPABILITY_INTERRUPTS) != 0U) ? RS_OK : RS_ENOTSUP;
}

static bool rs_npu_token_known(uint32_t job_id, uint32_t flags) {
    if ((flags & (RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING)) != 0U) {
        return job_id == RS_NPU_REG(RS_NPU_REG_JOB_ID);
    }
    return ((flags & RS_NPU_STATUS_RESULT_VALID) != 0U) &&
           (job_id == RS_NPU_REG(RS_NPU_REG_RESULT_JOB_ID));
}

static void rs_npu_read_status(rs_npu_status_t *status) {
    status->flags = RS_NPU_REG(RS_NPU_REG_STATUS);
    status->job_id = RS_NPU_REG(RS_NPU_REG_RESULT_JOB_ID);
    status->result_code = RS_NPU_REG(RS_NPU_REG_RESULT_CODE);
    status->completed_descriptors = RS_NPU_REG(RS_NPU_REG_COMPLETED_DESCRIPTORS);
    status->recovery_generation = RS_NPU_REG(RS_NPU_REG_RECOVERY_GENERATION);
}

static rs_status_t rs_npu_result_status(uint32_t result_code) {
    return (result_code == RS_NPU_RESULT_DONE) ? RS_OK : RS_EIO;
}

static uint64_t rs_npu_read_counter(uint32_t low_offset) {
    return ((uint64_t)RS_NPU_REG(low_offset + 4U) << 32U) | (uint64_t)RS_NPU_REG(low_offset);
}

static rs_status_t rs_npu_wait_terminal(uint32_t job_id, rs_timeout_t timeout,
                                        rs_npu_status_t *status) {
    uint32_t polls = rs_npu_poll_count(timeout);

    while (polls-- != 0U) {
        if ((RS_NPU_REG(RS_NPU_REG_STATUS) & RS_NPU_STATUS_RESULT_VALID) != 0U) {
            if (RS_NPU_REG(RS_NPU_REG_RESULT_JOB_ID) != job_id) {
                return RS_EIO;
            }
            rs_npu_read_status(status);
            rs_npu_fence();
            return rs_npu_result_status(status->result_code);
        }
    }
    rs_npu_read_status(status);
    return RS_ETIMEOUT;
}

rs_status_t rs_npu_get_capability(rs_npu_capability_t *capability) {
    uint32_t ip_id;
    uint32_t mac_config;

    if (capability == NULL) {
        return RS_EINVAL;
    }
    ip_id = RS_NPU_REG(RS_NPU_REG_IP_ID);
    mac_config = RS_NPU_REG(RS_NPU_REG_MAC_CONFIG);
    capability->ip_id = ip_id;
    capability->ip_version = RS_NPU_REG(RS_NPU_REG_IP_VERSION);
    capability->flags = RS_NPU_REG(RS_NPU_REG_CAPABILITY);
    capability->numeric_profile = RS_NPU_REG(RS_NPU_REG_NUMERIC_PROFILE);
    capability->local_bytes = RS_NPU_REG(RS_NPU_REG_LOCAL_BYTES);
    capability->dense_macs =
        (mac_config & RS_NPU_MAC_CONFIG_DENSE_MASK) >> RS_NPU_MAC_CONFIG_DENSE_SHIFT;
    capability->depthwise_macs =
        (mac_config & RS_NPU_MAC_CONFIG_DEPTHWISE_MASK) >> RS_NPU_MAC_CONFIG_DEPTHWISE_SHIFT;
    capability->max_k_slice = RS_NPU_REG(RS_NPU_REG_MAX_K_SLICE);
    capability->max_dimension = RS_NPU_REG(RS_NPU_REG_MAX_DIMENSION);
    capability->op_mask = RS_NPU_REG(RS_NPU_REG_OP_CAPABILITY);
    if ((ip_id != RS_NPU_IP_ID_VALUE) ||
        ((capability->ip_version & RS_NPU_IP_VERSION_MAJOR_MASK) != RS_NPU_IP_VERSION_MAJOR_1)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

rs_status_t rs_npu_submit(const rs_npu_job_t *job) {
    rs_npu_capability_t capability;
    rs_status_t status;
    uint64_t descriptor_end;

    if (job == NULL) {
        return RS_EINVAL;
    }
    descriptor_end = (uint64_t)job->descriptor_address +
                     ((uint64_t)job->descriptor_count * (uint64_t)RS_NPU_DESCRIPTOR_BYTES);
    if (((job->descriptor_address % RS_NPU_DESCRIPTOR_BASE_ALIGNMENT) != 0U) ||
        (job->descriptor_count == 0U) || (job->descriptor_count > RS_NPU_JOB_COUNT_VALUE_MASK) ||
        (job->timeout_cycles == 0U) || (descriptor_end > UINT64_C(0x100000000))) {
        return RS_EINVAL;
    }
    status = rs_npu_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    /* P2 integrates the register shell without a job execution path: START is never written. */
    return RS_ENOTSUP;
}

rs_status_t rs_npu_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status) {
    rs_status_t result;

    if (status == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    if (!rs_npu_token_known(job_id, RS_NPU_REG(RS_NPU_REG_STATUS))) {
        return RS_EINVAL;
    }
    return rs_npu_wait_terminal(job_id, timeout, status);
}

rs_status_t rs_npu_abort_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status) {
    uint32_t flags;
    rs_status_t result;

    if (status == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    flags = RS_NPU_REG(RS_NPU_REG_STATUS);
    if (!rs_npu_token_known(job_id, flags)) {
        return RS_EINVAL;
    }
    if ((flags & (RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING)) != 0U) {
        rs_npu_fence();
        RS_NPU_REG(RS_NPU_REG_CONTROL) = RS_NPU_CONTROL_ABORT;
    }
    return rs_npu_wait_terminal(job_id, timeout, status);
}

rs_status_t rs_npu_reset(rs_timeout_t timeout) {
    uint32_t polls;
    rs_status_t result;

    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    if (((RS_NPU_REG(RS_NPU_REG_STATUS) &
          (RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING | RS_NPU_STATUS_RECOVERING)) != 0U) ||
        ((RS_NPU_REG(RS_NPU_REG_PERF_STATUS) & RS_NPU_PERF_STATUS_SNAP_BUSY) != 0U)) {
        return RS_EINVAL;
    }
    rs_npu_fence();
    RS_NPU_REG(RS_NPU_REG_CONTROL) = RS_NPU_CONTROL_SOFT_RESET;
    polls = rs_npu_poll_count(timeout);
    while (polls-- != 0U) {
        if ((RS_NPU_REG(RS_NPU_REG_STATUS) &
             (RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING | RS_NPU_STATUS_RECOVERING)) == 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_npu_get_status(rs_npu_status_t *status) {
    rs_status_t result;

    if (status == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    rs_npu_read_status(status);
    return RS_OK;
}

rs_status_t rs_npu_get_error(rs_npu_error_t *error) {
    rs_status_t result;

    if (error == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    error->code = RS_NPU_REG(RS_NPU_REG_FAULT_CODE);
    error->address = RS_NPU_REG(RS_NPU_REG_FAULT_ADDRESS);
    error->descriptor_index = RS_NPU_REG(RS_NPU_REG_FAULT_DESCRIPTOR);
    error->info = RS_NPU_REG(RS_NPU_REG_FAULT_INFO);
    return RS_OK;
}

rs_status_t rs_npu_snapshot_counters(rs_timeout_t timeout, rs_npu_counters_t *counters) {
    uint32_t polls;
    rs_status_t result;

    if (counters == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_shell();
    if (result != RS_OK) {
        return result;
    }
    if ((RS_NPU_REG(RS_NPU_REG_PERF_STATUS) & RS_NPU_PERF_STATUS_SNAP_BUSY) != 0U) {
        return RS_EINVAL;
    }
    RS_NPU_REG(RS_NPU_REG_PERF_CONTROL) = RS_NPU_PERF_CONTROL_SNAPSHOT;
    polls = rs_npu_poll_count(timeout);
    while (polls-- != 0U) {
        const uint32_t perf = RS_NPU_REG(RS_NPU_REG_PERF_STATUS);

        if (((perf & RS_NPU_PERF_STATUS_SNAP_BUSY) == 0U) &&
            ((perf & RS_NPU_PERF_STATUS_SNAP_VALID) != 0U)) {
            counters->job_id = RS_NPU_REG(RS_NPU_REG_PERF_JOB_ID);
            counters->recovery_generation = RS_NPU_REG(RS_NPU_REG_PERF_GENERATION);
            counters->active_cycles = rs_npu_read_counter(RS_NPU_REG_PERF_ACTIVE_CYCLES_LO);
            counters->clock_pause_cycles =
                rs_npu_read_counter(RS_NPU_REG_PERF_CLOCK_PAUSE_CYCLES_LO);
            counters->useful_macs = rs_npu_read_counter(RS_NPU_REG_PERF_USEFUL_MACS_LO);
            counters->pack_cycles = rs_npu_read_counter(RS_NPU_REG_PERF_PACK_CYCLES_LO);
            counters->local_bank_stall_cycles =
                rs_npu_read_counter(RS_NPU_REG_PERF_LOCAL_BANK_STALL_LO);
            counters->dma_read_bytes = rs_npu_read_counter(RS_NPU_REG_PERF_DMA_READ_BYTES_LO);
            counters->dma_write_bytes = rs_npu_read_counter(RS_NPU_REG_PERF_DMA_WRITE_BYTES_LO);
            counters->dma_stall_cycles = rs_npu_read_counter(RS_NPU_REG_PERF_DMA_STALL_CYCLES_LO);
            counters->requant_stall_cycles = rs_npu_read_counter(RS_NPU_REG_PERF_REQUANT_STALL_LO);
            counters->retired_descriptors =
                rs_npu_read_counter(RS_NPU_REG_PERF_RETIRED_DESCRIPTORS_LO);
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_npu_irq_enable(uint32_t events) {
    rs_status_t result;

    if ((events & ~RS_NPU_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    result = rs_npu_require_irq();
    if (result != RS_OK) {
        return result;
    }
    RS_NPU_REG(RS_NPU_REG_IRQ_ENABLE) = events;
    return RS_OK;
}

rs_status_t rs_npu_irq_pending(uint32_t *events) {
    rs_status_t result;

    if (events == NULL) {
        return RS_EINVAL;
    }
    result = rs_npu_require_irq();
    if (result != RS_OK) {
        return result;
    }
    *events = RS_NPU_REG(RS_NPU_REG_IRQ_STATE) & RS_NPU_IRQ_ALL;
    return RS_OK;
}

rs_status_t rs_npu_irq_ack(uint32_t events) {
    rs_status_t result;

    if ((events & ~RS_NPU_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    result = rs_npu_require_irq();
    if (result != RS_OK) {
        return result;
    }
    RS_NPU_REG(RS_NPU_REG_IRQ_STATE) = events;
    return RS_OK;
}

#else

rs_status_t rs_npu_get_capability(rs_npu_capability_t *capability) {
    return (capability == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_submit(const rs_npu_job_t *job) {
    return (job == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status) {
    (void)job_id;
    (void)timeout;
    return (status == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_abort_wait(uint32_t job_id, rs_timeout_t timeout, rs_npu_status_t *status) {
    (void)job_id;
    (void)timeout;
    return (status == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_reset(rs_timeout_t timeout) {
    (void)timeout;
    return RS_ENOTSUP;
}

rs_status_t rs_npu_get_status(rs_npu_status_t *status) {
    return (status == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_get_error(rs_npu_error_t *error) {
    return (error == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_snapshot_counters(rs_timeout_t timeout, rs_npu_counters_t *counters) {
    (void)timeout;
    return (counters == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_irq_enable(uint32_t events) {
    return ((events & ~RS_NPU_IRQ_ALL) != 0U) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_irq_pending(uint32_t *events) {
    return (events == NULL) ? RS_EINVAL : RS_ENOTSUP;
}

rs_status_t rs_npu_irq_ack(uint32_t events) {
    return ((events & ~RS_NPU_IRQ_ALL) != 0U) ? RS_EINVAL : RS_ENOTSUP;
}

#endif
