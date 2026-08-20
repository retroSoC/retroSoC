#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/spisd.h>

static bool rs_spisd_address_range_valid(uintptr_t address, size_t byte_count) {
    uintptr_t last;

    if ((address == (uintptr_t)0U) || (address > (uintptr_t)UINT32_MAX) || (byte_count == 0U) ||
        (byte_count > (size_t)UINT32_MAX)) {
        return false;
    }
    last = address + (uintptr_t)(byte_count - 1U);
    return (last >= address) && (last <= (uintptr_t)UINT32_MAX);
}

static bool rs_spisd_descriptor_address_valid(uintptr_t address) {
    return (address <= (uintptr_t)UINT32_MAX) &&
           ((address % (uintptr_t)RS_SPISD_DESCRIPTOR_ALIGNMENT) == (uintptr_t)0U) &&
           ((address & UINT32_C(0xFFF)) < UINT32_C(0xFF0));
}

rs_status_t rs_spisd_clock_calculate(uint32_t source_clock_hz, uint32_t target_clock_hz,
                                     rs_spisd_clock_t *clock) {
    uint64_t denominator;
    uint64_t half_period;

    if ((source_clock_hz == 0U) || (target_clock_hz == 0U) || (clock == NULL) ||
        (target_clock_hz > (source_clock_hz / 2U))) {
        return RS_EINVAL;
    }
    denominator = (uint64_t)target_clock_hz * UINT64_C(2);
    half_period = ((uint64_t)source_clock_hz + denominator - UINT64_C(1)) / denominator;
    if ((half_period == UINT64_C(0)) || (half_period > (uint64_t)UINT16_MAX)) {
        return RS_EINVAL;
    }
    clock->half_period = (uint16_t)half_period;
    clock->requested_hz = target_clock_hz;
    clock->actual_hz = source_clock_hz / (UINT32_C(2) * (uint32_t)half_period);
    return (clock->actual_hz == 0U) ? RS_EINVAL : RS_OK;
}

rs_status_t rs_spisd_card_address(rs_spisd_card_type_t card_type, uint32_t sector,
                                  uint32_t *argument) {
    if (argument == NULL) {
        return RS_EINVAL;
    }
    switch (card_type) {
    case RS_SPISD_CARD_SDSC:
        if (sector > (UINT32_MAX / RS_SPISD_SECTOR_SIZE)) {
            return RS_EINVAL;
        }
        *argument = sector * RS_SPISD_SECTOR_SIZE;
        break;
    case RS_SPISD_CARD_SDHC:
        *argument = sector;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_spisd_parse_csd(const uint8_t *csd, rs_spisd_card_info_t *info) {
    uint32_t c_size;
    uint32_t multiplier;
    uint32_t read_block_length;
    uint64_t capacity_bytes;
    uint64_t capacity_blocks;

    if ((csd == NULL) || (info == NULL)) {
        return RS_EINVAL;
    }
    if ((csd[0] >> 6U) == 1U) {
        c_size = ((uint32_t)(csd[7] & UINT8_C(0x3F)) << 16U) | ((uint32_t)csd[8] << 8U) |
                 (uint32_t)csd[9];
        capacity_blocks = ((uint64_t)c_size + UINT64_C(1)) << 10U;
        info->card_type = RS_SPISD_CARD_SDHC;
        info->high_capacity = true;
    } else if ((csd[0] >> 6U) == 0U) {
        read_block_length = (uint32_t)(csd[5] & UINT8_C(0x0F));
        c_size = ((uint32_t)(csd[6] & UINT8_C(0x03)) << 10U) | ((uint32_t)csd[7] << 2U) |
                 ((uint32_t)csd[8] >> 6U);
        multiplier = ((uint32_t)(csd[9] & UINT8_C(0x03)) << 1U) | ((uint32_t)csd[10] >> 7U);
        if ((read_block_length > 11U) || (multiplier > 7U)) {
            return RS_EFORMAT;
        }
        capacity_bytes = ((uint64_t)c_size + UINT64_C(1))
                         << (multiplier + UINT32_C(2) + read_block_length);
        capacity_blocks = capacity_bytes / (uint64_t)RS_SPISD_SECTOR_SIZE;
        info->card_type = RS_SPISD_CARD_SDSC;
        info->high_capacity = false;
    } else {
        return RS_EFORMAT;
    }
    if ((capacity_blocks == UINT64_C(0)) || (capacity_blocks > (uint64_t)UINT32_MAX)) {
        return RS_EFORMAT;
    }
    info->capacity_blocks = (uint32_t)capacity_blocks;
    return RS_OK;
}

rs_status_t rs_spisd_descriptor_prepare(rs_spisd_descriptor_t *descriptor, uintptr_t buffer,
                                        size_t byte_count, uintptr_t next, bool end, bool irq) {
    uint32_t control;
    uintptr_t descriptor_address;

    if ((descriptor == NULL) || !rs_spisd_address_range_valid(buffer, byte_count) ||
        ((buffer % sizeof(uint32_t)) != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_spisd_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    if (end) {
        if (next != (uintptr_t)0U) {
            return RS_EINVAL;
        }
        control = RS_SPISD_DESC_END;
    } else {
        if ((next == (uintptr_t)0U) || !rs_spisd_descriptor_address_valid(next)) {
            return RS_EINVAL;
        }
        control = RS_SPISD_DESC_CHAIN;
    }
    if (irq) {
        control |= RS_SPISD_DESC_IRQ;
    }
    descriptor->buffer_address = (uint32_t)buffer;
    descriptor->byte_count = (uint32_t)byte_count;
    descriptor->next_address = (uint32_t)next;
    descriptor->control_status = control;
    return RS_OK;
}

rs_status_t rs_spisd_descriptor_validate(const rs_spisd_descriptor_t *descriptor) {
    bool chain;
    bool end;
    uintptr_t descriptor_address;

    if ((descriptor == NULL) || ((descriptor->buffer_address % sizeof(uint32_t)) != 0U) ||
        (descriptor->byte_count == 0U) ||
        ((descriptor->control_status & RS_SPISD_DESCRIPTOR_RESERVED_MASK) != 0U) ||
        ((descriptor->control_status & RS_SPISD_DESCRIPTOR_WRITEBACK_MASK) != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_spisd_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    chain = (descriptor->control_status & RS_SPISD_DESC_CHAIN) != 0U;
    end = (descriptor->control_status & RS_SPISD_DESC_END) != 0U;
    if (end) {
        if (chain || (descriptor->next_address != 0U)) {
            return RS_EINVAL;
        }
    } else if (!chain || (descriptor->next_address == 0U) ||
               !rs_spisd_descriptor_address_valid((uintptr_t)descriptor->next_address)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_spisd_descriptor_publish(rs_spisd_descriptor_t *descriptor) {
    if (rs_spisd_descriptor_validate(descriptor) != RS_OK) {
        return RS_EINVAL;
    }
    rs_spisd_memory_barrier();
    descriptor->control_status |= RS_SPISD_DESC_OWN;
    rs_spisd_memory_barrier();
    return RS_OK;
}
