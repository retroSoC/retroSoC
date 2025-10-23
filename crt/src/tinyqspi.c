#include <firmware.h>
#include <tinyqspi.h>


void qspi0_init(QSPI0_InitStruct_t val) {
    reg_qspi0_mode       = val.mode;
    reg_qspi0_nss        = val.nss;
    reg_qspi0_clkdiv     = val.clkdiv;
    reg_qspi0_txupbound  = val.txub;
    reg_qspi0_txlowbound = val.txlb;
    reg_qspi0_rxupbound  = val.rxub;
    reg_qspi0_rxlowbound = val.rxlb;
}

void qspi0_spi_rd(uint32_t cmdlen, uint32_t cmddat,
                  uint32_t adrlen, uint32_t adrdat,
                  uint32_t dumlen,
                  uint32_t datlen, uint32_t datbit, uint32_t* dat_list) {

    reg_qspi0_rdwr = (uint32_t)1;
    reg_qspi0_revdat = (uint32_t)0;
    reg_qspi0_flush = (uint32_t)1;
    // cmd
    if(cmdlen) reg_qspi0_cmdtyp = (uint32_t)1;
    else reg_qspi0_cmdtyp = (uint32_t)0;
    reg_qspi0_cmdlen = cmdlen;
    reg_qspi0_cmddat = cmddat;
    // adr
    if(adrlen) reg_qspi0_adrtyp = (uint32_t)1;
    else reg_qspi0_adrtyp = (uint32_t)0;
    reg_qspi0_adrlen = adrlen;
    reg_qspi0_adrdat = adrdat;
    // dum
    reg_qspi0_dumlen = dumlen;
    // dat
    reg_qspi0_dattyp = (uint32_t)1;
    reg_qspi0_datlen = datlen;
    reg_qspi0_datbit = datbit;

    reg_qspi0_start = (uint32_t)1;
    for(uint32_t i = 0; i < datlen; ++i) {
        while((reg_qspi0_status & (uint32_t)(1 << 4)));
        dat_list[i] = reg_qspi0_rxdata;
    }
}