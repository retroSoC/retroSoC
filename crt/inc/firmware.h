#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#define CPU_FREQ             72     // unit: MHz
#define UART_BPS             115200 // unit: bps
#define PSRAM_NUM            1
#define PSRAM_SCLK_MIN_FREQ  12  // unit: Mhz
#define PSRAM_SCLK_MAX_FREQ  133 // unit: Mhz
#define PSRAM_SCLK_FREQ      (CPU_FREQ / 2)

#define SPFS_MEM_START        0x00000000
#define SPFS_MEM_OFFST        0x1000000
#define SRAM_MEM_START        0x30000000
#define SRAM_MEM_OFFST        0x20000
#define PSRAM_MEM_START       0x40000000
#define PSRAM_MEM_OFFST       0x800000
// gpio
#define reg_gpio_data         (*(volatile uint32_t*)0x10000000)
#define reg_gpio_enb          (*(volatile uint32_t*)0x10000004)
#define reg_gpio_pub          (*(volatile uint32_t*)0x10000008)
#define reg_gpio_pdb          (*(volatile uint32_t*)0x1000000c)

#define reg_uart_clkdiv       (*(volatile uint32_t*)0x10001000)
#define reg_uart_data         (*(volatile uint32_t*)0x10001004)
// tim0
#define reg_tim0_config       (*(volatile uint32_t*)0x10002000)
#define reg_tim0_value        (*(volatile uint32_t*)0x10002004)
#define reg_tim0_data         (*(volatile uint32_t*)0x10002008)
// tim1
#define reg_tim1_config       (*(volatile uint32_t*)0x10003000)
#define reg_tim1_value        (*(volatile uint32_t*)0x10003004)
#define reg_tim1_data         (*(volatile uint32_t*)0x10003008)
// psram
#define reg_psram_waitcycl    (*(volatile uint32_t*)0x10004000)
#define reg_psram_chd         (*(volatile uint32_t*)0x10004004)
// cust archinfo
#define reg_cust_archinfo_sys (*(volatile uint32_t*)0x20001000)
#define reg_cust_archinfo_idl (*(volatile uint32_t*)0x20001004)
#define reg_cust_archinfo_idh (*(volatile uint32_t*)0x20001008)
// cust rng
#define reg_cust_rng_ctrl     (*(volatile uint32_t*)0x20002000)
#define reg_cust_rng_seed     (*(volatile uint32_t*)0x20002004)
#define reg_cust_rng_val      (*(volatile uint32_t*)0x20002008)
// cust uart
#define reg_cust_uart_lcr     (*(volatile uint32_t*)0x20003000)
#define reg_cust_uart_div     (*(volatile uint32_t*)0x20003004)
#define reg_cust_uart_trx     (*(volatile uint32_t*)0x20003008)
#define reg_cust_uart_fcr     (*(volatile uint32_t*)0x2000300c)
#define reg_cust_uart_lsr     (*(volatile uint32_t*)0x20003010)
// cust pwm
#define reg_cust_pwm_ctrl     (*(volatile uint32_t*)0x20004000)
#define reg_cust_pwm_pscr     (*(volatile uint32_t*)0x20004004)
#define reg_cust_pwm_cnt      (*(volatile uint32_t*)0x20004008)
#define reg_cust_pwm_cmp      (*(volatile uint32_t*)0x2000400c)
#define reg_cust_pwm_cr0      (*(volatile uint32_t*)0x20004010)
#define reg_cust_pwm_cr1      (*(volatile uint32_t*)0x20004014)
#define reg_cust_pwm_cr2      (*(volatile uint32_t*)0x20004018)
#define reg_cust_pwm_cr3      (*(volatile uint32_t*)0x2000401c)
#define reg_cust_pwm_stat     (*(volatile uint32_t*)0x20004020)
// cust ps2
#define reg_cust_ps2_ctrl     (*(volatile uint32_t*)0x20005000)
#define reg_cust_ps2_data     (*(volatile uint32_t*)0x20005004)
#define reg_cust_ps2_stat     (*(volatile uint32_t*)0x20005008)
// cust i2c
#define reg_cust_i2c_ctrl     (*(volatile uint32_t*)0x20006000)
#define reg_cust_i2c_pscr     (*(volatile uint32_t*)0x20006004)
#define reg_cust_i2c_txr      (*(volatile uint32_t*)0x20006008)
#define reg_cust_i2c_rxr      (*(volatile uint32_t*)0x2000600c)
#define reg_cust_i2c_cmd      (*(volatile uint32_t*)0x20006010)
#define reg_cust_i2c_sr       (*(volatile uint32_t*)0x20006014)
// cust qspi
#define reg_cust_qspi_status  (*(volatile uint32_t*)0x20007000)
#define reg_cust_qspi_clkdiv  (*(volatile uint32_t*)0x20007004)
#define reg_cust_qspi_cmd     (*(volatile uint32_t*)0x20007008)
#define reg_cust_qspi_adr     (*(volatile uint32_t*)0x2000700c)
#define reg_cust_qspi_len     (*(volatile uint32_t*)0x20007010)
#define reg_cust_qspi_dum     (*(volatile uint32_t*)0x20007014)
#define reg_cust_qspi_txfifo  (*(volatile uint32_t*)0x20007018)
#define reg_cust_qspi_rxfifo  (*(volatile uint32_t*)0x20007020)
#define reg_cust_qspi_intcfg  (*(volatile uint32_t*)0x20007024)
#define reg_cust_qspi_intsta  (*(volatile uint32_t*)0x20007028)

#endif