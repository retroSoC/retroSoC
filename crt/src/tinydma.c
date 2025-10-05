#include <firmware.h>
#include <tinyprintf.h>
#include <tinydma.h>
#include <tinyi2s.h>

void ip_dma_test() {
    printf("dma test\n");

    // i2s
    reg_i2s_mode = (uint32_t)1;
    reg_i2s_upbound = (uint32_t)120;
    reg_i2s_lowbound = (uint32_t)32;
    // dma
    reg_dma_mode = (uint32_t)1;
    // reg_dma_srcaddr = (uint32_t)0x51004000;
    reg_dma_srcaddr = (uint32_t)0x40000000;
    reg_dma_srcincr = (uint32_t)1;
    reg_dma_dstaddr = (uint32_t)0x1000700C;
    reg_dma_dstincr = (uint32_t)0;
    reg_dma_xferlen = (uint32_t)512;
    reg_dma_start = (uint32_t)1;

    while(reg_dma_status & 1);
    printf("dma done\n");
}