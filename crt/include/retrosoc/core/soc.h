#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/generated/memory_map.h>
#include <retrosoc/generated/user_extensions.h>

#define HW_CORE                         "Management Hazard3"

#define CPU_FREQ                        72     // unit: MHz
#define UART_BPS                        921600 // unit: bps
#define SPFS_MEM_START                  RS_SOC_FLASH_BASE
#define SPFS_MEM_OFFST                  RS_SOC_FLASH_SIZE
#define SRAM_MEM_START                  RS_SOC_SRAM_BASE
#define SRAM_MEM_OFFST                  RS_SOC_SRAM_SIZE
#define SDRAM_MEM_START                 RS_SOC_SDRAM_BASE
#define SDRAM_MEM_OFFST                 RS_SOC_SDRAM_SIZE
#define PSRAM_MEM_START                 RS_SOC_PSRAM_BASE
#define PSRAM_MEM_OFFST                 RS_SOC_PSRAM_SIZE
#define XPI_MEM_START                   RS_SOC_XPI_BASE
#define XPI_MEM_OFFST                   RS_SOC_XPI_SIZE
#define TF_CARD_START                   RS_SOC_SPISD_BASE
#define TF_CARD_OFFST                   RS_SOC_SPISD_SIZE

#define RS_SOC_REG32(base, offset)      (*(volatile uint32_t *)(uintptr_t)((base) + (offset)))

// spisd
#define reg_spisd_mode                  RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x00))
#define reg_spisd_clkdiv                RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x04))
#define reg_spisd_addr                  RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x08))
#define reg_spisd_txdata                RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x0C))
#define reg_spisd_rxdata                RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x10))
#define reg_spisd_status                RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x14))
#define reg_spisd_sync                  RS_SOC_REG32(RS_SOC_APB4_SPISD_BASE, UINT32_C(0x18))
// xpi
#define reg_xpi_cfgidx                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x00))
#define reg_xpi_accmd                   RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x04))
#define reg_xpi_mmstad                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x08))
#define reg_xpi_mmoffst                 RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x0C))
#define reg_xpi_mode                    RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x10))
#define reg_xpi_nss                     RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x14))
#define reg_xpi_clkdiv                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x18))
#define reg_xpi_rdwr                    RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x1C))
#define reg_xpi_revdat                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x20))
#define reg_xpi_txupb                   RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x24))
#define reg_xpi_txlowb                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x28))
#define reg_xpi_rxupb                   RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x2C))
#define reg_xpi_rxlowb                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x30))
#define reg_xpi_flush                   RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x34))
#define reg_xpi_cmdtyp                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x38))
#define reg_xpi_cmdlen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x3C))
#define reg_xpi_cmddat                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x40))
#define reg_xpi_adrtyp                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x44))
#define reg_xpi_adrlen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x48))
#define reg_xpi_adrdat                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x4C))
#define reg_xpi_alttyp                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x50))
#define reg_xpi_altlen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x54))
#define reg_xpi_altdat                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x58))
#define reg_xpi_tdulen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x5C))
#define reg_xpi_rdulen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x60))
#define reg_xpi_dattyp                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x64))
#define reg_xpi_datlen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x68))
#define reg_xpi_datbit                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x6C))
#define reg_xpi_hlvlen                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x70))
#define reg_xpi_txdata                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x74))
#define reg_xpi_rxdata                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x78))
#define reg_xpi_start                   RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x7C))
#define reg_xpi_status                  RS_SOC_REG32(RS_SOC_APB4_XPI_BASE, UINT32_C(0x80))
// dma(32b xfer, hardware trigger by I2S fifo, QSPI fifo)
#define reg_dma_mode                    RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x00))
#define reg_dma_srcaddr                 RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x04))
#define reg_dma_srcincr                 RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x08))
#define reg_dma_dstaddr                 RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x0C))
#define reg_dma_dstincr                 RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x10))
#define reg_dma_xferlen                 RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x14))
#define reg_dma_start                   RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x18))
#define reg_dma_stop                    RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x1C))
#define reg_dma_reset                   RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x20))
#define reg_dma_status                  RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x24))
#define reg_dma_fsm                     RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x28))
#define reg_dma_error_status            RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x2C))
#define reg_dma_error_addr              RS_SOC_REG32(RS_SOC_APB4_DMA_BASE, UINT32_C(0x30))
#define RS_SOC_DMA_ERROR_PENDING        UINT32_C(0x00000001)
#define RS_SOC_DMA_ERROR_RESPONSE_SHIFT 1U
#define RS_SOC_DMA_ERROR_RESPONSE_MASK  UINT32_C(0x0000000E)
#define reg_user_ip_reg0                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x00))
#define reg_user_ip_reg1                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x04))
#define reg_user_ip_reg2                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x08))
#define reg_user_ip_reg3                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x0C))
#define reg_user_ip_reg4                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x10))
#define reg_user_ip_reg5                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x14))
#define reg_user_ip_reg6                RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x18))
#endif
