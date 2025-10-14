#include <firmware.h>
#include <tinyprintf.h>
#include <tinydma.h>
#include <tinyi2s.h>

void dma_config(uint32_t mode, uint32_t src, uint32_t srcincr, uint32_t dst, uint32_t dstincr, uint32_t xferlen) {
    reg_dma_mode = mode;
    reg_dma_srcaddr = src;
    reg_dma_srcincr = srcincr;
    reg_dma_dstaddr = dst;
    reg_dma_dstincr = dstincr;
    reg_dma_xferlen = xferlen;
}

void dma_start_xfer() {
    reg_dma_start = (uint32_t)1;
}

void dma_stop_toggle() {
    reg_dma_stop = (uint32_t)1;
}

void dma_reset_xfer() {
    dma_stop_toggle();
    reg_dma_reset = (uint32_t)1;
    dma_stop_toggle();
}

void dma_wait_done() {
    while(reg_dma_status == (uint32_t)0);
    printf("dma tx done\n");
}

void ip_dma_test() {
    printf("dma test\n");
    // i2s
    reg_i2s_mode = (uint32_t)1;
    reg_i2s_upbound = (uint32_t)120;
    reg_i2s_lowbound = (uint32_t)32;
    reg_i2s_recven = (uint32_t)0;
    // dma
    reg_dma_mode = (uint32_t)1; // i2s tx fifo
    // reg_dma_srcaddr = (uint32_t)0x51004000;
    reg_dma_srcaddr = (uint32_t)0x40000000;
    reg_dma_srcincr = (uint32_t)1;
    reg_dma_dstaddr = (uint32_t)(&reg_i2s_txdata);
    reg_dma_dstincr = (uint32_t)0;
    reg_dma_xferlen = (uint32_t)512;
    reg_dma_start = (uint32_t)1;
    while(reg_dma_status == (uint32_t)0);
    printf("dma tx done\n");

    reg_i2s_recven = (uint32_t)1;
    reg_dma_mode = (uint32_t)2; // i2s rx fifo
    reg_dma_srcaddr = (uint32_t)(&reg_i2s_rxdata);
    reg_dma_srcincr = (uint32_t)0;
    reg_dma_dstaddr = (uint32_t)0x41000000;
    reg_dma_dstincr = (uint32_t)1;
    reg_dma_xferlen = (uint32_t)180;
    reg_dma_start = (uint32_t)1;
    while(reg_dma_status == (uint32_t)0);
    reg_i2s_recven = (uint32_t)0;
    printf("dma rx done\n");

    // volatile uint32_t *test_rd_addr = (uint32_t *)0x41000000;
    // for(int i = 0; i < 6; ++i) printf("recv %d: %x\n", i, *(test_rd_addr + i));
}