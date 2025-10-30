#ifndef TINYQSPI_H__
#define TINYQSPI_H__

#define USE_QSPI0_DEV
#define USE_QSPI0_DMA

typedef struct {
    uint32_t mode;
    uint32_t nss;
    uint32_t clkdiv;
    uint32_t txub;
    uint32_t txlb;
    uint32_t rxub;
    uint32_t rxlb;
    uint32_t hlven;
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

void qspi0_xfer_config(
    uint32_t rdwr, uint32_t revdat, uint32_t flush,
    uint32_t cmdtyp, uint32_t cmdlen,
    uint32_t adrtyp, uint32_t adrlen,
    uint32_t dumlen,
    uint32_t dattyp, uint32_t datlen, uint32_t datbit
);

void qspi0_wr_cmd8(uint8_t dat);
void qspi0_wr_cmd16(uint16_t dat);

void qspi0_wr_dat8(uint8_t dat);
void qspi0_wr_dat16(uint16_t dat);
void qspi0_wr_data32(uint32_t* dat, uint32_t len);
void qspi0_dma_xfer(uint32_t addr, uint32_t len);

void qspi1_init();
void qspi1_wr_dat8(uint8_t dat);

void qspi1_wr_data16(uint16_t dat);
void qspi1_wr_data32(uint32_t* dat, uint32_t len);
#endif