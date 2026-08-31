#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/jpeg.h>

static uint32_t rs_jpeg_job_config(const rs_jpeg_job_t *job) {
    uint32_t config = (uint32_t)job->table_context << RS_JPEG_JOB_CONFIG_TABLE_SHIFT;

    if (job->mode == RS_JPEG_MODE_ENCODE) {
        config |= RS_JPEG_JOB_CONFIG_ENCODE;
    }
    if (job->auto_header) {
        config |= RS_JPEG_JOB_CONFIG_AUTO_HEADER;
    }
    if (job->strict) {
        config |= RS_JPEG_JOB_CONFIG_STRICT;
    }
    if (job->metadata_length != 0U) {
        config |= RS_JPEG_JOB_CONFIG_METADATA;
    }
    return config;
}

static uint64_t rs_jpeg_read_cycles(void) {
    uint32_t high_before;
    uint32_t high_after;
    uint32_t low;

    do {
        high_before = RS_JPEG_REG(RS_JPEG_REG_CYCLES_HI);
        low = RS_JPEG_REG(RS_JPEG_REG_CYCLES_LO);
        high_after = RS_JPEG_REG(RS_JPEG_REG_CYCLES_HI);
    } while (high_before != high_after);
    return ((uint64_t)high_after << 32U) | (uint64_t)low;
}

rs_status_t rs_jpeg_configure(const rs_jpeg_job_t *job) {
    uint32_t encode_config;

    if (rs_jpeg_job_validate(job) != RS_OK) {
        return RS_EINVAL;
    }
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }

    encode_config = (uint32_t)job->quality | ((uint32_t)job->sampling << 8U);
    RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) = RS_JPEG_IRQ_ALL;
    RS_JPEG_REG(RS_JPEG_REG_ERROR_STATUS) = UINT32_C(1);
    RS_JPEG_REG(RS_JPEG_REG_JOB_CONFIG) = rs_jpeg_job_config(job);
    RS_JPEG_REG(RS_JPEG_REG_IMAGE_SIZE) = ((uint32_t)job->height << 16U) | (uint32_t)job->width;
    RS_JPEG_REG(RS_JPEG_REG_INPUT_FORMAT) = (uint32_t)job->input_format;
    RS_JPEG_REG(RS_JPEG_REG_OUTPUT_FORMAT) = (uint32_t)job->output_format;
    RS_JPEG_REG(RS_JPEG_REG_ENCODE_CONFIG) = encode_config;
    RS_JPEG_REG(RS_JPEG_REG_RESTART_INTERVAL) = (uint32_t)job->restart_interval;
    RS_JPEG_REG(RS_JPEG_REG_BITSTREAM_ADDR) = (uint32_t)job->bitstream;
    RS_JPEG_REG(RS_JPEG_REG_BITSTREAM_SIZE) = job->bitstream_size;
    RS_JPEG_REG(RS_JPEG_REG_PLANE0_ADDR) = (uint32_t)job->planes[0];
    RS_JPEG_REG(RS_JPEG_REG_PLANE0_STRIDE) = job->strides[0];
    RS_JPEG_REG(RS_JPEG_REG_PLANE1_ADDR) = (uint32_t)job->planes[1];
    RS_JPEG_REG(RS_JPEG_REG_PLANE1_STRIDE) = job->strides[1];
    RS_JPEG_REG(RS_JPEG_REG_PLANE2_ADDR) = (uint32_t)job->planes[2];
    RS_JPEG_REG(RS_JPEG_REG_PLANE2_STRIDE) = job->strides[2];
    RS_JPEG_REG(RS_JPEG_REG_METADATA_ADDR) = (uint32_t)job->metadata;
    RS_JPEG_REG(RS_JPEG_REG_METADATA_LENGTH) = job->metadata_length;
    return RS_OK;
}

rs_status_t rs_jpeg_start(void) {
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) = RS_JPEG_IRQ_JOB_DONE | RS_JPEG_IRQ_ERROR;
    RS_JPEG_REG(RS_JPEG_REG_COMMAND) = RS_JPEG_COMMAND_START;
    return RS_OK;
}

rs_status_t rs_jpeg_wait(rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        const uint32_t irq_state = RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE);

        if ((irq_state & RS_JPEG_IRQ_ERROR) != 0U) {
            return RS_EIO;
        }
        if ((irq_state & RS_JPEG_IRQ_JOB_DONE) != 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_jpeg_abort(rs_timeout_t timeout) {
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) == 0U) {
        return RS_EINVAL;
    }
    RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) = RS_JPEG_IRQ_ABORT_DONE;
    RS_JPEG_REG(RS_JPEG_REG_COMMAND) = RS_JPEG_COMMAND_ABORT;
    while (timeout-- != 0U) {
        if ((RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) & RS_JPEG_IRQ_ABORT_DONE) != 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_jpeg_get_status(rs_jpeg_status_t *status) {
    uint32_t flags;
    uint32_t image_size;

    if (status == NULL) {
        return RS_EINVAL;
    }
    flags = RS_JPEG_REG(RS_JPEG_REG_STATUS);
    image_size = RS_JPEG_REG(RS_JPEG_REG_RESULT_IMAGE_SIZE);
    status->busy = (flags & RS_JPEG_STATUS_BUSY) != 0U;
    status->ring_active = (flags & RS_JPEG_STATUS_RING_ACTIVE) != 0U;
    status->encode = (flags & RS_JPEG_STATUS_ENCODE) != 0U;
    status->irq_state = RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE);
    status->error_status = RS_JPEG_REG(RS_JPEG_REG_ERROR_STATUS);
    status->error_address = (uintptr_t)RS_JPEG_REG(RS_JPEG_REG_ERROR_ADDRESS);
    status->result_size = RS_JPEG_REG(RS_JPEG_REG_RESULT_SIZE);
    status->result_width = (uint16_t)image_size;
    status->result_height = (uint16_t)(image_size >> 16U);
    status->cycles = rs_jpeg_read_cycles();
    status->input_bytes = RS_JPEG_REG(RS_JPEG_REG_INPUT_BYTES);
    status->output_bytes = RS_JPEG_REG(RS_JPEG_REG_OUTPUT_BYTES);
    return RS_OK;
}

rs_status_t rs_jpeg_irq_enable(uint32_t mask) {
    if ((mask & ~RS_JPEG_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    RS_JPEG_REG(RS_JPEG_REG_IRQ_ENABLE) = mask;
    return RS_OK;
}

rs_status_t rs_jpeg_irq_pending(uint32_t *mask) {
    if (mask == NULL) {
        return RS_EINVAL;
    }
    *mask = RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) & RS_JPEG_IRQ_ALL;
    return RS_OK;
}

rs_status_t rs_jpeg_irq_clear(uint32_t mask) {
    if ((mask & ~RS_JPEG_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    RS_JPEG_REG(RS_JPEG_REG_IRQ_STATE) = mask;
    return RS_OK;
}

rs_status_t rs_jpeg_table_write(uint8_t context, uint8_t kind, uint8_t index, uint32_t value) {
    if ((context > 3U) || (kind > 11U) ||
        (((kind < 4U) && (index >= 64U)) || ((kind >= 4U) && (kind < 8U) && (index >= 12U)))) {
        return RS_EINVAL;
    }
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_JPEG_REG(RS_JPEG_REG_TABLE_CONTEXT) = (uint32_t)context;
    RS_JPEG_REG(RS_JPEG_REG_TABLE_KIND) = (uint32_t)kind;
    RS_JPEG_REG(RS_JPEG_REG_TABLE_INDEX) = (uint32_t)index;
    RS_JPEG_REG(RS_JPEG_REG_TABLE_DATA) = value;
    return RS_OK;
}

rs_status_t rs_jpeg_table_commit(uint8_t context) {
    uint32_t status;

    if (context > 3U) {
        return RS_EINVAL;
    }
    RS_JPEG_REG(RS_JPEG_REG_TABLE_CONTEXT) = (uint32_t)context;
    RS_JPEG_REG(RS_JPEG_REG_TABLE_COMMAND) = RS_JPEG_TABLE_COMMAND_COMMIT;
    status = RS_JPEG_REG(RS_JPEG_REG_TABLE_STATUS);
    return ((status & (RS_JPEG_TABLE_STATUS_VALID | RS_JPEG_TABLE_STATUS_ERROR)) ==
            RS_JPEG_TABLE_STATUS_VALID)
               ? RS_OK
               : RS_EIO;
}

rs_status_t rs_jpeg_table_clear(uint8_t context) {
    if (context > 3U) {
        return RS_EINVAL;
    }
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_JPEG_REG(RS_JPEG_REG_TABLE_CONTEXT) = (uint32_t)context;
    RS_JPEG_REG(RS_JPEG_REG_TABLE_COMMAND) = RS_JPEG_TABLE_COMMAND_CLEAR;
    return RS_OK;
}

rs_status_t rs_jpeg_ring_init(rs_jpeg_descriptor_t *ring, uint32_t entries) {
    if (rs_jpeg_ring_validate(ring, entries) != RS_OK) {
        return RS_EINVAL;
    }
    if ((RS_JPEG_REG(RS_JPEG_REG_STATUS) & RS_JPEG_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_JPEG_REG(RS_JPEG_REG_COMMAND) = RS_JPEG_COMMAND_SOFT_RESET;
    RS_JPEG_REG(RS_JPEG_REG_RING_BASE) = (uint32_t)(uintptr_t)ring;
    RS_JPEG_REG(RS_JPEG_REG_RING_SIZE) = entries;
    RS_JPEG_REG(RS_JPEG_REG_RING_TAIL) = 0U;
    RS_JPEG_REG(RS_JPEG_REG_RING_CONTROL) = RS_JPEG_RING_CONTROL_ENABLE;
    return RS_OK;
}

rs_status_t rs_jpeg_ring_submit(uint32_t tail) {
    const uint32_t entries = RS_JPEG_REG(RS_JPEG_REG_RING_SIZE);

    if ((entries < 2U) || (tail >= entries)) {
        return RS_EINVAL;
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
    RS_JPEG_REG(RS_JPEG_REG_RING_TAIL) = tail;
    RS_JPEG_REG(RS_JPEG_REG_DOORBELL) = UINT32_C(1);
    return RS_OK;
}
