#include <firmware.h>
#include <tinytim.h>
#include <tinyqspi.h>
#include <tinydma.h>
#include <tinyprintf.h>


void qspi0_init(QSPI0_InitStruct_t val) {
    reg_gpio_oe          = (uint32_t)0b100;
    reg_xpi_mode       = val.mode;
    reg_xpi_nss        = val.nss;
    reg_xpi_clkdiv     = val.clkdiv;
    reg_xpi_txupb      = val.txub;
    reg_xpi_txlowb     = val.txlb;
    reg_xpi_rxupb      = val.rxub;
    reg_xpi_rxlowb     = val.rxlb;
    reg_xpi_hlvlen     = val.hlven;
}

void qspi0_wr(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list) {

    reg_xpi_rdwr = (uint32_t)0;
    reg_xpi_revdat = (uint32_t)0;
    reg_xpi_flush = (uint32_t)1;
    // cmd
    reg_xpi_cmdtyp = cmdtyp;
    reg_xpi_cmdlen = cmdlen;
    reg_xpi_cmddat = cmddat;
    // adr
    reg_xpi_adrtyp = adrtyp;
    reg_xpi_adrlen = adrlen;
    reg_xpi_adrdat = adrdat;
    // dum
    reg_xpi_tdulen = dumlen;
    reg_xpi_rdulen = dumlen;
    // dat
    reg_xpi_dattyp = dattyp;
    reg_xpi_datlen = datlen;
    reg_xpi_datbit = datbit;

    // NOTE: need to guarantee 'len < fifo depth'
    for(uint32_t i = 0; i < datlen; ++i) {
        reg_xpi_txdata = dat_list[i];
    }

    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
}

void qspi0_xfer_config(
    uint32_t rdwr, uint32_t revdat, uint32_t flush,
    uint32_t cmdtyp, uint32_t cmdlen,
    uint32_t adrtyp, uint32_t adrlen,
    uint32_t dumlen,
    uint32_t dattyp, uint32_t datlen, uint32_t datbit
) {
    reg_xpi_rdwr = rdwr;
    reg_xpi_revdat = revdat;
    reg_xpi_flush = flush;
    // cmd
    reg_xpi_cmdtyp = cmdtyp;
    reg_xpi_cmdlen = cmdlen;
    // adr
    reg_xpi_adrtyp = adrtyp;
    reg_xpi_adrlen = adrlen;
    // dum
    reg_xpi_tdulen = dumlen;
    reg_xpi_rdulen = dumlen;
    // dat
    reg_xpi_dattyp = dattyp;
    reg_xpi_datlen = datlen;
    reg_xpi_datbit = datbit;
}

// NOTE: 
void qspi0_wr_cmd8(uint8_t dat) {
    uint32_t xfer_cmd = dat << 24;
    reg_xpi_cmdlen = (uint32_t)1;
    reg_xpi_cmddat = xfer_cmd;
    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
}

void qspi0_wr_cmd16(uint16_t dat) {
    uint32_t xfer_cmd = dat << 16;
    reg_xpi_cmdlen = (uint32_t)2;
    reg_xpi_cmddat = xfer_cmd;
    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
}

void qspi0_wr_dat8(uint8_t dat) {
    uint32_t xfer_dat = dat << 24;
    reg_xpi_datbit = (uint32_t)1;
    reg_xpi_txdata = xfer_dat;
    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
}

void qspi0_wr_dat16(uint16_t dat) {
    uint32_t xfer_dat = dat << 16;
    reg_xpi_datbit = (uint32_t)2;
    reg_xpi_txdata = xfer_dat;
    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
}

void qspi0_wr_data32(uint32_t* dat, uint32_t len) {
    reg_xpi_flush = (uint32_t)1;
    reg_xpi_mode = (uint32_t)0;
    reg_xpi_revdat = (uint32_t)1;
    reg_xpi_datlen = len;
    reg_xpi_datbit = (uint32_t)4;
   for (uint32_t i = 0; i < len; ++i) {
    reg_xpi_txdata = dat[i];
    // printf("data[%d]: %x\n", i, dat[i]);
   }

    reg_xpi_start = (uint32_t)1;
    while((reg_xpi_status & (uint32_t)1) == 0);
    reg_xpi_flush = (uint32_t)1;
    reg_xpi_revdat = (uint32_t)0;
    reg_xpi_datlen = (uint32_t)1;
}

void qspi0_rd(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list) {

    reg_xpi_rdwr = (uint32_t)1;
    reg_xpi_revdat = (uint32_t)0;
    reg_xpi_flush = (uint32_t)0;
    // cmd
    reg_xpi_cmdtyp = cmdtyp;
    reg_xpi_cmdlen = cmdlen;
    reg_xpi_cmddat = cmddat;
    // adr
    reg_xpi_adrtyp = adrtyp;
    reg_xpi_adrlen = adrlen;
    reg_xpi_adrdat = adrdat;
    // dum
    reg_xpi_tdulen = dumlen;
    reg_xpi_rdulen = dumlen;
    // dat
    reg_xpi_dattyp = dattyp;
    reg_xpi_datlen = datlen;
    reg_xpi_datbit = datbit;

    reg_xpi_start = (uint32_t)1;
    for(uint32_t i = 0; i < datlen; ++i) {
        while((reg_xpi_status & (uint32_t)(1 << 4)));
        dat_list[i] = reg_xpi_rxdata;
    }
}


void qspi0_dma_xfer(uint32_t addr, uint32_t len) {
    reg_xpi_flush = (uint32_t)1;
    reg_xpi_datlen = (uint32_t)32;
    reg_xpi_mode = (uint32_t)1;
    reg_xpi_revdat = (uint32_t)1;
    reg_xpi_datbit = (uint32_t)4;
    // printf("[qspi0 dma] src addr: %x, len: %d\n", addr, len);
    // uint32_t *ptr = (uint32_t*)addr;
    // for(int i = 0; i < 32; ++i) {
    //     printf("data[%d]: %x\n", i, ptr[i]);
    // }
    dma_config((uint32_t)3, addr, (uint32_t)1, (uint32_t)&reg_xpi_txdata, (uint32_t)0, len);
    dma_start_xfer();
    // NOTE: must guarantee dma xfer done flag is clr after tx fifo empty check!
    while((reg_xpi_status & (uint32_t)(1 << 2)) == 0);
    dma_wait_done();
    reg_xpi_mode = (uint32_t)0;
    reg_xpi_flush = (uint32_t)1;
    reg_xpi_revdat = (uint32_t)0;
    reg_xpi_datlen = (uint32_t)1;
}

void qspi_dev_init() {
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
}