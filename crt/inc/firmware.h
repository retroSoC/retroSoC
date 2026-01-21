#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef CORE_PICORV32
#define HW_CORE "PicoRV32"
#elif CORE_HAZARD3
#define HW_CORE "HAZARD3"
#else
#define HW_CORE "none"
#endif

#define CPU_FREQ            72     // unit: MHz
#define UART_BPS            921600 // unit: bps
#define PSRAM_NUM           4
#define PSRAM_SCLK_MIN_FREQ 12     // unit: MHz
#define PSRAM_SCLK_MAX_FREQ 133    // unit: MHz
#define PSRAM_SCLK_FREQ     (CPU_FREQ / 2)

#define SPFS_MEM_START      0x00000000
#define SPFS_MEM_OFFST      16 * 1024 * 1024
#define NMI_MEM_START       0x10000000
#define NMI_MEM_OFFST       256 * 1024 * 1024
#define APB_MEM_START       0x20000000
#define APB_MEM_OFFST       256 * 1024 * 1024
#define SRAM_MEM_START      0x30000000
#define SRAM_MEM_OFFST      128 * 1024
#define SDRAM_MEM_START     0x38000000
#define SDRAM_MEM_OFFST     64 * 1024 * 1024
#define PSRAM_MEM_START     0x40000000
#define PSRAM_MEM_OFFST     8 * 1024 * 1024 * PSRAM_NUM
#define QSPI_MEM_START      0x50000000
#define QSPI_MEM_OFFST      256 * 1024 * 1024
#define TF_CARD_START       (uint32_t)0x60000000
#define TF_CARD_OFFST       (uint32_t)0x40000000

// gpio
#define reg_gpio_oe        (*(volatile uint32_t*)0x10000000)
#define reg_gpio_cs        (*(volatile uint32_t*)0x10000004)
#define reg_gpio_pu        (*(volatile uint32_t*)0x10000008)
#define reg_gpio_pd        (*(volatile uint32_t*)0x1000000c)
#define reg_gpio_do        (*(volatile uint32_t*)0x10000010)
#define reg_gpio_di        (*(volatile uint32_t*)0x10000014)
// uart1
#define reg_uart0_clkdiv   (*(volatile uint32_t*)0x10001000)
#define reg_uart0_data     (*(volatile uint32_t*)0x10001004)
// tim0
#define reg_tim0_cfg       (*(volatile uint32_t*)0x10002000)
#define reg_tim0_rld       (*(volatile uint32_t*)0x10002004)
#define reg_tim0_val       (*(volatile uint32_t*)0x10002008)
// tim1
#define reg_tim1_cfg       (*(volatile uint32_t*)0x10003000)
#define reg_tim1_rld       (*(volatile uint32_t*)0x10003004)
#define reg_tim1_val       (*(volatile uint32_t*)0x10003008)
// psram
#define reg_psram_wait     (*(volatile uint32_t*)0x10004000)
#define reg_psram_chd      (*(volatile uint32_t*)0x10004004)
// spisd
#define reg_spisd_mode     (*(volatile uint32_t*)0x10005000)
#define reg_spisd_clkdiv   (*(volatile uint32_t*)0x10005004)
#define reg_spisd_addr     (*(volatile uint32_t*)0x10005008)
#define reg_spisd_txdata   (*(volatile uint32_t*)0x1000500C)
#define reg_spisd_rxdata   (*(volatile uint32_t*)0x10005010)
#define reg_spisd_status   (*(volatile uint32_t*)0x10005014)
#define reg_spisd_sync     (*(volatile uint32_t*)0x10005018)
// i2c0
#define reg_i2c0_clkdiv    (*(volatile uint32_t*)0x10006000)
#define reg_i2c0_devaddr   (*(volatile uint32_t*)0x10006004)
#define reg_i2c0_regaddr   (*(volatile uint32_t*)0x10006008)
#define reg_i2c0_txdata    (*(volatile uint32_t*)0x1000600C)
#define reg_i2c0_rxdata    (*(volatile uint32_t*)0x10006010)
#define reg_i2c0_xfer      (*(volatile uint32_t*)0x10006014)
#define reg_i2c0_cfg       (*(volatile uint32_t*)0x10006018)
#define reg_i2c0_status    (*(volatile uint32_t*)0x1000601C)
// i2s
#define reg_i2s_mode       (*(volatile uint32_t*)0x10007000)
#define reg_i2s_upbound    (*(volatile uint32_t*)0x10007004)
#define reg_i2s_lowbound   (*(volatile uint32_t*)0x10007008)
#define reg_i2s_recven     (*(volatile uint32_t*)0x1000700C)
#define reg_i2s_txdata     (*(volatile uint32_t*)0x10007010)
#define reg_i2s_rxdata     (*(volatile uint32_t*)0x10007014)
#define reg_i2s_status     (*(volatile uint32_t*)0x10007018)
// 1-wire
#define reg_onewire_clkdiv  (*(volatile uint32_t*)0x10008000)
#define reg_onewire_zerocnt (*(volatile uint32_t*)0x10008004)
#define reg_onewire_onecnt  (*(volatile uint32_t*)0x10008008)
#define reg_onewire_rstcnt  (*(volatile uint32_t*)0x1000800C)
#define reg_onewire_txdata  (*(volatile uint32_t*)0x10008010)
#define reg_onewire_ctrl    (*(volatile uint32_t*)0x10008014)
#define reg_onewire_status  (*(volatile uint32_t*)0x10008018)
// xpi
#define reg_qspi0_cfgidx     (*(volatile uint32_t*)0x10009000)
#define reg_qspi0_accmd      (*(volatile uint32_t*)0x10009004)
#define reg_qspi0_mmstad     (*(volatile uint32_t*)0x10009008)
#define reg_qspi0_mmoffst    (*(volatile uint32_t*)0x1000900C)
#define reg_qspi0_mode       (*(volatile uint32_t*)0x10009010)
#define reg_qspi0_nss        (*(volatile uint32_t*)0x10009014)
#define reg_qspi0_clkdiv     (*(volatile uint32_t*)0x10009018)
#define reg_qspi0_rdwr       (*(volatile uint32_t*)0x1000901C)
#define reg_qspi0_revdat     (*(volatile uint32_t*)0x10009020)
#define reg_qspi0_txupb      (*(volatile uint32_t*)0x10009024)
#define reg_qspi0_txlowb     (*(volatile uint32_t*)0x10009028)
#define reg_qspi0_rxupb      (*(volatile uint32_t*)0x1000902C)
#define reg_qspi0_rxlowb     (*(volatile uint32_t*)0x10009030)
#define reg_qspi0_flush      (*(volatile uint32_t*)0x10009034)
#define reg_qspi0_cmdtyp     (*(volatile uint32_t*)0x10009038)
#define reg_qspi0_cmdlen     (*(volatile uint32_t*)0x1000903C)
#define reg_qspi0_cmddat     (*(volatile uint32_t*)0x10009040)
#define reg_qspi0_adrtyp     (*(volatile uint32_t*)0x10009044)
#define reg_qspi0_adrlen     (*(volatile uint32_t*)0x10009048)
#define reg_qspi0_adrdat     (*(volatile uint32_t*)0x1000904C)
#define reg_qspi0_alttyp     (*(volatile uint32_t*)0x10009050)
#define reg_qspi0_altlen     (*(volatile uint32_t*)0x10009054)
#define reg_qspi0_altdat     (*(volatile uint32_t*)0x10009058)
#define reg_qspi0_tdulen     (*(volatile uint32_t*)0x1000905C)
#define reg_qspi0_rdulen     (*(volatile uint32_t*)0x10009060)
#define reg_qspi0_dattyp     (*(volatile uint32_t*)0x10009064)
#define reg_qspi0_datlen     (*(volatile uint32_t*)0x10009068)
#define reg_qspi0_datbit     (*(volatile uint32_t*)0x1000906C)
#define reg_qspi0_hlvlen     (*(volatile uint32_t*)0x10009070)
#define reg_qspi0_txdata     (*(volatile uint32_t*)0x10009074)
#define reg_qspi0_rxdata     (*(volatile uint32_t*)0x10009078)
#define reg_qspi0_start      (*(volatile uint32_t*)0x1000907C)
#define reg_qspi0_status     (*(volatile uint32_t*)0x10009080)
// dma(32b xfer, hardware trigger by I2S fifo, QSPI fifo)
#define reg_dma_mode        (*(volatile uint32_t*)0x1000A000)
#define reg_dma_srcaddr     (*(volatile uint32_t*)0x1000A004)
#define reg_dma_srcincr     (*(volatile uint32_t*)0x1000A008)
#define reg_dma_dstaddr     (*(volatile uint32_t*)0x1000A00C)
#define reg_dma_dstincr     (*(volatile uint32_t*)0x1000A010)
#define reg_dma_xferlen     (*(volatile uint32_t*)0x1000A014)
#define reg_dma_start       (*(volatile uint32_t*)0x1000A018)
#define reg_dma_stop        (*(volatile uint32_t*)0x1000A01C)
#define reg_dma_reset       (*(volatile uint32_t*)0x1000A020)
#define reg_dma_status      (*(volatile uint32_t*)0x1000A024)
#define reg_dma_fsm         (*(volatile uint32_t*)0x1000A028)
// sys ctrl
#define reg_sysctrl_coresel  (*(volatile uint32_t*)0x1000B000)
#define reg_sysctrl_ipsel    (*(volatile uint32_t*)0x1000B004)
#define reg_sysctrl_i2csel   (*(volatile uint32_t*)0x1000B008)
#define reg_sysctrl_qspicsel (*(volatile uint32_t*)0x1000B00C)
// clint
#define reg_clint_mtimel     (*(volatile uint32_t*)0x1000C000)
#define reg_clint_mtimeh     (*(volatile uint32_t*)0x1000C004)
#define reg_clint_mtimecmpl  (*(volatile uint32_t*)0x1000C008)
#define reg_clint_mtimecmph  (*(volatile uint32_t*)0x1000C00C)
#define reg_clint_msip       (*(volatile uint32_t*)0x1000C010)
#define reg_clint_clkdiv     (*(volatile uint32_t*)0x1000C014)
// sdram
#define reg_sdram_cfg        (*(volatile uint32_t*)0x1000D000)
// dvp
#define reg_dvp_cfg          (*(volatile uint32_t*)0x1000E000)
// apb
// archinfo
#define reg_archinfo_sys   (*(volatile uint32_t*)0x20000000)
#define reg_archinfo_idl   (*(volatile uint32_t*)0x20000004)
#define reg_archinfo_idh   (*(volatile uint32_t*)0x20000008)
// rng
#define reg_rng_ctrl       (*(volatile uint32_t*)0x20001000)
#define reg_rng_seed       (*(volatile uint32_t*)0x20001004)
#define reg_rng_val        (*(volatile uint32_t*)0x20001008)
// uart
#define reg_uart1_lcr      (*(volatile uint32_t*)0x20002000)
#define reg_uart1_div      (*(volatile uint32_t*)0x20002004)
#define reg_uart1_trx      (*(volatile uint32_t*)0x20002008)
#define reg_uart1_fcr      (*(volatile uint32_t*)0x2000200c)
#define reg_uart1_lsr      (*(volatile uint32_t*)0x20002010)
// pwm
#define reg_pwm_ctrl       (*(volatile uint32_t*)0x20003000)
#define reg_pwm_pscr       (*(volatile uint32_t*)0x20003004)
#define reg_pwm_cnt        (*(volatile uint32_t*)0x20003008)
#define reg_pwm_cmp        (*(volatile uint32_t*)0x2000300c)
#define reg_pwm_cr0        (*(volatile uint32_t*)0x20003010)
#define reg_pwm_cr1        (*(volatile uint32_t*)0x20003014)
#define reg_pwm_cr2        (*(volatile uint32_t*)0x20003018)
#define reg_pwm_cr3        (*(volatile uint32_t*)0x2000301c)
#define reg_pwm_stat       (*(volatile uint32_t*)0x20003020)
// ps2
#define reg_ps2_ctrl       (*(volatile uint32_t*)0x20004000)
#define reg_ps2_data       (*(volatile uint32_t*)0x20004004)
#define reg_ps2_stat       (*(volatile uint32_t*)0x20004008)
// rtc
#define reg_rtc_ctrl       (*(volatile uint32_t*)0x20005000)
#define reg_rtc_pscr       (*(volatile uint32_t*)0x20005004)
#define reg_rtc_cnt        (*(volatile uint32_t*)0x20005008)
#define reg_rtc_alrm       (*(volatile uint32_t*)0x2000500C)
#define reg_rtc_ista       (*(volatile uint32_t*)0x20005010)
#define reg_rtc_ssta       (*(volatile uint32_t*)0x20005014)
// wdg
#define reg_wdg_ctrl       (*(volatile uint32_t*)0x20006000)
#define reg_wdg_pscr       (*(volatile uint32_t*)0x20006004)
#define reg_wdg_cnt        (*(volatile uint32_t*)0x20006008)
#define reg_wdg_cmp        (*(volatile uint32_t*)0x2000600C)
#define reg_wdg_stat       (*(volatile uint32_t*)0x20006010)
#define reg_wdg_key        (*(volatile uint32_t*)0x20006014)
#define reg_wdg_feed       (*(volatile uint32_t*)0x20006018)
// crc
#define reg_crc_ctrl       (*(volatile uint32_t*)0x20007000)
#define reg_crc_init       (*(volatile uint32_t*)0x20007004)
#define reg_crc_xorv       (*(volatile uint32_t*)0x20007008)
#define reg_crc_data       (*(volatile uint32_t*)0x2000700C)
#define reg_crc_stat       (*(volatile uint32_t*)0x20007010)
// tim3
#define reg_tim3_ctrl      (*(volatile uint32_t*)0x20008000)
#define reg_tim3_pscr      (*(volatile uint32_t*)0x20008004)
#define reg_tim3_cnt       (*(volatile uint32_t*)0x20008008)
#define reg_tim3_cmp       (*(volatile uint32_t*)0x2000800C)
#define reg_tim3_stat      (*(volatile uint32_t*)0x20008010)
// user ip design(example)
#define reg_user_ip_reg0   (*(volatile uint32_t*)0x2000F000)
#define reg_user_ip_reg1   (*(volatile uint32_t*)0x2000F004)
#define reg_user_ip_reg2   (*(volatile uint32_t*)0x2000F008)
#define reg_user_ip_reg3   (*(volatile uint32_t*)0x2000F00C)
#define reg_user_ip_reg4   (*(volatile uint32_t*)0x2000F010)
#define reg_user_ip_reg5   (*(volatile uint32_t*)0x2000F014)
#define reg_user_ip_reg6   (*(volatile uint32_t*)0x2000F018)
// ... user custom area ...
#endif