#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/apu.h>

#if defined(RS_APU_TEST_MMIO)
extern volatile uint32_t rs_apu_test_mmio[1024];
#undef RS_APU_REG
#define RS_APU_REG(offset) rs_apu_test_mmio[(offset) / 4U]
#endif

static uint32_t rs_apu_direct_cookie[2];
static uint32_t rs_apu_ring_collected[8];

static void rs_apu_fence(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

static uint32_t rs_apu_poll_count(rs_timeout_t timeout) {
    return (timeout == 0U) ? 1U : timeout;
}

static uint32_t rs_apu_bit(uint32_t value, uint32_t bit) {
    return (value >> bit) & 1U;
}

static uint32_t rs_apu_owner_unblocked(void) {
    const uint32_t owner = RS_APU_REG(RS_APU_ABI_OWNER_STATUS);

    return (((owner & UINT32_C(3)) <= 1U) &&
            (rs_apu_bit(owner, RS_APU_ABI_OWNER_STATUS_QUIESCE) == 0U) &&
            (rs_apu_bit(owner, RS_APU_ABI_OWNER_STATUS_RESET) == 0U))
               ? 1U
               : 0U;
}

static uint32_t rs_apu_lp_quiesced(void) {
    const uint32_t owner = RS_APU_REG(RS_APU_ABI_OWNER_STATUS);

    return (((owner & UINT32_C(3)) == 0U) &&
            (rs_apu_bit(owner, RS_APU_ABI_OWNER_STATUS_QUIESCE) != 0U) &&
            (rs_apu_bit(owner, RS_APU_ABI_OWNER_STATUS_RESET) == 0U))
               ? 1U
               : 0U;
}

static uint32_t rs_apu_range_in_acl(uint32_t address, uint32_t bytes, uint32_t base,
                                    uint32_t limit) {
    const uint64_t last = (uint64_t)address + (uint64_t)bytes - 1U;

    return ((bytes != 0U) && (address >= base) && (last <= (uint64_t)limit)) ? 1U : 0U;
}

static uint32_t rs_apu_capability_available(const rs_apu_job_t *job) {
    const uint32_t capability = RS_APU_REG(RS_APU_ABI_CAPABILITY0);
    const uint32_t format_bit =
        (job->format == RS_APU_WAV) ? RS_APU_ABI_CAPABILITY0_WAV : RS_APU_ABI_CAPABILITY0_FLAC;

    if (rs_apu_bit(capability, format_bit) == 0U) {
        return 0U;
    }
    if ((job->output == RS_APU_I2S) &&
        (rs_apu_bit(capability, RS_APU_ABI_CAPABILITY0_STREAMS) == 0U)) {
        return 0U;
    }
    if ((job->resample != 0U) && (rs_apu_bit(capability, RS_APU_ABI_CAPABILITY0_RESAMPLER) == 0U)) {
        return 0U;
    }
    return 1U;
}

static rs_status_t rs_apu_check_job_hardware(const rs_apu_job_t *job) {
    uint32_t read_base;
    uint32_t read_limit;

    if (rs_apu_capability_available(job) == 0U) {
        return RS_ENOTSUP;
    }
    if ((rs_apu_owner_unblocked() == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_MC_STATUS), RS_APU_ABI_MC_STATUS_VALID) == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_MC_LOCK), RS_APU_ABI_MC_LOCK_LOCKED) == 0U)) {
        return RS_EINVAL;
    }
    read_base = RS_APU_REG(RS_APU_ABI_READ_BASE);
    read_limit = RS_APU_REG(RS_APU_ABI_READ_LIMIT);
    if (rs_apu_range_in_acl(job->input_address, job->input_bytes, read_base, read_limit) == 0U) {
        return RS_EINVAL;
    }
    if (job->output == RS_APU_MEMORY) {
        const uint32_t write_base = RS_APU_REG(RS_APU_ABI_WRITE_BASE);
        const uint32_t write_limit = RS_APU_REG(RS_APU_ABI_WRITE_LIMIT);

        if (rs_apu_range_in_acl(job->output_address, job->output_capacity, write_base,
                                write_limit) == 0U) {
            return RS_EINVAL;
        }
    }
    return RS_OK;
}

static uint32_t rs_apu_slot_collected(uint32_t slot) {
    return (rs_apu_ring_collected[slot >> 5U] >> (slot & 31U)) & 1U;
}

static void rs_apu_set_slot_collected(uint32_t slot, uint32_t collected) {
    const uint32_t mask = UINT32_C(1) << (slot & 31U);

    if (collected != 0U) {
        rs_apu_ring_collected[slot >> 5U] |= mask;
    } else {
        rs_apu_ring_collected[slot >> 5U] &= ~mask;
    }
}

static uint32_t rs_apu_control(const rs_apu_job_t *job, uint32_t ioc, uint32_t own) {
    return ((uint32_t)job->format << RS_APU_ABI_DESCRIPTOR_CONTROL_INPUT_FORMAT) |
           ((uint32_t)job->output << RS_APU_ABI_DESCRIPTOR_CONTROL_OUTPUT_MODE) |
           (job->downmix << RS_APU_ABI_DESCRIPTOR_CONTROL_DOWNMIX) |
           (job->resample << RS_APU_ABI_DESCRIPTOR_CONTROL_RESAMPLE) |
           (ioc << RS_APU_ABI_DESCRIPTOR_CONTROL_IOC) | (own << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
}

static uint32_t rs_apu_input_config(const rs_apu_job_t *job) {
    return job->expected_rate | (job->expected_channels << 17U) | (job->expected_bits << 20U);
}

static uint32_t rs_apu_output_config(const rs_apu_job_t *job) {
    return job->output_rate | (job->output_channels << 17U) | ((uint32_t)job->pcm << 19U);
}

static rs_status_t rs_apu_terminal_status(uint32_t status, uint32_t detail) {
    const uint32_t code = (status >> RS_APU_ABI_JOB_STATUS_ERROR_CODE) & UINT32_C(0x3F);

    if ((status & (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE)) != 0U) {
        return RS_OK;
    }
    if (code == RS_APU_ABI_ERROR_CODE_UNSUPPORTED) {
        return RS_ENOTSUP;
    }
    if ((code >= RS_APU_ABI_ERROR_CODE_MALFORMED) && (code <= RS_APU_ABI_ERROR_CODE_DECODE)) {
        return RS_EFORMAT;
    }
    if ((detail & UINT32_C(0xFFFF)) == UINT32_C(0x0051)) {
        return RS_ENOSPC;
    }
    return RS_EIO;
}

static void rs_apu_read_error(rs_apu_error_t *error) {
    error->status = RS_APU_REG(RS_APU_ABI_ERROR_STATUS);
    error->address = RS_APU_REG(RS_APU_ABI_ERROR_ADDRESS);
    error->detail = RS_APU_REG(RS_APU_ABI_ERROR_DETAIL);
}

static void rs_apu_descriptor_fill(rs_apu_descriptor_t *descriptor, const rs_apu_job_t *job,
                                   uint32_t ioc) {
    *descriptor = (rs_apu_descriptor_t){0};
    descriptor->control = rs_apu_control(job, ioc, 0U);
    descriptor->input_address = job->input_address;
    descriptor->input_length = job->input_bytes;
    descriptor->output_address = job->output_address;
    descriptor->output_capacity = job->output_capacity;
    descriptor->input_config = rs_apu_input_config(job);
    descriptor->output_config = rs_apu_output_config(job);
    descriptor->job_flags = job->strict;
    descriptor->cookie[0] = job->cookie[0];
    descriptor->cookie[1] = job->cookie[1];
}

static void rs_apu_result_from_descriptor(const rs_apu_descriptor_t *descriptor,
                                          rs_apu_result_t *result) {
    result->status = descriptor->result_status;
    result->input_used = descriptor->result_input_used;
    result->output_bytes = descriptor->result_output_bytes;
    result->frames = descriptor->result_frames;
    result->source_info = descriptor->result_source_info;
    result->cycles = descriptor->result_cycles;
    result->detail = descriptor->result_detail;
    result->cookie[0] = descriptor->cookie[0];
    result->cookie[1] = descriptor->cookie[1];
    result->start_timestamp[0] = descriptor->start_timestamp[0];
    result->start_timestamp[1] = descriptor->start_timestamp[1];
    result->finish_timestamp[0] = descriptor->finish_timestamp[0];
    result->finish_timestamp[1] = descriptor->finish_timestamp[1];
    result->microcode_build_id = descriptor->microcode_build_id;
    rs_apu_read_error(&result->first_error);
}

rs_status_t rs_apu_probe(rs_apu_info_t *info) {
    if (info == NULL) {
        return RS_EINVAL;
    }
    info->ip_id = RS_APU_REG(RS_APU_ABI_IP_ID);
    info->version = RS_APU_REG(RS_APU_ABI_IP_VERSION);
    info->capability0 = RS_APU_REG(RS_APU_ABI_CAPABILITY0);
    info->capability1 = RS_APU_REG(RS_APU_ABI_CAPABILITY1);
    info->abi_digest = RS_APU_REG(RS_APU_ABI_ABI_DIGEST);
    if ((info->ip_id != RS_APU_IP_ID_VALUE) ||
        ((info->version & RS_APU_IP_VERSION_MAJOR_MASK) != RS_APU_IP_VERSION_VALUE)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

rs_status_t rs_apu_set_acl(uint32_t read_base, uint32_t read_limit, uint32_t write_base,
                           uint32_t write_limit) {
    if ((read_base > read_limit) || (write_base > write_limit) || (rs_apu_lp_quiesced() == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_STATUS), RS_APU_ABI_STATUS_IDLE) == 0U)) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_READ_BASE) = read_base;
    RS_APU_REG(RS_APU_ABI_READ_LIMIT) = read_limit;
    RS_APU_REG(RS_APU_ABI_WRITE_BASE) = write_base;
    RS_APU_REG(RS_APU_ABI_WRITE_LIMIT) = write_limit;
    return RS_OK;
}

rs_status_t rs_apu_microcode_load(const rs_apu_image_t *image, rs_timeout_t timeout) {
    uint32_t polls;
    uint32_t read_base;
    uint32_t read_limit;

    if ((image == NULL) || ((image->address & UINT32_C(63)) != 0U) || (image->bytes == 0U) ||
        (image->address > (UINT32_MAX - (image->bytes - 1U)))) {
        return RS_EINVAL;
    }
    read_base = RS_APU_REG(RS_APU_ABI_READ_BASE);
    read_limit = RS_APU_REG(RS_APU_ABI_READ_LIMIT);
    if ((rs_apu_lp_quiesced() == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_STATUS), RS_APU_ABI_STATUS_IDLE) == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_MC_LOCK), RS_APU_ABI_MC_LOCK_LOCKED) != 0U) ||
        (rs_apu_range_in_acl(image->address, image->bytes, read_base, read_limit) == 0U)) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_MC_IMAGE_ADDRESS) = image->address;
    RS_APU_REG(RS_APU_ABI_MC_IMAGE_SIZE) = image->bytes;
    RS_APU_REG(RS_APU_ABI_MC_EXPECTED_CRC) = image->expected_crc;
    RS_APU_REG(RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_MICROCODE_LOAD;
    polls = rs_apu_poll_count(timeout);
    while (polls-- != 0U) {
        const uint32_t status = RS_APU_REG(RS_APU_ABI_MC_STATUS);

        if ((status & (UINT32_C(1) << RS_APU_ABI_MC_STATUS_BUSY)) == 0U) {
            if ((status & (UINT32_C(1) << RS_APU_ABI_MC_STATUS_VALID)) != 0U &&
                RS_APU_REG(RS_APU_ABI_MC_LOCK) != 0U &&
                RS_APU_REG(RS_APU_ABI_MC_ACTUAL_CRC) == image->expected_crc) {
                return RS_OK;
            }
            return RS_EFORMAT;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_apu_validate_job(const rs_apu_job_t *job) {
    uint64_t input_end;
    uint64_t output_end;

    if (job == NULL) {
        return RS_EINVAL;
    }
    if ((job->format != RS_APU_WAV) && (job->format != RS_APU_FLAC)) {
        return RS_ENOTSUP;
    }
    if (((uint32_t)job->output > (uint32_t)RS_APU_I2S) ||
        ((uint32_t)job->pcm > (uint32_t)RS_APU_S24_32) || (job->downmix > 1U) ||
        (job->resample > 1U) || (job->strict > 1U) || ((job->input_address & 3U) != 0U) ||
        (job->input_bytes == 0U) || (job->input_bytes > UINT32_C(0x7FFFFFFF))) {
        return RS_EINVAL;
    }
    input_end = (uint64_t)job->input_address + (uint64_t)job->input_bytes;
    output_end = (uint64_t)job->output_address + (uint64_t)job->output_capacity;
    if (input_end > ((uint64_t)UINT32_MAX + 1U)) {
        return RS_EINVAL;
    }
    if ((job->expected_rate != 0U) &&
        ((job->expected_rate < 8000U) || (job->expected_rate > 96000U))) {
        return RS_ENOTSUP;
    }
    if ((job->expected_channels > 2U) ||
        ((job->expected_bits != 0U) && (job->expected_bits != 8U) && (job->expected_bits != 16U) &&
         (job->expected_bits != 24U) && (job->expected_bits != 32U)) ||
        (job->output_channels > 2U) ||
        ((job->output_rate != 0U) && ((job->output_rate < 8000U) || (job->output_rate > 96000U))) ||
        ((job->format == RS_APU_FLAC) && (job->expected_bits != 0U) &&
         (job->expected_bits != 16U) && (job->expected_bits != 24U))) {
        return RS_ENOTSUP;
    }
    if (job->resample != 0U) {
        if ((job->output_rate != 48000U) && (job->output_rate != 96000U)) {
            return RS_ENOTSUP;
        }
    } else if ((job->output_rate != 0U) && (job->expected_rate != 0U) &&
               (job->output_rate != job->expected_rate)) {
        return RS_ENOTSUP;
    }
    if ((job->downmix != 0U) && ((job->expected_channels == 1U) || (job->output_channels != 1U))) {
        return RS_ENOTSUP;
    }
    if ((job->downmix == 0U) && (job->expected_channels == 2U) && (job->output_channels == 1U)) {
        return RS_ENOTSUP;
    }
    if (job->output == RS_APU_MEMORY) {
        if (((job->output_address & 3U) != 0U) || (job->output_capacity == 0U) ||
            (output_end > ((uint64_t)UINT32_MAX + 1U)) ||
            !((input_end <= (uint64_t)job->output_address) ||
              (output_end <= (uint64_t)job->input_address))) {
            return RS_EINVAL;
        }
    } else if ((job->output_address != 0U) || (job->output_capacity != 0U) ||
               ((job->output_rate != 48000U) && (job->output_rate != 96000U))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_apu_submit_direct(const rs_apu_job_t *job) {
    rs_status_t status = rs_apu_validate_job(job);

    if (status != RS_OK) {
        return status;
    }
    status = rs_apu_check_job_hardware(job);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_apu_bit(RS_APU_REG(RS_APU_ABI_STATUS), RS_APU_ABI_STATUS_IDLE) == 0U) ||
        (RS_APU_REG(RS_APU_ABI_RING_CONTROL) != 0U)) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_JOB_CONTROL) = rs_apu_control(job, 0U, 0U);
    RS_APU_REG(RS_APU_ABI_JOB_INPUT_ADDRESS) = job->input_address;
    RS_APU_REG(RS_APU_ABI_JOB_INPUT_LENGTH) = job->input_bytes;
    RS_APU_REG(RS_APU_ABI_JOB_OUTPUT_ADDRESS) = job->output_address;
    RS_APU_REG(RS_APU_ABI_JOB_OUTPUT_CAPACITY) = job->output_capacity;
    RS_APU_REG(RS_APU_ABI_JOB_INPUT_CONFIG) = rs_apu_input_config(job);
    RS_APU_REG(RS_APU_ABI_JOB_OUTPUT_CONFIG) = rs_apu_output_config(job);
    RS_APU_REG(RS_APU_ABI_JOB_FLAGS) = job->strict;
    rs_apu_direct_cookie[0] = job->cookie[0];
    rs_apu_direct_cookie[1] = job->cookie[1];
    rs_apu_fence();
    RS_APU_REG(RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_START_DIRECT;
    return RS_OK;
}

rs_status_t rs_apu_wait_direct(rs_apu_result_t *result, rs_timeout_t timeout) {
    uint32_t polls = rs_apu_poll_count(timeout);

    if (result == NULL) {
        return RS_EINVAL;
    }
    while (polls-- != 0U) {
        const uint32_t status = RS_APU_REG(RS_APU_ABI_JOB_STATUS);

        if ((status & ((UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE) |
                       (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ERROR) |
                       (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ABORTED))) != 0U) {
            result->status =
                ((status >> RS_APU_ABI_JOB_STATUS_DONE) & 1U) |
                (((status >> RS_APU_ABI_JOB_STATUS_ERROR) & 1U) << 1U) |
                (((status >> RS_APU_ABI_JOB_STATUS_ABORTED) & 1U) << 2U) |
                (((status >> RS_APU_ABI_JOB_STATUS_ERROR_CODE) & UINT32_C(0x3F)) << 3U) |
                (((status >> RS_APU_ABI_JOB_STATUS_STAGE) & UINT32_C(0xF)) << 9U) |
                (((status >> RS_APU_ABI_JOB_STATUS_AXI_RESPONSE) & UINT32_C(3)) << 13U);
            result->input_used = RS_APU_REG(RS_APU_ABI_JOB_INPUT_USED);
            result->output_bytes = RS_APU_REG(RS_APU_ABI_JOB_OUTPUT_BYTES);
            result->frames = RS_APU_REG(RS_APU_ABI_JOB_FRAMES);
            result->source_info = RS_APU_REG(RS_APU_ABI_JOB_SOURCE_INFO);
            result->cycles = RS_APU_REG(RS_APU_ABI_JOB_CYCLES);
            result->detail = RS_APU_REG(RS_APU_ABI_JOB_DETAIL);
            result->cookie[0] = rs_apu_direct_cookie[0];
            result->cookie[1] = rs_apu_direct_cookie[1];
            result->start_timestamp[0] = 0U;
            result->start_timestamp[1] = 0U;
            result->finish_timestamp[0] = 0U;
            result->finish_timestamp[1] = 0U;
            result->microcode_build_id = RS_APU_REG(RS_APU_ABI_MC_BUILD_ID_LO);
            rs_apu_read_error(&result->first_error);
            return rs_apu_terminal_status(status, result->detail);
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_apu_decode(const rs_apu_job_t *job, rs_apu_result_t *result, rs_timeout_t timeout) {
    const rs_status_t status = rs_apu_submit_direct(job);

    return (status == RS_OK) ? rs_apu_wait_direct(result, timeout) : status;
}

rs_status_t rs_apu_ring_configure(rs_apu_ring_t *ring, uint32_t stop_on_error,
                                  uint32_t coalesce_count, uint32_t coalesce_timeout) {
    uint32_t descriptor_bytes;

    if ((ring == NULL) || (ring->descriptors == NULL) || (ring->entries < 2U) ||
        (ring->entries > 256U) || ((ring->entries & (ring->entries - 1U)) != 0U) ||
        (((uintptr_t)ring->descriptors & UINT32_C(127)) != 0U) ||
        ((ring->dma_address & UINT32_C(127)) != 0U) || (stop_on_error > 1U) ||
        (coalesce_count == 0U) || (coalesce_count > 255U) || (coalesce_timeout == 0U) ||
        (coalesce_timeout > 65535U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_STATUS), RS_APU_ABI_STATUS_IDLE) == 0U) ||
        (RS_APU_REG(RS_APU_ABI_RING_CONTROL) != 0U) || (rs_apu_owner_unblocked() == 0U)) {
        return RS_EINVAL;
    }
    descriptor_bytes = ring->entries * RS_APU_ABI_DESCRIPTOR_BYTES;
    if ((rs_apu_range_in_acl(ring->dma_address, descriptor_bytes, RS_APU_REG(RS_APU_ABI_READ_BASE),
                             RS_APU_REG(RS_APU_ABI_READ_LIMIT)) == 0U) ||
        (rs_apu_range_in_acl(ring->dma_address, descriptor_bytes, RS_APU_REG(RS_APU_ABI_WRITE_BASE),
                             RS_APU_REG(RS_APU_ABI_WRITE_LIMIT)) == 0U)) {
        return RS_EINVAL;
    }
    for (uint32_t slot = 0U; slot < ring->entries; ++slot) {
        if ((ring->descriptors[slot].control &
             (UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN)) != 0U) {
            return RS_EINVAL;
        }
    }
    ring->tail = 0U;
    for (uint32_t word = 0U; word < 8U; ++word) {
        rs_apu_ring_collected[word] = 0U;
    }
    for (uint32_t slot = 0U; slot < ring->entries; ++slot) {
        rs_apu_set_slot_collected(slot, 1U);
    }
    RS_APU_REG(RS_APU_ABI_RING_BASE) = ring->dma_address;
    RS_APU_REG(RS_APU_ABI_RING_SIZE) = ring->entries;
    RS_APU_REG(RS_APU_ABI_RING_COALESCE) = coalesce_count | (coalesce_timeout << 16U);
    RS_APU_REG(RS_APU_ABI_RING_TAIL) = 0U;
    RS_APU_REG(RS_APU_ABI_RING_CONTROL) = UINT32_C(1) | (stop_on_error << 1U);
    return RS_OK;
}

rs_status_t rs_apu_ring_submit(rs_apu_ring_t *ring, const rs_apu_job_t *job, uint32_t ioc,
                               uint32_t *slot) {
    uint32_t next;
    rs_status_t status;

    if ((ring == NULL) || (slot == NULL) || (ioc > 1U) || (ring->descriptors == NULL) ||
        (ring->entries < 2U) || (ring->entries > 256U) ||
        ((ring->entries & (ring->entries - 1U)) != 0U) || (ring->tail >= ring->entries) ||
        (((uintptr_t)ring->descriptors & UINT32_C(127)) != 0U) ||
        ((ring->dma_address & UINT32_C(127)) != 0U)) {
        return RS_EINVAL;
    }
    status = rs_apu_validate_job(job);
    if (status != RS_OK) {
        return status;
    }
    status = rs_apu_check_job_hardware(job);
    if (status != RS_OK) {
        return status;
    }
    if (((RS_APU_REG(RS_APU_ABI_RING_CONTROL) & 1U) == 0U) ||
        (RS_APU_REG(RS_APU_ABI_RING_BASE) != ring->dma_address) ||
        (RS_APU_REG(RS_APU_ABI_RING_SIZE) != ring->entries)) {
        return RS_EINVAL;
    }
    next = (ring->tail + 1U) & (ring->entries - 1U);
    if (next == RS_APU_REG(RS_APU_ABI_RING_HEAD)) {
        return RS_ENOSPC;
    }
    *slot = ring->tail;
    if ((rs_apu_slot_collected(*slot) == 0U) ||
        ((ring->descriptors[*slot].control & (UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN)) !=
         0U)) {
        return RS_ENOSPC;
    }
    rs_apu_descriptor_fill(&ring->descriptors[*slot], job, ioc);
    rs_apu_fence();
    ring->descriptors[*slot].control |= UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN;
    rs_apu_fence();
    rs_apu_set_slot_collected(*slot, 0U);
    ring->tail = next;
    RS_APU_REG(RS_APU_ABI_RING_TAIL) = next;
    RS_APU_REG(RS_APU_ABI_RING_DOORBELL) = UINT32_C(1);
    return RS_OK;
}

rs_status_t rs_apu_ring_result(const rs_apu_ring_t *ring, uint32_t slot, rs_apu_result_t *result,
                               rs_timeout_t timeout) {
    uint32_t polls;

    if ((ring == NULL) || (result == NULL) || (slot >= ring->entries)) {
        return RS_EINVAL;
    }
    polls = rs_apu_poll_count(timeout);
    while (polls-- != 0U) {
        const rs_apu_descriptor_t *const descriptor = &ring->descriptors[slot];

        if ((descriptor->control & (UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN)) == 0U) {
            uint32_t status;

            rs_apu_fence();
            if ((descriptor->result_status & UINT32_C(7)) == 0U) {
                return RS_EINVAL;
            }
            rs_apu_result_from_descriptor(descriptor, result);
            status = ((descriptor->result_status & 1U) << RS_APU_ABI_JOB_STATUS_DONE) |
                     (((descriptor->result_status >> 1U) & 1U) << RS_APU_ABI_JOB_STATUS_ERROR) |
                     (((descriptor->result_status >> 2U) & 1U) << RS_APU_ABI_JOB_STATUS_ABORTED) |
                     (((descriptor->result_status >> 3U) & UINT32_C(0x3F))
                      << RS_APU_ABI_JOB_STATUS_ERROR_CODE);
            rs_apu_set_slot_collected(slot, 1U);
            return rs_apu_terminal_status(status, descriptor->result_detail);
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_apu_abort(rs_timeout_t timeout) {
    uint32_t polls;

    if ((RS_APU_REG(RS_APU_ABI_STATUS) & (UINT32_C(1) << RS_APU_ABI_STATUS_IDLE)) != 0U) {
        return RS_OK;
    }
    RS_APU_REG(RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_ABORT;
    polls = rs_apu_poll_count(timeout);
    while (polls-- != 0U) {
        if ((RS_APU_REG(RS_APU_ABI_STATUS) & (UINT32_C(1) << RS_APU_ABI_STATUS_IDLE)) != 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_apu_ring_disable(rs_timeout_t timeout) {
    rs_status_t status = RS_OK;

    if ((rs_apu_bit(RS_APU_REG(RS_APU_ABI_STATUS), RS_APU_ABI_STATUS_IDLE) == 0U) ||
        (rs_apu_bit(RS_APU_REG(RS_APU_ABI_RING_STATUS), RS_APU_ABI_RING_STATUS_ACTIVE) != 0U)) {
        status = rs_apu_abort(timeout);
    }
    if (status == RS_OK) {
        RS_APU_REG(RS_APU_ABI_RING_CONTROL) = 0U;
        for (uint32_t word = 0U; word < 8U; ++word) {
            rs_apu_ring_collected[word] = 0U;
        }
    }
    return status;
}

rs_status_t rs_apu_stream_route(uint32_t tx_route, uint32_t rx_route) {
    const uint32_t status = RS_APU_REG(RS_APU_ABI_STREAM_STATUS);
    const uint32_t capability = RS_APU_REG(RS_APU_ABI_CAPABILITY0);

    if ((tx_route > 1U) || (rx_route != 0U) ||
        ((tx_route == 1U) && (rs_apu_bit(capability, RS_APU_ABI_CAPABILITY0_STREAMS) == 0U)) ||
        (((status & (UINT32_C(1) << RS_APU_ABI_STREAM_STATUS_TX_ACTIVE)) != 0U) &&
         (tx_route != (RS_APU_REG(RS_APU_ABI_STREAM_ROUTE) & 3U)))) {
        return (rx_route != 0U) ? RS_ENOTSUP : RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_STREAM_ROUTE) = tx_route | (rx_route << 2U);
    return RS_OK;
}

rs_status_t rs_apu_soft_reset(void) {
    if ((RS_APU_REG(RS_APU_ABI_STATUS) & (UINT32_C(1) << RS_APU_ABI_STATUS_IDLE)) == 0U) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_SOFT_RESET;
    return RS_OK;
}

rs_status_t rs_apu_error_read(rs_apu_error_t *error) {
    if (error == NULL) {
        return RS_EINVAL;
    }
    rs_apu_read_error(error);
    return RS_OK;
}

rs_status_t rs_apu_error_clear(void) {
    RS_APU_REG(RS_APU_ABI_ERROR_STATUS) = UINT32_C(1);
    return RS_OK;
}

rs_status_t rs_apu_irq_read(uint32_t *state) {
    if (state == NULL) {
        return RS_EINVAL;
    }
    *state = RS_APU_REG(RS_APU_ABI_IRQ_STATE);
    return RS_OK;
}

rs_status_t rs_apu_irq_enable(uint32_t mask) {
    if ((mask & ~RS_APU_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_IRQ_ENABLE) = mask;
    return RS_OK;
}

rs_status_t rs_apu_irq_ack(uint32_t mask) {
    if ((mask & ~RS_APU_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    RS_APU_REG(RS_APU_ABI_IRQ_STATE) = mask;
    return RS_OK;
}
