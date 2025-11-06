#include <firmware.h>
#include <tinytim.h>
#include <tinyqspi.h>
#include <tinydma.h>
#include <tinyprintf.h>


void qspi0_init(QSPI0_InitStruct_t val) {
    reg_qspi0_mode       = val.mode;
    reg_qspi0_nss        = val.nss;
    reg_qspi0_clkdiv     = val.clkdiv;
    reg_qspi0_txupbound  = val.txub;
    reg_qspi0_txlowbound = val.txlb;
    reg_qspi0_rxupbound  = val.rxub;
    reg_qspi0_rxlowbound = val.rxlb;
    reg_qspi0_hlvlen     = val.hlven;
}

void qspi0_wr(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list) {

    reg_qspi0_rdwr = (uint32_t)0;
    reg_qspi0_revdat = (uint32_t)0;
    reg_qspi0_flush = (uint32_t)1;
    // cmd
    reg_qspi0_cmdtyp = cmdtyp;
    reg_qspi0_cmdlen = cmdlen;
    reg_qspi0_cmddat = cmddat;
    // adr
    reg_qspi0_adrtyp = adrtyp;
    reg_qspi0_adrlen = adrlen;
    reg_qspi0_adrdat = adrdat;
    // dum
    reg_qspi0_dumlen = dumlen;
    // dat
    reg_qspi0_dattyp = dattyp;
    reg_qspi0_datlen = datlen;
    reg_qspi0_datbit = datbit;

    // NOTE: need to guarantee 'len < fifo depth'
    for(uint32_t i = 0; i < datlen; ++i) {
        reg_qspi0_txdata = dat_list[i];
    }

    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
}

void qspi0_xfer_config(
    uint32_t rdwr, uint32_t revdat, uint32_t flush,
    uint32_t cmdtyp, uint32_t cmdlen,
    uint32_t adrtyp, uint32_t adrlen,
    uint32_t dumlen,
    uint32_t dattyp, uint32_t datlen, uint32_t datbit
) {
    reg_qspi0_rdwr = rdwr;
    reg_qspi0_revdat = revdat;
    reg_qspi0_flush = flush;
    // cmd
    reg_qspi0_cmdtyp = cmdtyp;
    reg_qspi0_cmdlen = cmdlen;
    // adr
    reg_qspi0_adrtyp = adrtyp;
    reg_qspi0_adrlen = adrlen;
    // dum
    reg_qspi0_dumlen = dumlen;
    // dat
    reg_qspi0_dattyp = dattyp;
    reg_qspi0_datlen = datlen;
    reg_qspi0_datbit = datbit;
}

// NOTE: 
void qspi0_wr_cmd8(uint8_t dat) {
    uint32_t xfer_cmd = dat << 24;
    reg_qspi0_cmdlen = (uint32_t)1;
    reg_qspi0_cmddat = xfer_cmd;
    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
}

void qspi0_wr_cmd16(uint16_t dat) {
    uint32_t xfer_cmd = dat << 16;
    reg_qspi0_cmdlen = (uint32_t)2;
    reg_qspi0_cmddat = xfer_cmd;
    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
}

void qspi0_wr_dat8(uint8_t dat) {
    uint32_t xfer_dat = dat << 24;
    reg_qspi0_datbit = (uint32_t)1;
    reg_qspi0_txdata = xfer_dat;
    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
}

void qspi0_wr_dat16(uint16_t dat) {
    uint32_t xfer_dat = dat << 16;
    reg_qspi0_datbit = (uint32_t)2;
    reg_qspi0_txdata = xfer_dat;
    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
}

void qspi0_wr_data32(uint32_t* dat, uint32_t len) {
    reg_qspi0_flush = (uint32_t)1;
    reg_qspi0_mode = (uint32_t)0;
    reg_qspi0_revdat = (uint32_t)1;
    reg_qspi0_datlen = len;
    reg_qspi0_datbit = (uint32_t)4;
   for (uint32_t i = 0; i < len; ++i) {
    reg_qspi0_txdata = dat[i];
    // printf("data[%d]: %x\n", i, dat[i]);
   }

    reg_qspi0_start = (uint32_t)1;
    while((reg_qspi0_status & (uint32_t)1) == 0);
    reg_qspi0_flush = (uint32_t)1;
    reg_qspi0_revdat = (uint32_t)0;
    reg_qspi0_datlen = (uint32_t)1;
}

void qspi0_rd(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list) {

    reg_qspi0_rdwr = (uint32_t)1;
    reg_qspi0_revdat = (uint32_t)0;
    reg_qspi0_flush = (uint32_t)0;
    // cmd
    reg_qspi0_cmdtyp = cmdtyp;
    reg_qspi0_cmdlen = cmdlen;
    reg_qspi0_cmddat = cmddat;
    // adr
    reg_qspi0_adrtyp = adrtyp;
    reg_qspi0_adrlen = adrlen;
    reg_qspi0_adrdat = adrdat;
    // dum
    reg_qspi0_dumlen = dumlen;
    // dat
    reg_qspi0_dattyp = dattyp;
    reg_qspi0_datlen = datlen;
    reg_qspi0_datbit = datbit;

    reg_qspi0_start = (uint32_t)1;
    for(uint32_t i = 0; i < datlen; ++i) {
        while((reg_qspi0_status & (uint32_t)(1 << 4)));
        dat_list[i] = reg_qspi0_rxdata;
    }
}


void qspi0_dma_xfer(uint32_t addr, uint32_t len) {
    reg_qspi0_flush = (uint32_t)1;
    reg_qspi0_datlen = (uint32_t)32;
    reg_qspi0_mode = (uint32_t)1;
    reg_qspi0_revdat = (uint32_t)1;
    reg_qspi0_datbit = (uint32_t)4;
    // printf("[qspi0 dma] src addr: %x, len: %d\n", addr, len);
    // uint32_t *ptr = (uint32_t*)addr;
    // for(int i = 0; i < 32; ++i) {
    //     printf("data[%d]: %x\n", i, ptr[i]);
    // }
    dma_config((uint32_t)3, addr, (uint32_t)1, (uint32_t)&reg_qspi0_txdata, (uint32_t)0, len);
    dma_start_xfer();
    // NOTE: must guarantee dma xfer done flag is clr after tx fifo empty check!
    while((reg_qspi0_status & (uint32_t)(1 << 2)) == 0);
    dma_wait_done();
    reg_qspi0_mode = (uint32_t)0;
    reg_qspi0_flush = (uint32_t)1;
    reg_qspi0_revdat = (uint32_t)0;
    reg_qspi0_datlen = (uint32_t)1;
}

void qspi1_init() {
    reg_gpio_oen = (uint32_t)0b011;
    reg_qspi1_status = (uint32_t)0b10000;
    reg_qspi1_status = (uint32_t)0b00000;
    reg_qspi1_intcfg = (uint32_t)0b00000;
    reg_qspi1_dum = (uint32_t)0;
    reg_qspi1_clkdiv = (uint32_t)0; // sck = apb_clk/2(div+1)
}

void qspi1_wr_dat8(uint8_t dat) {
    uint32_t wdat = ((uint32_t)dat) << 24;
    // spi_set_datalen(8);
    reg_qspi1_len = 0x80000;
    // spi_write_fifo(&wdata, 8);
    reg_qspi1_txfifo = wdat;
    // spi_start_transaction(SPI_CMD_WR, SPI_CSN0);
    reg_qspi1_status = 258;
    while ((reg_qspi1_status & 0xFFFF) != 1);
}

void qspi1_wr_data16(uint16_t dat) {
    uint32_t wdat = ((uint32_t)dat) << 16;
    reg_qspi1_len = 0x100000; // NOTE: 16bits
    reg_qspi1_txfifo = wdat;
    reg_qspi1_status = 258;
    while ((reg_qspi1_status & 0xFFFF) != 1);
}

void qspi1_wr_data32(uint32_t* dat, uint32_t len) {
    reg_qspi1_len = (32 * len) << 16;
    for(uint32_t i = 0; i < len; ++i) reg_qspi1_txfifo = dat[i];
    reg_qspi1_status = 258;
    while ((reg_qspi1_status & 0xFFFF) != 1);
}

void qspi_dev_init() {
#ifdef USE_QSPI0_DEV
    QSPI0_InitStruct_t qspi0 = {
        (uint32_t)0,
        (uint32_t)0b0001, // fpga
        // (uint32_t)0b1000, // soc
        (uint32_t)0,
        (uint32_t)250,
        (uint32_t)200,
        (uint32_t)24,
        (uint32_t)10,
        (uint32_t)2,
    };
    qspi0_init(qspi0);
    // 1-1-1(tx data only)
    qspi0_xfer_config((uint32_t)0, (uint32_t)0, (uint32_t)1, // flush bit
                      (uint32_t)0, (uint32_t)0,
                      (uint32_t)0, (uint32_t)0,
                      (uint32_t)0,
                      (uint32_t)1, (uint32_t)1, (uint32_t)1
                     );
#else
    qspi1_init();
#endif
}