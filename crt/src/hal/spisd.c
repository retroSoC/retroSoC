#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_spisd_sector_address(uint32_t sector, uintptr_t *address) {
    if ((address == NULL) || (sector > ((UINT32_MAX - TF_CARD_START) / RS_SPISD_SECTOR_SIZE))) {
        return RS_EINVAL;
    }
    *address = (uintptr_t)TF_CARD_START + ((uintptr_t)sector * RS_SPISD_SECTOR_SIZE);
    return RS_OK;
}

rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address) {
    volatile const uint8_t *source = (volatile const uint8_t *)address;
    uint8_t *destination = (uint8_t *)buffer;

    if ((buffer == NULL) || (address == 0U)) {
        return RS_EINVAL;
    }
    for (size_t index = 0U; index < byte_count; ++index) {
        destination[index] = source[index];
    }
    return RS_OK;
}

rs_status_t rs_spisd_sector_read(uint8_t *buffer, uint32_t sector, uint32_t count) {
    uintptr_t address;
    size_t byte_count;
    rs_status_t status;

    if ((buffer == NULL) || (count == 0U) || (count > (SIZE_MAX / RS_SPISD_SECTOR_SIZE))) {
        return RS_EINVAL;
    }
    status = rs_spisd_sector_address(sector, &address);
    if (status != RS_OK) {
        return status;
    }
    byte_count = (size_t)count * RS_SPISD_SECTOR_SIZE;
    return rs_spisd_read_bytes(buffer, byte_count, address);
}

rs_status_t rs_spisd_sector_write(const uint8_t *buffer, uint32_t sector, uint32_t count) {
    volatile uint8_t *destination;
    uintptr_t address;
    size_t byte_count;
    rs_status_t status;

    if ((buffer == NULL) || (count == 0U) || (count > (SIZE_MAX / RS_SPISD_SECTOR_SIZE))) {
        return RS_EINVAL;
    }
    status = rs_spisd_sector_address(sector, &address);
    if (status != RS_OK) {
        return status;
    }
    destination = (volatile uint8_t *)address;
    byte_count = (size_t)count * RS_SPISD_SECTOR_SIZE;
    for (size_t index = 0U; index < byte_count; ++index) {
        destination[index] = buffer[index];
    }
    return RS_OK;
}

rs_status_t rs_spisd_sector_sync(rs_timeout_t timeout) {
    reg_spisd_sync = 1U;
    return rs_wait_mask(&reg_spisd_status, UINT32_MAX, 0U, timeout);
}

void ip_spisd_test(void) {
    printf("spisd test\n");
    printf("[SPISD] clock divider: %d\n", reg_spisd_clkdiv);
    ip_psram_selftest(0x50000000U, 1U * 1024U * 1024U);
}

void ip_spisd_read(uint32_t address, uint32_t length) {
    volatile const uint32_t *source = (volatile const uint32_t *)(uintptr_t)address;

    printf("spisd read test\n");
    for (uint32_t index = 0U; index < length; ++index) {
        printf("addr: %x val: %x\n", (unsigned int)(uintptr_t)&source[index], source[index]);
    }
}
