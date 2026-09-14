#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/ga2d.h>

#if defined(RS_GA2D_TEST_MMIO)
extern volatile uint32_t rs_ga2d_test_mmio[1024];
#undef RS_GA2D_REG
#define RS_GA2D_REG(offset) rs_ga2d_test_mmio[(offset) / 4U]
#endif

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
    if (job == NULL) {
        return RS_EINVAL;
    }
    return RS_ENOTSUP;
}

rs_status_t rs_ga2d_configure(const rs_ga2d_job_t *job) {
    if (job == NULL) {
        return RS_EINVAL;
    }
    return RS_ENOTSUP;
}

rs_status_t rs_ga2d_start(void) {
    return RS_ENOTSUP;
}

rs_status_t rs_ga2d_wait(rs_timeout_t timeout) {
    (void)timeout;
    return RS_ENOTSUP;
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

        if ((status & (RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DRAINING)) == 0U) {
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
    if (stats == NULL) {
        return RS_EINVAL;
    }
    return RS_ENOTSUP;
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
