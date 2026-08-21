#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/sdio.h>

static bool rs_sdio_response_range_valid(uint32_t high_bit, uint32_t low_bit) {
    return (high_bit < 136U) && (low_bit <= high_bit) && ((high_bit - low_bit) < 32U);
}

static rs_status_t rs_sdio_response_bit(const rs_sdio_response_t *response, uint32_t bit,
                                        uint32_t *value) {
    uint32_t word;
    uint32_t shift;

    if ((response == NULL) || (value == NULL) || (bit >= 136U)) {
        return RS_EINVAL;
    }
    word = bit / 32U;
    shift = bit % 32U;
    *value = (response->words[word] >> shift) & UINT32_C(1);
    return RS_OK;
}

static bool rs_sdio_address_range_valid(uintptr_t address, size_t byte_count) {
    uintptr_t last;

    if ((address == (uintptr_t)0U) || (address > (uintptr_t)UINT32_MAX) || (byte_count == 0U) ||
        (byte_count > (size_t)UINT32_MAX)) {
        return false;
    }

    last = address + (uintptr_t)(byte_count - 1U);
    return (last >= address) && (last <= (uintptr_t)UINT32_MAX);
}

static bool rs_sdio_descriptor_address_valid(uintptr_t address) {
    return (address <= (uintptr_t)UINT32_MAX) &&
           ((address % (uintptr_t)RS_SDIO_DESCRIPTOR_ALIGNMENT) == (uintptr_t)0U) &&
           ((address & UINT32_C(0xFFF)) < UINT32_C(0xFF0));
}

rs_status_t rs_sdio_clock_calculate(uint32_t source_clock_hz, uint32_t target_clock_hz,
                                    rs_sdio_clock_t *clock) {
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
    clock->actual_hz = source_clock_hz / (2U * (uint32_t)half_period);
    if (clock->actual_hz == 0U) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_response_field(const rs_sdio_response_t *response, uint32_t high_bit,
                                   uint32_t low_bit, uint32_t *value) {
    uint32_t result = 0U;
    uint32_t bit;

    if (!rs_sdio_response_range_valid(high_bit, low_bit) || (response == NULL) || (value == NULL)) {
        return RS_EINVAL;
    }
    for (bit = low_bit; bit <= high_bit; bit++) {
        uint32_t bit_value;

        if (rs_sdio_response_bit(response, bit, &bit_value) != RS_OK) {
            return RS_EINVAL;
        }
        result |= bit_value << (bit - low_bit);
        if (bit == high_bit) {
            break;
        }
    }
    *value = result;
    return RS_OK;
}

rs_status_t rs_sd_memory_address(rs_sd_memory_card_type_t card_type, uint32_t block,
                                 uint32_t *argument) {
    if (argument == NULL) {
        return RS_EINVAL;
    }
    switch (card_type) {
    case RS_SD_MEMORY_SDSC:
        if (block > (UINT32_MAX / RS_SD_MEMORY_BLOCK_SIZE)) {
            return RS_EINVAL;
        }
        *argument = block * RS_SD_MEMORY_BLOCK_SIZE;
        break;
    case RS_SD_MEMORY_SDHC:
        *argument = block;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sd_memory_parse_csd(const rs_sdio_response_t *response, rs_sd_memory_info_t *info) {
    uint32_t csd_structure;
    uint32_t read_bl_len;
    uint32_t c_size;
    uint32_t c_size_mult;
    uint32_t block_length;
    uint64_t capacity_bytes;
    uint64_t capacity_blocks;

    if ((response == NULL) || (info == NULL) ||
        (rs_sdio_response_field(response, 127U, 126U, &csd_structure) != RS_OK) ||
        (rs_sdio_response_field(response, 83U, 80U, &read_bl_len) != RS_OK)) {
        return RS_EINVAL;
    }
    if (csd_structure == 1U) {
        if (rs_sdio_response_field(response, 69U, 48U, &c_size) != RS_OK) {
            return RS_EINVAL;
        }
        capacity_blocks = ((uint64_t)c_size + UINT64_C(1)) << 10U;
        capacity_bytes = capacity_blocks * (uint64_t)RS_SD_MEMORY_BLOCK_SIZE;
        block_length = RS_SD_MEMORY_BLOCK_SIZE;
        info->card_type = RS_SD_MEMORY_SDHC;
        info->high_capacity = true;
    } else if (csd_structure == 0U) {
        if ((read_bl_len > 11U) || (rs_sdio_response_field(response, 73U, 62U, &c_size) != RS_OK) ||
            (rs_sdio_response_field(response, 49U, 47U, &c_size_mult) != RS_OK)) {
            return RS_EINVAL;
        }
        block_length = UINT32_C(1) << read_bl_len;
        capacity_bytes = ((uint64_t)c_size + UINT64_C(1)) * (UINT64_C(1) << (c_size_mult + 2U)) *
                         (uint64_t)block_length;
        capacity_blocks = capacity_bytes / (uint64_t)RS_SD_MEMORY_BLOCK_SIZE;
        info->card_type = RS_SD_MEMORY_SDSC;
        info->high_capacity = false;
    } else {
        return RS_EFORMAT;
    }
    if ((capacity_blocks == UINT64_C(0)) || (capacity_blocks > (uint64_t)UINT32_MAX) ||
        (capacity_bytes == UINT64_C(0))) {
        return RS_EINVAL;
    }
    info->capacity_blocks = (uint32_t)capacity_blocks;
    info->block_length = block_length;
    return RS_OK;
}

rs_status_t rs_sdio_cmd52_argument(const rs_sdio_cmd52_t *command, uint32_t *argument) {
    uint32_t value;

    if ((command == NULL) || (argument == NULL) || (command->function > 7U) ||
        (command->address > UINT32_C(0x1FFFF))) {
        return RS_EINVAL;
    }
    value =
        ((uint32_t)command->function << 28U) | (command->address << 9U) | (uint32_t)command->data;
    if (command->write) {
        value |= UINT32_C(0x80000000);
    }
    if (command->raw) {
        value |= UINT32_C(0x08000000);
    }
    *argument = value;
    return RS_OK;
}

rs_status_t rs_sdio_cmd53_argument(const rs_sdio_cmd53_t *command, uint32_t *argument) {
    uint32_t encoded_count;
    uint32_t value;

    if ((command == NULL) || (argument == NULL) || (command->function > 7U) ||
        (command->address > UINT32_C(0x1FFFF)) || (command->count == 0U) ||
        (command->count > UINT16_C(512))) {
        return RS_EINVAL;
    }
    encoded_count = (command->count == UINT16_C(512)) ? 0U : (uint32_t)command->count;
    value = ((uint32_t)command->function << 28U) | (command->address << 9U) | encoded_count;
    if (command->write) {
        value |= UINT32_C(0x80000000);
    }
    if (command->block_mode) {
        value |= UINT32_C(0x08000000);
    }
    if (!command->fixed_address) {
        value |= UINT32_C(0x04000000);
    }
    *argument = value;
    return RS_OK;
}

rs_status_t rs_sdio_validate_dma_buffer(const void *buffer, size_t byte_count) {
    uintptr_t address;

    if (buffer == NULL) {
        return RS_EINVAL;
    }
    address = (uintptr_t)buffer;
    if (((address % sizeof(uint32_t)) != 0U) || !rs_sdio_address_range_valid(address, byte_count)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_descriptor_prepare(rs_sdio_descriptor_t *descriptor, uintptr_t buffer,
                                       size_t byte_count, uintptr_t next, bool end, bool irq) {
    uint32_t control;
    uintptr_t descriptor_address;

    if ((descriptor == NULL) || !rs_sdio_address_range_valid(buffer, byte_count) ||
        ((buffer % sizeof(uint32_t)) != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_sdio_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    if (end) {
        if (next != (uintptr_t)0U) {
            return RS_EINVAL;
        }
    } else if ((next == (uintptr_t)0U) || (next > (uintptr_t)UINT32_MAX) ||
               ((next % RS_SDIO_DESCRIPTOR_ALIGNMENT) != 0U) ||
               !rs_sdio_descriptor_address_valid(next)) {
        return RS_EINVAL;
    }
    control = end ? (UINT32_C(1) << RS_SDIO_DESC_END_BIT) : (UINT32_C(1) << RS_SDIO_DESC_CHAIN_BIT);
    if (irq) {
        control |= UINT32_C(1) << RS_SDIO_DESC_IRQ_BIT;
    }
    descriptor->buffer_addr = (uint32_t)buffer;
    descriptor->byte_count = (uint32_t)byte_count;
    descriptor->next_addr = (uint32_t)next;
    descriptor->control_status = control;
    return RS_OK;
}

rs_status_t rs_sdio_descriptor_validate(const rs_sdio_descriptor_t *descriptor) {
    bool end;
    bool chain;
    uintptr_t descriptor_address;

    if ((descriptor == NULL) || ((descriptor->buffer_addr % sizeof(uint32_t)) != 0U) ||
        (descriptor->byte_count == 0U) ||
        ((descriptor->control_status & RS_SDIO_DESCRIPTOR_RESERVED_MASK) != 0U) ||
        ((descriptor->control_status & RS_SDIO_DESCRIPTOR_WRITEBACK_MASK) != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_sdio_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    end = (descriptor->control_status & (UINT32_C(1) << RS_SDIO_DESC_END_BIT)) != 0U;
    chain = (descriptor->control_status & (UINT32_C(1) << RS_SDIO_DESC_CHAIN_BIT)) != 0U;
    if (end) {
        if (chain || (descriptor->next_addr != 0U)) {
            return RS_EINVAL;
        }
    } else if (!chain || (descriptor->next_addr == 0U) ||
               ((descriptor->next_addr % RS_SDIO_DESCRIPTOR_ALIGNMENT) != 0U) ||
               !rs_sdio_descriptor_address_valid((uintptr_t)descriptor->next_addr)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_descriptor_chain_validate(const rs_sdio_descriptor_t *descriptors,
                                              uint16_t count, uint32_t total_bytes) {
    uint32_t total = 0U;
    uint16_t index;
    bool found_end = false;

    if ((descriptors == NULL) || (count == 0U) ||
        (count > (uint16_t)RS_SDIO_MAX_DESCRIPTOR_COUNT) ||
        (((uintptr_t)descriptors % RS_SDIO_DESCRIPTOR_ALIGNMENT) != 0U) ||
        ((uintptr_t)descriptors > (uintptr_t)UINT32_MAX) ||
        !rs_sdio_descriptor_address_valid((uintptr_t)descriptors)) {
        return RS_EINVAL;
    }
    for (index = 0U; index < count; index++) {
        const rs_sdio_descriptor_t *descriptor = &descriptors[index];
        bool end;

        if (rs_sdio_descriptor_validate(descriptor) != RS_OK) {
            return RS_EINVAL;
        }
        if (descriptor->byte_count > (UINT32_MAX - total)) {
            return RS_EINVAL;
        }
        total += descriptor->byte_count;
        end = (descriptor->control_status & (UINT32_C(1) << RS_SDIO_DESC_END_BIT)) != 0U;
        if (end) {
            if (index + 1U != count) {
                return RS_EINVAL;
            }
            found_end = true;
        } else {
            uintptr_t next = (uintptr_t)&descriptors[index + 1U];

            if ((next > (uintptr_t)UINT32_MAX) || !rs_sdio_descriptor_address_valid(next) ||
                (descriptor->next_addr != (uint32_t)next)) {
                return RS_EINVAL;
            }
        }
    }
    if (!found_end || ((total_bytes != 0U) && (total != total_bytes))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_descriptor_publish(rs_sdio_descriptor_t *descriptor) {
    if (rs_sdio_descriptor_validate(descriptor) != RS_OK) {
        return RS_EINVAL;
    }
    rs_sdio_memory_barrier();
    descriptor->control_status |= UINT32_C(1) << RS_SDIO_DESC_OWN_BIT;
    rs_sdio_memory_barrier();
    return RS_OK;
}

rs_status_t rs_sdio_descriptor_publish_chain(rs_sdio_descriptor_t *descriptors, uint16_t count) {
    uint16_t index;

    if (rs_sdio_descriptor_chain_validate(descriptors, count, 0U) != RS_OK) {
        return RS_EINVAL;
    }
    for (index = 0U; index < count; index++) {
        if (rs_sdio_descriptor_publish(&descriptors[index]) != RS_OK) {
            return RS_EINVAL;
        }
    }
    return RS_OK;
}
