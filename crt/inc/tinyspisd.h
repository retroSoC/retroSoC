#ifndef TINYSPISD_H__
#define TINYSPISD_H__

void spisd_mem_read(uint8_t *buff, uint32_t size, uint32_t count, uint32_t addr);
void spisd_sector_read(uint8_t *buff, uint32_t sector, uint32_t count);
void spisd_sector_write(uint8_t *buff, uint32_t sector, uint32_t count);
void ip_spisd_test();
void ip_spisd_read(uint32_t addr, uint32_t len);
#endif