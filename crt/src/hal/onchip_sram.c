#include <stddef.h>

#include <retrosoc/hal/onchip_sram.h>

rs_status_t rs_onchip_sram_probe(rs_onchip_sram_info_t *info) {
    uint32_t capability;
    uint32_t memory_bytes;
    uint32_t bank_count;
    uint32_t bank_bytes;

    if (info == NULL) {
        return RS_EINVAL;
    }
    if ((RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_IP_ID) != RS_ONCHIP_SRAM_IP_ID_VALUE) ||
        (RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_IP_VERSION) != RS_ONCHIP_SRAM_IP_VERSION_VALUE)) {
        return RS_EIO;
    }

    capability = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_CAPABILITY);
    memory_bytes = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_MEMORY_BYTES);
    bank_count = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_BANK_COUNT);
    bank_bytes = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_BANK_BYTES);
    info->capability = capability;
    info->memory_bytes = memory_bytes;
    info->bank_count = bank_count;
    info->bank_bytes = bank_bytes;
    info->max_burst_beats = (uint8_t)((capability & RS_ONCHIP_SRAM_CAP_MAX_BEATS_MASK) >>
                                      RS_ONCHIP_SRAM_CAP_MAX_BEATS_SHIFT);
    info->data_bytes = (uint8_t)((capability & RS_ONCHIP_SRAM_CAP_DATA_BYTES_MASK) >>
                                 RS_ONCHIP_SRAM_CAP_DATA_BYTES_SHIFT);
    info->present = (capability & RS_ONCHIP_SRAM_CAP_PRESENT) != 0U;

    if ((bank_bytes != RS_ONCHIP_SRAM_BANK_BYTES_VALUE) || (info->max_burst_beats != 16U) ||
        ((info->data_bytes != 4U) && (info->data_bytes != 8U)) ||
        ((capability & (RS_ONCHIP_SRAM_CAP_NATIVE_AXI4 | RS_ONCHIP_SRAM_CAP_BYTE_WRITE |
                        RS_ONCHIP_SRAM_CAP_FIXED | RS_ONCHIP_SRAM_CAP_INCR |
                        RS_ONCHIP_SRAM_CAP_WRAP | RS_ONCHIP_SRAM_CAP_PERFORMANCE)) !=
         (RS_ONCHIP_SRAM_CAP_NATIVE_AXI4 | RS_ONCHIP_SRAM_CAP_BYTE_WRITE |
          RS_ONCHIP_SRAM_CAP_FIXED | RS_ONCHIP_SRAM_CAP_INCR | RS_ONCHIP_SRAM_CAP_WRAP |
          RS_ONCHIP_SRAM_CAP_PERFORMANCE))) {
        return RS_EIO;
    }
    if (info->present) {
        if ((memory_bytes != RS_SOC_SRAM_SIZE) ||
            (bank_count != (memory_bytes / RS_ONCHIP_SRAM_BANK_BYTES_VALUE)) ||
            (bank_count == 0U)) {
            return RS_EIO;
        }
    } else if ((memory_bytes != 0U) || (bank_count != 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_onchip_sram_read_performance(rs_onchip_sram_perf_t *performance) {
    if (performance == NULL) {
        return RS_EINVAL;
    }
    performance->read_requests = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_READ_REQUESTS);
    performance->write_requests = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_WRITE_REQUESTS);
    performance->read_beats = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_READ_BEATS);
    performance->write_beats = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_WRITE_BEATS);
    performance->stall_cycles = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_STALL_CYCLES);
    performance->error_responses = RS_ONCHIP_SRAM_REG(RS_ONCHIP_SRAM_REG_PERF_ERROR_RESPONSES);
    return RS_OK;
}
