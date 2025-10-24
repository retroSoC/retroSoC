#ifndef TINYQSPI_H__
#define TINYQSPI_H__

typedef struct {
    uint32_t mode;
    uint32_t nss;
    uint32_t clkdiv;
    uint32_t txub;
    uint32_t txlb;
    uint32_t rxub;
    uint32_t rxlb;
} QSPI0_InitStruct_t;

void qspi0_init(QSPI0_InitStruct_t val);

void qspi0_wr(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list);

void qspi0_rd(uint32_t cmdtyp, uint32_t cmdlen, uint32_t cmddat,
              uint32_t adrtyp, uint32_t adrlen, uint32_t adrdat,
              uint32_t dumlen,
              uint32_t dattyp, uint32_t datlen, uint32_t datbit,
              uint32_t* dat_list);

#endif