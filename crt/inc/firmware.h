#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef CORE_PICORV32
#define HW_CORE "picorv32"
#elif CORE_MINIRV
#define HW_CORE "minirv"
#elif CORE_MDD
#define HW_CORE "mdd(host core: picorv32)"
#else
#define HW_CORE "NONE"
#endif

#ifdef ISA_RV32E
#define SW_ISA "rv32e"
#elif ISA_RV32I
#define SW_ISA "rv32i"
#elif ISA_RV32IM
#define SW_ISA "rv32im"
#else
#define SW_ISA "NONE"
#endif

#define CPU_FREQ            72     // unit: MHz
#define UART_BPS            115200 // unit: bps
#define PSRAM_NUM           4
#define PSRAM_SCLK_MIN_FREQ 12     // unit: MHz
#define PSRAM_SCLK_MAX_FREQ 133    // unit: MHz
#define PSRAM_SCLK_FREQ     (CPU_FREQ / 2)

#define SPFS_MEM_START      0x00000000
#define SPFS_MEM_OFFST      0x1000000
#define SRAM_MEM_START      0x30000000
#define SRAM_MEM_OFFST      0x20000
#define PSRAM_MEM_START     0x40000000
#define PSRAM_MEM_OFFST     (0x800000 * PSRAM_NUM)
#define TF_CARD_START       0x50000000
#define TF_CARD_OFFST       0x10000000

// gpio
#define reg_gpio_data      (*(volatile uint32_t*)0x10000000)
#define reg_gpio_oen       (*(volatile uint32_t*)0x10000004)
#define reg_gpio_pun       (*(volatile uint32_t*)0x10000008)
#define reg_gpio_pdn       (*(volatile uint32_t*)0x1000000c)
// uart1
#define reg_uart0_clkdiv   (*(volatile uint32_t*)0x10001000)
#define reg_uart0_data     (*(volatile uint32_t*)0x10001004)
// tim0
#define reg_tim0_cfg       (*(volatile uint32_t*)0x10002000)
#define reg_tim0_val       (*(volatile uint32_t*)0x10002004)
#define reg_tim0_dat       (*(volatile uint32_t*)0x10002008)
// tim1
#define reg_tim1_cfg       (*(volatile uint32_t*)0x10003000)
#define reg_tim1_val       (*(volatile uint32_t*)0x10003004)
#define reg_tim1_dat       (*(volatile uint32_t*)0x10003008)
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
// dma(32b xfer, hardware trigger by I2S fifo, QSPI fifo)
#define reg_dma_mode        (*(volatile uint32_t*)0x10009000)
#define reg_dma_srcaddr     (*(volatile uint32_t*)0x10009004)
#define reg_dma_srcincr     (*(volatile uint32_t*)0x10009008)
#define reg_dma_dstaddr     (*(volatile uint32_t*)0x1000900C)
#define reg_dma_dstincr     (*(volatile uint32_t*)0x10009010)
#define reg_dma_xferlen     (*(volatile uint32_t*)0x10009014)
#define reg_dma_start       (*(volatile uint32_t*)0x10009018)
#define reg_dma_stop        (*(volatile uint32_t*)0x1000901C)
#define reg_dma_reset       (*(volatile uint32_t*)0x10009020)
#define reg_dma_status      (*(volatile uint32_t*)0x10009024)
#define reg_dma_fsm         (*(volatile uint32_t*)0x10009028)
// sys ctrl
#define reg_sysctrl_coresel (*(volatile uint32_t*)0x1000A000)
#define reg_sysctrl_ipsel   (*(volatile uint32_t*)0x1000A004)
#define reg_sysctrl_i2csel  (*(volatile uint32_t*)0x1000A008)
// apb
// archinfo
#define reg_archinfo_sys   (*(volatile uint32_t*)0x20001000)
#define reg_archinfo_idl   (*(volatile uint32_t*)0x20001004)
#define reg_archinfo_idh   (*(volatile uint32_t*)0x20001008)
// rng
#define reg_rng_ctrl       (*(volatile uint32_t*)0x20002000)
#define reg_rng_seed       (*(volatile uint32_t*)0x20002004)
#define reg_rng_val        (*(volatile uint32_t*)0x20002008)
// uart
#define reg_uart1_lcr      (*(volatile uint32_t*)0x20003000)
#define reg_uart1_div      (*(volatile uint32_t*)0x20003004)
#define reg_uart1_trx      (*(volatile uint32_t*)0x20003008)
#define reg_uart1_fcr      (*(volatile uint32_t*)0x2000300c)
#define reg_uart1_lsr      (*(volatile uint32_t*)0x20003010)
// pwm
#define reg_pwm_ctrl       (*(volatile uint32_t*)0x20004000)
#define reg_pwm_pscr       (*(volatile uint32_t*)0x20004004)
#define reg_pwm_cnt        (*(volatile uint32_t*)0x20004008)
#define reg_pwm_cmp        (*(volatile uint32_t*)0x2000400c)
#define reg_pwm_cr0        (*(volatile uint32_t*)0x20004010)
#define reg_pwm_cr1        (*(volatile uint32_t*)0x20004014)
#define reg_pwm_cr2        (*(volatile uint32_t*)0x20004018)
#define reg_pwm_cr3        (*(volatile uint32_t*)0x2000401c)
#define reg_pwm_stat       (*(volatile uint32_t*)0x20004020)
// ps2
#define reg_ps2_ctrl       (*(volatile uint32_t*)0x20005000)
#define reg_ps2_data       (*(volatile uint32_t*)0x20005004)
#define reg_ps2_stat       (*(volatile uint32_t*)0x20005008)
// i2c1
#define reg_i2c1_ctrl      (*(volatile uint32_t*)0x20006000)
#define reg_i2c1_pscr      (*(volatile uint32_t*)0x20006004)
#define reg_i2c1_txr       (*(volatile uint32_t*)0x20006008)
#define reg_i2c1_rxr       (*(volatile uint32_t*)0x2000600c)
#define reg_i2c1_cmd       (*(volatile uint32_t*)0x20006010)
#define reg_i2c1_sr        (*(volatile uint32_t*)0x20006014)
// qspi1
#define reg_qspi1_status   (*(volatile uint32_t*)0x20007000)
#define reg_qspi1_clkdiv   (*(volatile uint32_t*)0x20007004)
#define reg_qspi1_cmd      (*(volatile uint32_t*)0x20007008)
#define reg_qspi1_adr      (*(volatile uint32_t*)0x2000700c)
#define reg_qspi1_len      (*(volatile uint32_t*)0x20007010)
#define reg_qspi1_dum      (*(volatile uint32_t*)0x20007014)
#define reg_qspi1_txfifo   (*(volatile uint32_t*)0x20007018)
#define reg_qspi1_rxfifo   (*(volatile uint32_t*)0x20007020)
#define reg_qspi1_intcfg   (*(volatile uint32_t*)0x20007024)
#define reg_qspi1_intsta   (*(volatile uint32_t*)0x20007028)
// rtc
#define reg_rtc_ctrl       (*(volatile uint32_t*)0x20008000)
#define reg_rtc_pscr       (*(volatile uint32_t*)0x20008004)
#define reg_rtc_cnt        (*(volatile uint32_t*)0x20008008)
#define reg_rtc_alrm       (*(volatile uint32_t*)0x2000800C)
#define reg_rtc_ista       (*(volatile uint32_t*)0x20008010)
#define reg_rtc_ssta       (*(volatile uint32_t*)0x20008014)
// wdg
#define reg_wdg_ctrl       (*(volatile uint32_t*)0x20009000)
#define reg_wdg_pscr       (*(volatile uint32_t*)0x20009004)
#define reg_wdg_cnt        (*(volatile uint32_t*)0x20009008)
#define reg_wdg_cmp        (*(volatile uint32_t*)0x2000900C)
#define reg_wdg_stat       (*(volatile uint32_t*)0x20009010)
#define reg_wdg_key        (*(volatile uint32_t*)0x20009014)
#define reg_wdg_feed       (*(volatile uint32_t*)0x20009018)
// crc
#define reg_crc_ctrl       (*(volatile uint32_t*)0x2000A000)
#define reg_crc_init       (*(volatile uint32_t*)0x2000A004)
#define reg_crc_xorv       (*(volatile uint32_t*)0x2000A008)
#define reg_crc_data       (*(volatile uint32_t*)0x2000A00C)
#define reg_crc_stat       (*(volatile uint32_t*)0x2000A010)
// tim
#define reg_tim3_ctrl      (*(volatile uint32_t*)0x2000B000)
#define reg_tim3_pscr      (*(volatile uint32_t*)0x2000B004)
#define reg_tim3_cnt       (*(volatile uint32_t*)0x2000B008)
#define reg_tim3_cmp       (*(volatile uint32_t*)0x2000B00C)
#define reg_tim3_stat      (*(volatile uint32_t*)0x2000B010)

// user ip design(example)
#define reg_user_ip_reg0   (*(volatile uint32_t*)0x2000F000)
#define reg_user_ip_reg1   (*(volatile uint32_t*)0x2000F004)
#define reg_user_ip_reg2   (*(volatile uint32_t*)0x2000F008)
#endif