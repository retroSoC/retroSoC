#include <firmware.h>
#include <tinylib.h>
#include <tinyprintf.h>
#include <tinyspisd.h>


void spisd_mem_read(uint8_t *buff, uint32_t size, uint32_t count, uint32_t addr) {
   switch(size) {
    case 1: {
        volatile uint8_t *wr_ptr = (volatile uint8_t*)addr;
        volatile uint8_t *buff_ptr = (volatile uint8_t*)buff;
        for (uint32_t i = 0; i < count; ++i) buff_ptr[i] = wr_ptr[i];
    break;
    }
    case 2: {
        volatile uint16_t *wr_ptr = (volatile uint16_t*)addr;
        volatile uint16_t *buff_ptr = (volatile uint16_t*)buff;
        for (uint32_t i = 0; i < count; ++i) buff_ptr[i] = wr_ptr[i];
    break;
    }
    case 4: {
        volatile uint32_t *wr_ptr = (volatile uint32_t*)addr;
        volatile uint32_t *buff_ptr = (volatile uint32_t*)buff;
        for (uint32_t i = 0; i < count; ++i) buff_ptr[i] = wr_ptr[i];
    break;
    }
    default: 
        printf("error\n");
        break;
    }
}

void spisd_sector_read(uint8_t *buff, uint32_t sector, uint32_t count) {
    uint32_t start_addr = sector * 512;
    start_addr += 0x60000000;
    // printf("START: %x LEN: %x\n\n", start_addr, 512 * count);

    volatile uint32_t *vis_addr = (uint32_t *)start_addr;
    for(uint32_t i = 0; i < count; ++i) {
        for(uint32_t j = 0; j < 128; ++j, ++vis_addr, buff += 4) {
            // printf("addr: %x val: %x\n", vis_addr, *vis_addr);
            *((uint32_t*)buff) = *vis_addr;
        }
    }
}

void spisd_sector_write(uint8_t *buff, uint32_t sector, uint32_t count) {
    uint32_t start_addr = sector * 512;
    start_addr += 0x60000000;
    // printf("START: %x LEN: %x\n\n", start_addr, 512 * count);

    volatile uint32_t *vis_addr = (uint32_t *)start_addr;
    for(uint32_t i = 0; i < count; ++i) {
        for(uint32_t j = 0; j < 128; ++j, ++vis_addr, buff += 4) {
            *vis_addr = *((uint32_t*)buff);
        }
    }
}

void ip_spisd_test() {
    printf("spisd test\n");
    printf("[SPISD] clk div(default): %d\n", reg_spisd_clkdiv);
    ip_psram_selftest(0x50000000, 1 * 1024 * 1024);
}

void ip_spisd_read(uint32_t addr, uint32_t len) {
    printf("spisd read test\n");
    printf("[SPISD] mode(default): %d\n", reg_spisd_mode);
    printf("[SPISD] clk div(default): %d\n", reg_spisd_clkdiv);
    printf("[SPISD] status: %d\n", reg_spisd_status);

    printf("START: %x LEN: %x\n\n", addr, len);
    volatile uint32_t *vis_addr = (uint32_t *)addr;
    for(uint32_t i = 0; i < len; ++i, ++vis_addr) {
        printf("addr: %x val: %x\n", vis_addr, *vis_addr);
    }

    // uint8_t res[512] = {0};
    // printf("\nsector read test\n");
    // spisd_sector_read(res, 32800, 1);
    // for(int i = 0; i < 512; ++i) {
    //     printf("res[%d]: %x\n", i, res[i]);
    // }
}