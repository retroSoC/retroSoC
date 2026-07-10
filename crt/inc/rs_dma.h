
#ifndef TINYDMA_H__
#define TINYDMA_H__

void dma_config(uint32_t mode, uint32_t src, uint32_t srcincr, uint32_t dst, uint32_t dstincr, uint32_t xferlen);
void dma_start_xfer();
void dma_stop_toggle();
void dma_reset_xfer();
void dma_wait_done();
void ip_dma_test();

#endif