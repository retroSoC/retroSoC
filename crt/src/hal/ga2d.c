#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/memory.h>
#include <retrosoc/hal/ga2d.h>

#include "ga2d_math.h"

#if defined(RS_GA2D_TEST_MMIO)
extern volatile uint32_t rs_ga2d_test_mmio[1024];
extern uint32_t rs_ga2d_test_mem_pad_mode;
#undef RS_GA2D_REG
#define RS_GA2D_REG(offset) rs_ga2d_test_mmio[(offset) / 4U]
#endif

#define RS_GA2D_MEM_PAD_MODE_MASK UINT32_C(0x00000003)

static void rs_ga2d_fence(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

static uint32_t rs_ga2d_poll_count(rs_timeout_t timeout) {
    return (timeout == 0U) ? 1U : timeout;
}

static uint32_t rs_ga2d_bit(uint32_t value, uint32_t mask) {
    return ((value & mask) != 0U) ? 1U : 0U;
}

static rs_status_t rs_ga2d_require_shell(void) {
    rs_ga2d_capability_t capability;

    return rs_ga2d_get_capability(&capability);
}

static rs_status_t rs_ga2d_require_irq(void) {
    rs_ga2d_capability_t capability;
    rs_status_t status;

    status = rs_ga2d_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    return ((capability.features & RS_GA2D_CAPABILITY_IRQ) != 0U) ? RS_OK : RS_ENOTSUP;
}

static rs_status_t rs_ga2d_require_snapshot(void) {
    rs_ga2d_capability_t capability;
    rs_status_t status;

    status = rs_ga2d_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    return ((capability.features & RS_GA2D_CAPABILITY_SNAPSHOT) != 0U) ? RS_OK : RS_ENOTSUP;
}

static rs_status_t rs_ga2d_require_private_dma(void) {
    rs_ga2d_capability_t capability;
    rs_status_t status;

    status = rs_ga2d_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    return ((capability.features & RS_GA2D_CAPABILITY_PRIVATE_DMA) != 0U) ? RS_OK : RS_ENOTSUP;
}

static rs_status_t rs_ga2d_require_safe_idle(void) {
    const uint32_t status = RS_GA2D_REG(RS_GA2D_REG_STATUS);

    if (((status & (RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DRAINING | RS_GA2D_STATUS_QUIESCED |
                    RS_GA2D_STATUS_RECOVERY_REQUIRED)) != 0U) ||
        ((status & RS_GA2D_STATUS_DATA_READY) == 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

static bool rs_ga2d_address_in_region(uintptr_t address, uint32_t region_base,
                                      uint32_t region_size) {
    const uint64_t base = (uint64_t)address;
    const uint64_t start = (uint64_t)region_base;
    const uint64_t end = start + (uint64_t)region_size;

    return (base >= start) && (base < end);
}

static rs_memory_pad_mode_t rs_ga2d_memory_pad_mode(void) {
#if defined(RS_GA2D_TEST_MMIO)
    return (rs_memory_pad_mode_t)(rs_ga2d_test_mem_pad_mode & RS_GA2D_MEM_PAD_MODE_MASK);
#else
    return (rs_memory_pad_mode_t)(RS_SOC_REG32(RS_SOC_APB4_SYSCTRL_BASE,
                                               RS_SOC_SYSCTRL_MEM_PAD_STATUS_OFFSET) &
                                  RS_GA2D_MEM_PAD_MODE_MASK);
#endif
}

static rs_status_t rs_ga2d_validate_runtime_memory_surface(const rs_ga2d_surface_t *surface) {
    rs_memory_pad_mode_t pad_mode;

    if (!rs_ga2d_address_in_region(surface->address, RS_SOC_PSRAM_BASE, RS_SOC_PSRAM_SIZE) &&
        !rs_ga2d_address_in_region(surface->address, RS_SOC_OPIPSRAM_BASE, RS_SOC_OPIPSRAM_SIZE)) {
        return RS_OK;
    }
    pad_mode = rs_ga2d_memory_pad_mode();
    if (rs_ga2d_address_in_region(surface->address, RS_SOC_PSRAM_BASE, RS_SOC_PSRAM_SIZE)) {
        return (pad_mode == RS_MEMORY_PAD_QPI) ? RS_OK : RS_EINVAL;
    }
    return (pad_mode == RS_MEMORY_PAD_OPI) ? RS_OK : RS_EINVAL;
}

static rs_status_t rs_ga2d_validate_runtime_memory(const rs_ga2d_job_t *job) {
    rs_status_t status;

    status = rs_ga2d_validate_runtime_memory_surface(&job->destination);
    if (status != RS_OK) {
        return status;
    }
    if (job->operation != RS_GA2D_OP_FILL) {
        status = rs_ga2d_validate_runtime_memory_surface(&job->foreground);
        if (status != RS_OK) {
            return status;
        }
    }
    if (job->operation == RS_GA2D_OP_BLEND) {
        return rs_ga2d_validate_runtime_memory_surface(&job->background);
    }
    return RS_OK;
}

static uint64_t rs_ga2d_read_snapshot64(uint32_t low_offset, uint32_t high_offset) {
    return ((uint64_t)RS_GA2D_REG(high_offset) << 32U) | (uint64_t)RS_GA2D_REG(low_offset);
}

rs_status_t rs_ga2d_get_capability(rs_ga2d_capability_t *capability) {
    uint32_t ip_id;

    if (capability == NULL) {
        return RS_EINVAL;
    }
    ip_id = RS_GA2D_REG(RS_GA2D_REG_IP_ID);
    capability->version = RS_GA2D_REG(RS_GA2D_REG_IP_VERSION);
    capability->features = RS_GA2D_REG(RS_GA2D_REG_CAPABILITY);
    capability->limits = RS_GA2D_REG(RS_GA2D_REG_LIMITS);
    capability->formats = RS_GA2D_REG(RS_GA2D_REG_FORMAT_CAPABILITY);
    if ((ip_id != RS_GA2D_IP_ID_VALUE) ||
        ((capability->version & RS_GA2D_IP_VERSION_MAJOR_MASK) != RS_GA2D_IP_VERSION_MAJOR_1)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

rs_status_t rs_ga2d_job_validate(const rs_ga2d_job_t *job) {
    rs_ga2d_capability_t capability;
    rs_status_t status;

    if (job == NULL) {
        return RS_EINVAL;
    }
    status = rs_ga2d_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_job_validate_capability(job, &capability);
    if (status != RS_OK) {
        return status;
    }
    return rs_ga2d_validate_runtime_memory(job);
}

rs_status_t rs_ga2d_configure(const rs_ga2d_job_t *job) {
    rs_ga2d_capability_t capability;
    rs_status_t status;

    if (job == NULL) {
        return RS_EINVAL;
    }
    status = rs_ga2d_get_capability(&capability);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_job_validate_capability(job, &capability);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_validate_runtime_memory(job);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_require_safe_idle();
    if (status != RS_OK) {
        return status;
    }

    RS_GA2D_REG(RS_GA2D_REG_JOB_CONFIG) =
        ((uint32_t)job->operation << RS_GA2D_JOB_CONFIG_OPERATION_SHIFT) &
        RS_GA2D_JOB_CONFIG_OPERATION_MASK;
    RS_GA2D_REG(RS_GA2D_REG_GLOBAL_ALPHA) =
        ((uint32_t)job->global_alpha << RS_GA2D_GLOBAL_ALPHA_VALUE_SHIFT) &
        RS_GA2D_GLOBAL_ALPHA_VALUE_MASK;
    RS_GA2D_REG(RS_GA2D_REG_COLOR) = job->color;
    RS_GA2D_REG(RS_GA2D_REG_SIZE) = ((uint32_t)job->width << RS_GA2D_SIZE_WIDTH_SHIFT) |
                                    ((uint32_t)job->height << RS_GA2D_SIZE_HEIGHT_SHIFT);

    if (job->operation != RS_GA2D_OP_FILL) {
        RS_GA2D_REG(RS_GA2D_REG_FG_ADDRESS) = (uint32_t)job->foreground.address;
        RS_GA2D_REG(RS_GA2D_REG_FG_PITCH) = job->foreground.pitch;
        RS_GA2D_REG(RS_GA2D_REG_FG_FORMAT) =
            ((uint32_t)job->foreground.format << RS_GA2D_FG_FORMAT_VALUE_SHIFT) &
            RS_GA2D_FORMAT_VALUE_MASK;
    } else {
        RS_GA2D_REG(RS_GA2D_REG_FG_ADDRESS) = 0U;
        RS_GA2D_REG(RS_GA2D_REG_FG_PITCH) = 0U;
        RS_GA2D_REG(RS_GA2D_REG_FG_FORMAT) = 0U;
    }
    if (job->operation == RS_GA2D_OP_BLEND) {
        RS_GA2D_REG(RS_GA2D_REG_BG_ADDRESS) = (uint32_t)job->background.address;
        RS_GA2D_REG(RS_GA2D_REG_BG_PITCH) = job->background.pitch;
        RS_GA2D_REG(RS_GA2D_REG_BG_FORMAT) =
            ((uint32_t)job->background.format << RS_GA2D_BG_FORMAT_VALUE_SHIFT) &
            RS_GA2D_FORMAT_VALUE_MASK;
    } else {
        RS_GA2D_REG(RS_GA2D_REG_BG_ADDRESS) = 0U;
        RS_GA2D_REG(RS_GA2D_REG_BG_PITCH) = 0U;
        RS_GA2D_REG(RS_GA2D_REG_BG_FORMAT) = 0U;
    }
    RS_GA2D_REG(RS_GA2D_REG_DST_ADDRESS) = (uint32_t)job->destination.address;
    RS_GA2D_REG(RS_GA2D_REG_DST_PITCH) = job->destination.pitch;
    RS_GA2D_REG(RS_GA2D_REG_DST_FORMAT) =
        ((uint32_t)job->destination.format << RS_GA2D_DST_FORMAT_VALUE_SHIFT) &
        RS_GA2D_FORMAT_VALUE_MASK;
    return RS_OK;
}

rs_status_t rs_ga2d_start(void) {
    rs_status_t status;

    status = rs_ga2d_require_private_dma();
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_require_safe_idle();
    if (status != RS_OK) {
        return status;
    }
    RS_GA2D_REG(RS_GA2D_REG_IRQ_STATE) = RS_GA2D_IRQ_ALL;
    RS_GA2D_REG(RS_GA2D_REG_ERROR_STATUS) = RS_GA2D_ERROR_STATUS_VALID;
    rs_ga2d_fence();
    RS_GA2D_REG(RS_GA2D_REG_COMMAND) = RS_GA2D_COMMAND_START;
    return RS_OK;
}

rs_status_t rs_ga2d_wait(rs_timeout_t timeout) {
    uint32_t polls;
    rs_status_t status;

    status = rs_ga2d_require_private_dma();
    if (status != RS_OK) {
        return status;
    }
    polls = rs_ga2d_poll_count(timeout);
    while (polls-- != 0U) {
        const uint32_t flags = RS_GA2D_REG(RS_GA2D_REG_STATUS);

        if ((flags & (RS_GA2D_STATUS_ERROR | RS_GA2D_STATUS_ABORTED)) != 0U) {
            return RS_EIO;
        }
        if (((flags & RS_GA2D_STATUS_DONE) != 0U) &&
            ((flags & (RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DRAINING)) == 0U)) {
            rs_ga2d_fence();
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_ga2d_abort_wait(rs_timeout_t timeout) {
    uint32_t polls;

    if (rs_ga2d_require_shell() != RS_OK) {
        return RS_ENOTSUP;
    }
    RS_GA2D_REG(RS_GA2D_REG_COMMAND) = RS_GA2D_COMMAND_ABORT;
    polls = rs_ga2d_poll_count(timeout);
    while (polls-- != 0U) {
        const uint32_t status = RS_GA2D_REG(RS_GA2D_REG_STATUS);

        if ((status & RS_GA2D_STATUS_RECOVERY_REQUIRED) != 0U) {
            return RS_EIO;
        }
        if ((status & (RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DRAINING)) == 0U) {
            if (rs_ga2d_require_safe_idle() != RS_OK) {
                return RS_EIO;
            }
            rs_ga2d_fence();
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_ga2d_reset(void) {
    uint32_t status;
    rs_status_t result;

    result = rs_ga2d_require_shell();
    if (result != RS_OK) {
        return result;
    }
    status = RS_GA2D_REG(RS_GA2D_REG_STATUS);
    if ((status & (RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DRAINING | RS_GA2D_STATUS_QUIESCED |
                   RS_GA2D_STATUS_RECOVERY_REQUIRED)) != 0U ||
        (rs_ga2d_bit(status, RS_GA2D_STATUS_DATA_READY) == 0U)) {
        return RS_EIO;
    }
    RS_GA2D_REG(RS_GA2D_REG_COMMAND) = RS_GA2D_COMMAND_SOFT_RESET;
    return RS_OK;
}

rs_status_t rs_ga2d_get_status(rs_ga2d_status_t *status) {
    uint32_t flags;
    rs_status_t result;

    if (status == NULL) {
        return RS_EINVAL;
    }
    result = rs_ga2d_require_shell();
    if (result != RS_OK) {
        return result;
    }
    flags = RS_GA2D_REG(RS_GA2D_REG_STATUS);
    status->busy = rs_ga2d_bit(flags, RS_GA2D_STATUS_BUSY) != 0U;
    status->draining = rs_ga2d_bit(flags, RS_GA2D_STATUS_DRAINING) != 0U;
    status->quiesced = rs_ga2d_bit(flags, RS_GA2D_STATUS_QUIESCED) != 0U;
    status->data_ready = rs_ga2d_bit(flags, RS_GA2D_STATUS_DATA_READY) != 0U;
    status->done = rs_ga2d_bit(flags, RS_GA2D_STATUS_DONE) != 0U;
    status->aborted = rs_ga2d_bit(flags, RS_GA2D_STATUS_ABORTED) != 0U;
    status->error = rs_ga2d_bit(flags, RS_GA2D_STATUS_ERROR) != 0U;
    status->recovery_required = rs_ga2d_bit(flags, RS_GA2D_STATUS_RECOVERY_REQUIRED) != 0U;
    status->irq_state = RS_GA2D_REG(RS_GA2D_REG_IRQ_STATE) & RS_GA2D_IRQ_ALL;
    return RS_OK;
}

rs_status_t rs_ga2d_get_error(rs_ga2d_error_t *error) {
    uint32_t status;
    rs_status_t result;

    if (error == NULL) {
        return RS_EINVAL;
    }
    result = rs_ga2d_require_shell();
    if (result != RS_OK) {
        return result;
    }
    status = RS_GA2D_REG(RS_GA2D_REG_ERROR_STATUS);
    error->valid = rs_ga2d_bit(status, RS_GA2D_ERROR_STATUS_VALID) != 0U;
    error->code =
        (uint8_t)((status & RS_GA2D_ERROR_STATUS_CODE_MASK) >> RS_GA2D_ERROR_STATUS_CODE_SHIFT);
    error->stage =
        (uint8_t)((status & RS_GA2D_ERROR_STATUS_STAGE_MASK) >> RS_GA2D_ERROR_STATUS_STAGE_SHIFT);
    error->axi_response = (uint8_t)((status & RS_GA2D_ERROR_STATUS_AXI_RESPONSE_MASK) >>
                                    RS_GA2D_ERROR_STATUS_AXI_RESPONSE_SHIFT);
    error->address = (uintptr_t)RS_GA2D_REG(RS_GA2D_REG_ERROR_ADDRESS);
    return RS_OK;
}

rs_status_t rs_ga2d_get_stats(rs_ga2d_stats_t *stats) {
    rs_status_t status;

    if (stats == NULL) {
        return RS_EINVAL;
    }
    status = rs_ga2d_require_snapshot();
    if (status != RS_OK) {
        return status;
    }
    RS_GA2D_REG(RS_GA2D_REG_PERF_SNAPSHOT) = UINT32_C(1);
    stats->cycles = rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_CYCLES_LO, RS_GA2D_REG_SNAP_CYCLES_HI);
    stats->read_bytes =
        rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_READ_BYTES_LO, RS_GA2D_REG_SNAP_READ_BYTES_HI);
    stats->write_bytes =
        rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_WRITE_BYTES_LO, RS_GA2D_REG_SNAP_WRITE_BYTES_HI);
    stats->read_stalls =
        rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_READ_STALL_LO, RS_GA2D_REG_SNAP_READ_STALL_HI);
    stats->write_stalls =
        rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_WRITE_STALL_LO, RS_GA2D_REG_SNAP_WRITE_STALL_HI);
    stats->pipe_stalls =
        rs_ga2d_read_snapshot64(RS_GA2D_REG_SNAP_PIPE_STALL_LO, RS_GA2D_REG_SNAP_PIPE_STALL_HI);
    stats->lines_done = (uint16_t)RS_GA2D_REG(RS_GA2D_REG_SNAP_LINES_DONE);
    return RS_OK;
}

rs_status_t rs_ga2d_irq_enable(uint32_t mask) {
    rs_status_t result;

    if ((mask & ~RS_GA2D_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    result = rs_ga2d_require_irq();
    if (result != RS_OK) {
        return result;
    }
    RS_GA2D_REG(RS_GA2D_REG_IRQ_ENABLE) = mask;
    return RS_OK;
}

rs_status_t rs_ga2d_irq_pending(uint32_t *pending) {
    rs_status_t result;

    if (pending == NULL) {
        return RS_EINVAL;
    }
    result = rs_ga2d_require_irq();
    if (result != RS_OK) {
        return result;
    }
    *pending =
        RS_GA2D_REG(RS_GA2D_REG_IRQ_STATE) & RS_GA2D_REG(RS_GA2D_REG_IRQ_ENABLE) & RS_GA2D_IRQ_ALL;
    return RS_OK;
}

rs_status_t rs_ga2d_irq_clear(uint32_t mask) {
    rs_status_t result;

    if ((mask & ~RS_GA2D_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    result = rs_ga2d_require_irq();
    if (result != RS_OK) {
        return result;
    }
    RS_GA2D_REG(RS_GA2D_REG_IRQ_STATE) = mask;
    return RS_OK;
}
