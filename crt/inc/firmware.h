#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#define CPU_FREQ             64     // unit: MHz
#define UART_BPS             115200 // unit: bps
#define PSRAM_NUM            1
#define PSRAM_SCLK_MIN_FREQ  12  // unit: Mhz
#define PSRAM_SCLK_MAX_FREQ  133 // unit: Mhz
#define PSRAM_SCLK_FREQ      (CPU_FREQ / 2)

#define SPFS_MEM_START        0x30000000
#define SPFS_MEM_OFFST        0x1000000
#define SRAM_MEM_START        0x00000000
#define SRAM_MEM_OFFST        0x20000
#define PSRAM_MEM_START       0x04000000
#define PSRAM_MEM_OFFST       0x800000
// gpio
#define reg_gpio_data         (*(volatile uint32_t*)0x02000000)
#define reg_gpio_enb          (*(volatile uint32_t*)0x02000004)
#define reg_gpio_pub          (*(volatile uint32_t*)0x02000008)
#define reg_gpio_pdb          (*(volatile uint32_t*)0x0200000c)

#define reg_uart_clkdiv       (*(volatile uint32_t*)0x02001000)
#define reg_uart_data         (*(volatile uint32_t*)0x02001004)
// tim0
#define reg_tim0_config       (*(volatile uint32_t*)0x02002000)
#define reg_tim0_value        (*(volatile uint32_t*)0x02002004)
#define reg_tim0_data         (*(volatile uint32_t*)0x02002008)
// tim1
#define reg_tim1_config       (*(volatile uint32_t*)0x02003000)
#define reg_tim1_value        (*(volatile uint32_t*)0x02003004)
#define reg_tim1_data         (*(volatile uint32_t*)0x02003008)
// psram
#define reg_psram_waitcycl    (*(volatile uint32_t*)0x02004000)
#define reg_psram_chd         (*(volatile uint32_t*)0x02004004)
// cust archinfo
#define reg_cust_archinfo_sys (*(volatile uint32_t*)0x03001000)
#define reg_cust_archinfo_idl (*(volatile uint32_t*)0x03001004)
#define reg_cust_archinfo_idh (*(volatile uint32_t*)0x03001008)
// cust rng
#define reg_cust_rng_ctrl     (*(volatile uint32_t*)0x03002000)
#define reg_cust_rng_seed     (*(volatile uint32_t*)0x03002004)
#define reg_cust_rng_val      (*(volatile uint32_t*)0x03002008)
// cust uart
#define reg_cust_uart_lcr     (*(volatile uint32_t*)0x03003000)
#define reg_cust_uart_div     (*(volatile uint32_t*)0x03003004)
#define reg_cust_uart_trx     (*(volatile uint32_t*)0x03003008)
#define reg_cust_uart_fcr     (*(volatile uint32_t*)0x0300300c)
#define reg_cust_uart_lsr     (*(volatile uint32_t*)0x03003010)
// cust pwm
#define reg_cust_pwm_ctrl     (*(volatile uint32_t*)0x03004000)
#define reg_cust_pwm_pscr     (*(volatile uint32_t*)0x03004004)
#define reg_cust_pwm_cnt      (*(volatile uint32_t*)0x03004008)
#define reg_cust_pwm_cmp      (*(volatile uint32_t*)0x0300400c)
#define reg_cust_pwm_cr0      (*(volatile uint32_t*)0x03004010)
#define reg_cust_pwm_cr1      (*(volatile uint32_t*)0x03004014)
#define reg_cust_pwm_cr2      (*(volatile uint32_t*)0x03004018)
#define reg_cust_pwm_cr3      (*(volatile uint32_t*)0x0300401c)
#define reg_cust_pwm_stat     (*(volatile uint32_t*)0x03004020)
// cust ps2
#define reg_cust_ps2_ctrl     (*(volatile uint32_t*)0x03005000)
#define reg_cust_ps2_data     (*(volatile uint32_t*)0x03005004)
#define reg_cust_ps2_stat     (*(volatile uint32_t*)0x03005008)
// cust i2c
#define reg_cust_i2c_ctrl     (*(volatile uint32_t*)0x03006000)
#define reg_cust_i2c_pscr     (*(volatile uint32_t*)0x03006004)
#define reg_cust_i2c_txr      (*(volatile uint32_t*)0x03006008)
#define reg_cust_i2c_rxr      (*(volatile uint32_t*)0x0300600c)
#define reg_cust_i2c_cmd      (*(volatile uint32_t*)0x03006010)
#define reg_cust_i2c_sr       (*(volatile uint32_t*)0x03006014)
// cust qspi
#define reg_cust_qspi_status  (*(volatile uint32_t*)0x03007000)
#define reg_cust_qspi_clkdiv  (*(volatile uint32_t*)0x03007004)
#define reg_cust_qspi_cmd     (*(volatile uint32_t*)0x03007008)
#define reg_cust_qspi_adr     (*(volatile uint32_t*)0x0300700c)
#define reg_cust_qspi_len     (*(volatile uint32_t*)0x03007010)
#define reg_cust_qspi_dum     (*(volatile uint32_t*)0x03007014)
#define reg_cust_qspi_txfifo  (*(volatile uint32_t*)0x03007018)
#define reg_cust_qspi_rxfifo  (*(volatile uint32_t*)0x03007020)
#define reg_cust_qspi_intcfg  (*(volatile uint32_t*)0x03007024)
#define reg_cust_qspi_intsta  (*(volatile uint32_t*)0x03007028)

#endif