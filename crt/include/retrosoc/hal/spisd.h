#ifndef RETROSOC_HAL_SPISD_H
#define RETROSOC_HAL_SPISD_H

#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_SPISD_SECTOR_SIZE 512U

rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address);
rs_status_t rs_spisd_sector_read(uint8_t *buffer, uint32_t sector, uint32_t count);
rs_status_t rs_spisd_sector_write(const uint8_t *buffer, uint32_t sector, uint32_t count);
rs_status_t rs_spisd_sector_sync(rs_timeout_t timeout);
void ip_spisd_test(void);
void ip_spisd_read(uint32_t address, uint32_t length);

#endif
