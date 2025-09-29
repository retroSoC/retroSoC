#include <firmware.h>
#include <tinylib.h>
#include <tinyprintf.h>
#include <tinyspisd.h>


void ip_spisd_test() {
    printf("spisd test\n");
    printf("[SPISD] clk div(default): %d\n", reg_spisd_mode);
    ip_psram_selftest(0x50000000, 1 * 1024 * 1024);
}

void ip_spisd_read(uint32_t addr, uint32_t len) {
    printf("spisd read test\n");
    printf("[SPISD] clk div(default): %d\n", reg_spisd_mode);
    printf("START: %x LEN: %x\n\n", addr, len);
    volatile uint32_t *vis_addr = (uint32_t *)addr;
    for(uint32_t i = 0; i < len; ++i, ++vis_addr) {
        printf("addr: %x val: %x\n", vis_addr, *vis_addr);
    }
}