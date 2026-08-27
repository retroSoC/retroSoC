#ifndef RETROSOC_HP_BOOT_BUNDLE_H
#define RETROSOC_HP_BOOT_BUNDLE_H

#include <stdint.h>

#define RS_HP_BOOT_BUNDLE_OFFSET      UINT32_C(0x00100000)
#define RS_HP_BOOT_BUNDLE_MAGIC       UINT32_C(0x50485352)
#define RS_HP_BOOT_BUNDLE_VERSION     UINT32_C(1)
#define RS_HP_BOOT_BUNDLE_ENTRY_COUNT UINT32_C(4)
#define RS_HP_BOOT_BUNDLE_REQUIRED    UINT32_C(1)

#define RS_HP_BOOT_TYPE_OPENSBI       UINT32_C(1)
#define RS_HP_BOOT_TYPE_DTB           UINT32_C(2)
#define RS_HP_BOOT_TYPE_LINUX         UINT32_C(3)
#define RS_HP_BOOT_TYPE_INITRAMFS     UINT32_C(4)

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
    uint32_t reserved;
    rs_hp_boot_entry_t entries[RS_HP_BOOT_BUNDLE_ENTRY_COUNT];
} rs_hp_boot_header_t;

#endif
