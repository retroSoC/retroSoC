#ifndef RETROSOC_HP_BOOT_BUNDLE_H
#define RETROSOC_HP_BOOT_BUNDLE_H

#include <stdint.h>
#include <stdbool.h>

#define RS_HP_BOOT_BUNDLE_OFFSET      UINT32_C(0x00100000)
#define RS_HP_BOOT_BUNDLE_MAGIC       UINT32_C(0x50485352)
#define RS_HP_BOOT_BUNDLE_VERSION     UINT32_C(2)
#define RS_HP_BOOT_BUNDLE_ENTRY_COUNT UINT32_C(4)
#define RS_HP_BOOT_BUNDLE_REQUIRED    UINT32_C(1)

#define RS_HP_BOOT_TYPE_OPENSBI       UINT32_C(1)
#define RS_HP_BOOT_TYPE_DTB           UINT32_C(2)
#define RS_HP_BOOT_TYPE_LINUX         UINT32_C(3)
#define RS_HP_BOOT_TYPE_INITRAMFS     UINT32_C(4)
#define RS_HP_BOOT_TYPE_EXECUTABLE    UINT32_C(5)
#define RS_HP_BOOT_WORKLOAD_LINUX     UINT32_C(1)
#define RS_HP_BOOT_WORKLOAD_SMOKE     UINT32_C(2)
#define RS_HP_BOOT_WORKLOAD_RTTHREAD  UINT32_C(3)
#define RS_HP_RTTHREAD_READY_ARG      UINT32_C(0x52545401)
#define RS_HP_RTTHREAD_IRQ_COMMAND    UINT32_C(0x52545402)
#define RS_HP_RTTHREAD_IRQ_ARG        UINT32_C(0x12345678)

#define RS_HP_BOOT_OPENSBI_ADDRESS    UINT32_C(0x38000000)
#define RS_HP_BOOT_OPENSBI_MAX_SIZE   UINT32_C(0x00080000)
#define RS_HP_BOOT_DTB_ADDRESS        UINT32_C(0x38080000)
#define RS_HP_BOOT_DTB_MAX_SIZE       UINT32_C(0x00010000)
#define RS_HP_BOOT_LINUX_ADDRESS      UINT32_C(0x38400000)
#define RS_HP_BOOT_LINUX_MAX_SIZE     UINT32_C(0x00C00000)
#define RS_HP_BOOT_INITRAMFS_ADDRESS  UINT32_C(0x39000000)
#define RS_HP_BOOT_INITRAMFS_MAX_SIZE UINT32_C(0x00800000)

typedef struct {
    uint32_t type;
    uint32_t flash_offset;
    uint32_t load_address;
    uint32_t size;
    uint32_t crc32;
    uint32_t flags;
} rs_hp_boot_entry_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t header_size;
    uint32_t entry_count;
    uint32_t total_size;
    uint32_t header_crc32;
    uint32_t flags;
    uint32_t workload;
    rs_hp_boot_entry_t entries[RS_HP_BOOT_BUNDLE_ENTRY_COUNT];
} rs_hp_boot_header_t;

uint32_t rs_hp_boot_crc32_byte(uint32_t crc, uint8_t value);
uint32_t rs_hp_boot_crc32(const uint8_t *data, uint32_t size);
bool rs_hp_boot_header_valid(const rs_hp_boot_header_t *header);
/* 0: wait for publication, 1: expected message, 2: invalid/failure message. */
uint32_t rs_hp_boot_message_status(uint32_t code, uint32_t argument, uint32_t sequence,
                                   uint32_t expected_code, uint32_t expected_argument,
                                   uint32_t expected_sequence);

#endif
