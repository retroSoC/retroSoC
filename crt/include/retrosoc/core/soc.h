#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/generated/memory_map.h>
#include <retrosoc/generated/user_extensions.h>

#define HW_CORE                         "Management Hazard3"

#define CPU_FREQ                        72     // unit: MHz
#define UART_BPS                        921600 // unit: bps
#define PSRAM_NUM                       4
#define PSRAM_SCLK_MIN_FREQ             12  // unit: MHz
#define PSRAM_SCLK_MAX_FREQ             133 // unit: MHz
#define PSRAM_SCLK_FREQ                 (CPU_FREQ / 2)

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

// gpio
#define reg_gpio_oe                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x00))
#define reg_gpio_cs                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x04))
#define reg_gpio_pu                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x08))
#define reg_gpio_pd                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x0C))
#define reg_gpio_do                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x10))
#define reg_gpio_di                     RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x14))
#define reg_gpio_ien                    RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x18))
#define reg_gpio_itype0                 RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x1C))
#define reg_gpio_itype1                 RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x20))
#define reg_gpio_istat                  RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x24))
#define reg_gpio_iofcfg                 RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x28))
#define reg_gpio_pinmux                 RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x2C))
#define reg_gpio_user_sel               RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x30))
#define reg_gpio_user_lock              RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x34))
#define reg_gpio_user_status            RS_SOC_REG32(RS_SOC_RIBP_GPIO_BASE, UINT32_C(0x38))
// uart0
#define reg_uart0_clkdiv                RS_SOC_REG32(RS_SOC_RIBP_UART0_BASE, UINT32_C(0x00))
#define reg_uart0_data                  RS_SOC_REG32(RS_SOC_RIBP_UART0_BASE, UINT32_C(0x04))
// tim0
#define reg_tim0_cfg                    RS_SOC_REG32(RS_SOC_RIBP_TIM0_BASE, UINT32_C(0x00))
#define reg_tim0_rld                    RS_SOC_REG32(RS_SOC_RIBP_TIM0_BASE, UINT32_C(0x04))
#define reg_tim0_val                    RS_SOC_REG32(RS_SOC_RIBP_TIM0_BASE, UINT32_C(0x08))
// tim1
#define reg_tim1_cfg                    RS_SOC_REG32(RS_SOC_RIBP_TIM1_BASE, UINT32_C(0x00))
#define reg_tim1_rld                    RS_SOC_REG32(RS_SOC_RIBP_TIM1_BASE, UINT32_C(0x04))
#define reg_tim1_val                    RS_SOC_REG32(RS_SOC_RIBP_TIM1_BASE, UINT32_C(0x08))
// psram
#define reg_psram_wait                  RS_SOC_REG32(RS_SOC_RIBP_PSRAM_BASE, UINT32_C(0x00))
#define reg_psram_chd                   RS_SOC_REG32(RS_SOC_RIBP_PSRAM_BASE, UINT32_C(0x04))
#define reg_psram_init                  RS_SOC_REG32(RS_SOC_RIBP_PSRAM_BASE, UINT32_C(0x08))
// spisd
#define reg_spisd_mode                  RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x00))
#define reg_spisd_clkdiv                RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x04))
#define reg_spisd_addr                  RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x08))
#define reg_spisd_txdata                RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x0C))
#define reg_spisd_rxdata                RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x10))
#define reg_spisd_status                RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x14))
#define reg_spisd_sync                  RS_SOC_REG32(RS_SOC_RIBP_SPISD_BASE, UINT32_C(0x18))
// i2c0
#define reg_i2c0_clkdiv                 RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x00))
#define reg_i2c0_devaddr                RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x04))
#define reg_i2c0_regaddr                RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x08))
#define reg_i2c0_txdata                 RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x0C))
#define reg_i2c0_rxdata                 RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x10))
#define reg_i2c0_xfer                   RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x14))
#define reg_i2c0_cfg                    RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x18))
#define reg_i2c0_status                 RS_SOC_REG32(RS_SOC_RIBP_I2C0_BASE, UINT32_C(0x1C))
// i2s
#define reg_i2s_mode                    RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x00))
#define reg_i2s_format                  RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x04))
#define reg_i2s_upbound                 RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x08))
#define reg_i2s_lowbound                RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x0C))
#define reg_i2s_recven                  RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x10))
#define reg_i2s_txdata                  RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x14))
#define reg_i2s_rxdata                  RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x18))
#define reg_i2s_status                  RS_SOC_REG32(RS_SOC_RIBP_I2S_BASE, UINT32_C(0x1C))
// onewire
#define reg_onewire_clkdiv              RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x00))
#define reg_onewire_zerocnt             RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x04))
#define reg_onewire_onecnt              RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x08))
#define reg_onewire_rstcnt              RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x0C))
#define reg_onewire_txdata              RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x10))
#define reg_onewire_ctrl                RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x14))
#define reg_onewire_status              RS_SOC_REG32(RS_SOC_RIBP_ONEWIRE_BASE, UINT32_C(0x18))
// xpi
#define reg_xpi_cfgidx                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x00))
#define reg_xpi_accmd                   RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x04))
#define reg_xpi_mmstad                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x08))
#define reg_xpi_mmoffst                 RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x0C))
#define reg_xpi_mode                    RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x10))
#define reg_xpi_nss                     RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x14))
#define reg_xpi_clkdiv                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x18))
#define reg_xpi_rdwr                    RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x1C))
#define reg_xpi_revdat                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x20))
#define reg_xpi_txupb                   RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x24))
#define reg_xpi_txlowb                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x28))
#define reg_xpi_rxupb                   RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x2C))
#define reg_xpi_rxlowb                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x30))
#define reg_xpi_flush                   RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x34))
#define reg_xpi_cmdtyp                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x38))
#define reg_xpi_cmdlen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x3C))
#define reg_xpi_cmddat                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x40))
#define reg_xpi_adrtyp                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x44))
#define reg_xpi_adrlen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x48))
#define reg_xpi_adrdat                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x4C))
#define reg_xpi_alttyp                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x50))
#define reg_xpi_altlen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x54))
#define reg_xpi_altdat                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x58))
#define reg_xpi_tdulen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x5C))
#define reg_xpi_rdulen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x60))
#define reg_xpi_dattyp                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x64))
#define reg_xpi_datlen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x68))
#define reg_xpi_datbit                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x6C))
#define reg_xpi_hlvlen                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x70))
#define reg_xpi_txdata                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x74))
#define reg_xpi_rxdata                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x78))
#define reg_xpi_start                   RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x7C))
#define reg_xpi_status                  RS_SOC_REG32(RS_SOC_RIBP_XPI_BASE, UINT32_C(0x80))
// dma(32b xfer, hardware trigger by I2S fifo, QSPI fifo)
#define reg_dma_mode                    RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x00))
#define reg_dma_srcaddr                 RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x04))
#define reg_dma_srcincr                 RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x08))
#define reg_dma_dstaddr                 RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x0C))
#define reg_dma_dstincr                 RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x10))
#define reg_dma_xferlen                 RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x14))
#define reg_dma_start                   RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x18))
#define reg_dma_stop                    RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x1C))
#define reg_dma_reset                   RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x20))
#define reg_dma_status                  RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x24))
#define reg_dma_fsm                     RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x28))
#define reg_dma_error_status            RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x2C))
#define reg_dma_error_addr              RS_SOC_REG32(RS_SOC_RIBP_DMA_BASE, UINT32_C(0x30))
#define RS_SOC_DMA_ERROR_PENDING        UINT32_C(0x00000001)
#define RS_SOC_DMA_ERROR_RESPONSE_SHIFT 1U
#define RS_SOC_DMA_ERROR_RESPONSE_MASK  UINT32_C(0x0000000E)
// sys ctrl
#define RS_SOC_SYSCTRL_REG32(offset)    RS_SOC_REG32(RS_SOC_RIBP_SYSCTRL_BASE, (offset))
#define reg_sysctrl_coresel             RS_SOC_REG32(RS_SOC_RIBP_SYSCTRL_BASE, UINT32_C(0x00))
#define reg_sysctrl_ipsel               RS_SOC_REG32(RS_SOC_RIBP_SYSCTRL_BASE, UINT32_C(0x04))
#define reg_sysctrl_pll_cfg             RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PLL_CFG_OFFSET)
#define reg_sysctrl_pll_cmd             RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PLL_CMD_OFFSET)
/* Status: bit 0 pending (W1C), bit 1 write, bits 3:2 reason (1 unmapped, 2 reserved). */
#define reg_sysctrl_bus_fault_status    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_FAULT_STATUS_OFFSET)
#define reg_sysctrl_bus_fault_addr      RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_FAULT_ADDR_OFFSET)
#define reg_sysctrl_bus_fault_count     RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_FAULT_COUNT_OFFSET)
#define reg_sysctrl_pll_status          RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PLL_STATUS_OFFSET)
#define reg_sysctrl_user_core_reset     RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_USER_CORE_RESET_OFFSET)
#define reg_sysctrl_user_core_status    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_USER_CORE_STATUS_OFFSET)
#define reg_sysctrl_bus_fault_master    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_FAULT_MASTER_OFFSET)
#define reg_sysctrl_bus_fault_detail    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_FAULT_DETAIL_OFFSET)
#define reg_sysctrl_perf_ctrl           RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_CTRL_OFFSET)
#define reg_sysctrl_perf_mgmt_wait_lo   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_mgmt_wait_hi   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_user_wait_lo   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_USER_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_user_wait_hi   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_USER_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_dma_wait_lo    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_DMA_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_dma_wait_hi    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_DMA_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_ribp_wait_lo   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_RIBP_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_ribp_wait_hi   RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_RIBP_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_apb_wait_lo    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_APB_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_apb_wait_hi    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_APB_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_sdram_wait_lo                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_sdram_wait_hi                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_psram_wait_lo                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_psram_wait_hi                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET)
#define reg_sysctrl_perf_flash_wait_lo                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET)
#define reg_sysctrl_perf_flash_wait_hi                                                             \
    RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET)
#define reg_sysctrl_test_status            RS_SOC_SYSCTRL_REG32(RS_SOC_SYSCTRL_TEST_STATUS_OFFSET)
#define RS_SOC_TEST_STATUS_VALID           UINT32_C(0x80000000)
#define RS_SOC_TEST_STATUS_CODE_SHIFT      8U
#define RS_SOC_TEST_STATUS_PASS            UINT32_C(0x00000001)
#define RS_SOC_BUS_FAULT_PENDING           UINT32_C(0x00000001)
#define RS_SOC_BUS_FAULT_WRITE             UINT32_C(0x00000002)
#define RS_SOC_BUS_FAULT_REASON_MASK       UINT32_C(0x0000000C)
#define RS_SOC_BUS_FAULT_REASON_UNMAPPED   UINT32_C(0x00000004)
#define RS_SOC_BUS_FAULT_REASON_RESERVED   UINT32_C(0x00000008)
#define RS_SOC_BUS_FAULT_RESPONSE_OK       UINT32_C(0x00000000)
#define RS_SOC_BUS_FAULT_RESPONSE_DECERR   UINT32_C(0x00000001)
#define RS_SOC_BUS_FAULT_RESPONSE_PROTERR  UINT32_C(0x00000002)
#define RS_SOC_BUS_FAULT_RESPONSE_SLVERR   UINT32_C(0x00000003)
#define RS_SOC_BUS_FAULT_RESPONSE_TIMEOUT  UINT32_C(0x00000004)
#define RS_SOC_BUS_FAULT_RESPONSE_RESERVED UINT32_C(0x00000005)
#define RS_SOC_PERF_CTRL_ENABLE            UINT32_C(0x00000001)
#define RS_SOC_PERF_CTRL_CLEAR             UINT32_C(0x00000002)
#define RS_SOC_PERF_CTRL_SNAPSHOT          UINT32_C(0x00000004)
// clint
#define reg_clint_mtimel                   RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x00))
#define reg_clint_mtimeh                   RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x04))
#define reg_clint_mtimecmpl                RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x08))
#define reg_clint_mtimecmph                RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x0C))
#define reg_clint_msip                     RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x10))
#define reg_clint_clkdiv                   RS_SOC_REG32(RS_SOC_RIBP_CLINT_BASE, UINT32_C(0x14))
// sdram
#define reg_sdram_clkdiv                   RS_SOC_REG32(RS_SOC_RIBP_SDRAM_BASE, UINT32_C(0x00))
#define reg_sdram_cfg                      RS_SOC_REG32(RS_SOC_RIBP_SDRAM_BASE, UINT32_C(0x04))
// dvp
#define reg_dvp_recven                     RS_SOC_REG32(RS_SOC_RIBP_DVP_BASE, UINT32_C(0x00))
#define reg_dvp_rxdata                     RS_SOC_REG32(RS_SOC_RIBP_DVP_BASE, UINT32_C(0x04))
#define reg_dvp_status                     RS_SOC_REG32(RS_SOC_RIBP_DVP_BASE, UINT32_C(0x08))
// i2c1
#define reg_i2c1_clkdiv                    RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x00))
#define reg_i2c1_devaddr                   RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x04))
#define reg_i2c1_regaddr                   RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x08))
#define reg_i2c1_txdata                    RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x0C))
#define reg_i2c1_rxdata                    RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x10))
#define reg_i2c1_xfer                      RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x14))
#define reg_i2c1_cfg                       RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x18))
#define reg_i2c1_status                    RS_SOC_REG32(RS_SOC_RIBP_I2C1_BASE, UINT32_C(0x1C))
// archinfo
#define reg_archinfo_sys                   RS_SOC_REG32(RS_SOC_APB_ARCHINFO_BASE, UINT32_C(0x00))
#define reg_archinfo_idl                   RS_SOC_REG32(RS_SOC_APB_ARCHINFO_BASE, UINT32_C(0x04))
#define reg_archinfo_idh                   RS_SOC_REG32(RS_SOC_APB_ARCHINFO_BASE, UINT32_C(0x08))
// rng
#define reg_rng_ctrl                       RS_SOC_REG32(RS_SOC_APB_RNG_BASE, UINT32_C(0x00))
#define reg_rng_seed                       RS_SOC_REG32(RS_SOC_APB_RNG_BASE, UINT32_C(0x04))
#define reg_rng_val                        RS_SOC_REG32(RS_SOC_APB_RNG_BASE, UINT32_C(0x08))
// uart
#define reg_uart1_lcr                      RS_SOC_REG32(RS_SOC_APB_UART1_BASE, UINT32_C(0x00))
#define reg_uart1_div                      RS_SOC_REG32(RS_SOC_APB_UART1_BASE, UINT32_C(0x04))
#define reg_uart1_trx                      RS_SOC_REG32(RS_SOC_APB_UART1_BASE, UINT32_C(0x08))
#define reg_uart1_fcr                      RS_SOC_REG32(RS_SOC_APB_UART1_BASE, UINT32_C(0x0C))
#define reg_uart1_lsr                      RS_SOC_REG32(RS_SOC_APB_UART1_BASE, UINT32_C(0x10))
// pwm
#define reg_pwm_ctrl                       RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x00))
#define reg_pwm_pscr                       RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x04))
#define reg_pwm_cnt                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x08))
#define reg_pwm_cmp                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x0C))
#define reg_pwm_cr0                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x10))
#define reg_pwm_cr1                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x14))
#define reg_pwm_cr2                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x18))
#define reg_pwm_cr3                        RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x1C))
#define reg_pwm_stat                       RS_SOC_REG32(RS_SOC_APB_PWM_BASE, UINT32_C(0x20))
// ps2
#define reg_ps2_ctrl                       RS_SOC_REG32(RS_SOC_APB_PS2_BASE, UINT32_C(0x00))
#define reg_ps2_data                       RS_SOC_REG32(RS_SOC_APB_PS2_BASE, UINT32_C(0x04))
#define reg_ps2_stat                       RS_SOC_REG32(RS_SOC_APB_PS2_BASE, UINT32_C(0x08))
// rtc
#define reg_rtc_ctrl                       RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x00))
#define reg_rtc_pscr                       RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x04))
#define reg_rtc_cnt                        RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x08))
#define reg_rtc_alrm                       RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x0C))
#define reg_rtc_ista                       RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x10))
#define reg_rtc_ssta                       RS_SOC_REG32(RS_SOC_APB_RTC_BASE, UINT32_C(0x14))
// wdg
#define reg_wdg_ctrl                       RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x00))
#define reg_wdg_pscr                       RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x04))
#define reg_wdg_cnt                        RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x08))
#define reg_wdg_cmp                        RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x0C))
#define reg_wdg_stat                       RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x10))
#define reg_wdg_key                        RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x14))
#define reg_wdg_feed                       RS_SOC_REG32(RS_SOC_APB_WDG_BASE, UINT32_C(0x18))
// crc
#define reg_crc_ctrl                       RS_SOC_REG32(RS_SOC_APB_CRC_BASE, UINT32_C(0x00))
#define reg_crc_init                       RS_SOC_REG32(RS_SOC_APB_CRC_BASE, UINT32_C(0x04))
#define reg_crc_xorv                       RS_SOC_REG32(RS_SOC_APB_CRC_BASE, UINT32_C(0x08))
#define reg_crc_data                       RS_SOC_REG32(RS_SOC_APB_CRC_BASE, UINT32_C(0x0C))
#define reg_crc_stat                       RS_SOC_REG32(RS_SOC_APB_CRC_BASE, UINT32_C(0x10))
// tim3
#define reg_tim3_ctrl                      RS_SOC_REG32(RS_SOC_APB_TMR_BASE, UINT32_C(0x00))
#define reg_tim3_pscr                      RS_SOC_REG32(RS_SOC_APB_TMR_BASE, UINT32_C(0x04))
#define reg_tim3_cnt                       RS_SOC_REG32(RS_SOC_APB_TMR_BASE, UINT32_C(0x08))
#define reg_tim3_cmp                       RS_SOC_REG32(RS_SOC_APB_TMR_BASE, UINT32_C(0x0C))
#define reg_tim3_stat                      RS_SOC_REG32(RS_SOC_APB_TMR_BASE, UINT32_C(0x10))
#define reg_user_ip_reg0                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x00))
#define reg_user_ip_reg1                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x04))
#define reg_user_ip_reg2                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x08))
#define reg_user_ip_reg3                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x0C))
#define reg_user_ip_reg4                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x10))
#define reg_user_ip_reg5                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x14))
#define reg_user_ip_reg6                   RS_SOC_REG32(RS_SOC_APB_USER_IP_BASE, UINT32_C(0x18))
#endif
