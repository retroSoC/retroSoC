#include "hp_boot_bundle.h"

#include <stddef.h>

uint32_t rs_hp_boot_message_status(uint32_t code, uint32_t argument, uint32_t sequence,
                                   uint32_t expected_code, uint32_t expected_argument,
                                   uint32_t expected_sequence) {
    if ((sequence > expected_sequence) || ((sequence != 0U) && (code == 3U))) {
        return 2U;
    }
    if (sequence == expected_sequence) {
        return ((code == expected_code) && (argument == expected_argument)) ? 1U : 2U;
    }
    return 0U;
}

uint32_t rs_hp_boot_crc32_byte(uint32_t crc, uint8_t value) {
    crc ^= value;
    for (uint32_t bit = 0U; bit < 8U; ++bit) {
        uint32_t mask = UINT32_C(0) - (crc & UINT32_C(1));
        crc = (crc >> 1U) ^ (UINT32_C(0xEDB88320) & mask);
    }
    return crc;
}

uint32_t rs_hp_boot_crc32(const uint8_t *data, uint32_t size) {
    uint32_t crc = UINT32_C(0xFFFFFFFF);
    for (uint32_t index = 0U; index < size; ++index) {
        crc = rs_hp_boot_crc32_byte(crc, data[index]);
    }
    return ~crc;
}

bool rs_hp_boot_header_valid(const rs_hp_boot_header_t *header) {
    static const uint32_t addresses[4] = {RS_HP_BOOT_OPENSBI_ADDRESS, RS_HP_BOOT_DTB_ADDRESS,
                                          RS_HP_BOOT_LINUX_ADDRESS, RS_HP_BOOT_INITRAMFS_ADDRESS};
    static const uint32_t maxima[4] = {RS_HP_BOOT_OPENSBI_MAX_SIZE, RS_HP_BOOT_DTB_MAX_SIZE,
                                       RS_HP_BOOT_LINUX_MAX_SIZE, RS_HP_BOOT_INITRAMFS_MAX_SIZE};
    rs_hp_boot_header_t copy;
    uint32_t previous_end = RS_HP_BOOT_BUNDLE_OFFSET + (uint32_t)sizeof(copy);
    uint32_t count;
    if (header == NULL) {
        return false;
    }
    copy = *header;
    copy.header_crc32 = 0U;
    count = (header->workload == RS_HP_BOOT_WORKLOAD_LINUX) ? 4U : 1U;
    if ((header->magic != RS_HP_BOOT_BUNDLE_MAGIC) ||
        (header->version != RS_HP_BOOT_BUNDLE_VERSION) || (header->header_size != sizeof(copy)) ||
        (header->entry_count != count) || (header->workload < RS_HP_BOOT_WORKLOAD_LINUX) ||
        (header->workload > RS_HP_BOOT_WORKLOAD_RTTHREAD) ||
        (header->flags != RS_HP_BOOT_BUNDLE_REQUIRED) || (header->total_size < sizeof(copy)) ||
        (header->total_size > UINT32_C(0x00F00000)) ||
        (rs_hp_boot_crc32((const uint8_t *)&copy, sizeof(copy)) != header->header_crc32)) {
        return false;
    }
    for (uint32_t index = 0U; index < RS_HP_BOOT_BUNDLE_ENTRY_COUNT; ++index) {
        const rs_hp_boot_entry_t *entry = &header->entries[index];
        if (index >= count) {
            if ((entry->type | entry->flash_offset | entry->load_address | entry->size |
                 entry->crc32 | entry->flags) != 0U) {
                return false;
            }
        } else {
            uint32_t type = (count == 4U) ? index + 1U : RS_HP_BOOT_TYPE_EXECUTABLE;
            uint32_t bundle_end = RS_HP_BOOT_BUNDLE_OFFSET + header->total_size;
            if ((entry->type != type) || (entry->load_address != addresses[index]) ||
                (entry->size == 0U) || (entry->size > maxima[index]) ||
                (entry->flags != RS_HP_BOOT_BUNDLE_REQUIRED) ||
                ((entry->flash_offset & UINT32_C(0xFFF)) != 0U) ||
                (entry->flash_offset < previous_end) || (entry->flash_offset >= bundle_end) ||
                (entry->size > (bundle_end - entry->flash_offset))) {
                return false;
            }
            previous_end = entry->flash_offset + entry->size;
        }
    }
    return true;
}
