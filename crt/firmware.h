#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

// memory map
// 0x0000_0000 - 0x0001_0000 ram(64KB)
// 0x0010_0000 - 0x01ff_ffff spfs(32MB)
// 0x0300_0000 - 0x03ff_ffff mmio
// 0x0400_0000 - 0x04ff_ffff psram(32MB)
// 0x3000_0000 - 0x3fff_ffff spfs
// memory map io definitions
#define reg_spictrl        (*(volatile uint32_t*)0x02000000)

#define reg_gpio_data      (*(volatile uint32_t*)0x03000000)
#define reg_gpio_enb       (*(volatile uint32_t*)0x03000004)
#define reg_gpio_pub       (*(volatile uint32_t*)0x03000008)
#define reg_gpio_pdb       (*(volatile uint32_t*)0x0300000c)

#define reg_uart_clkdiv    (*(volatile uint32_t*)0x03000010)
#define reg_uart_data      (*(volatile uint32_t*)0x03000014)

#define reg_spi_commconfig (*(volatile uint32_t*)0x03000018)
#define reg_spi_enables    (*(volatile uint32_t*)0x0300001c)
#define reg_spi_pll_config (*(volatile uint32_t*)0x03000020)
#define reg_spi_mfgr_id    (*(volatile uint32_t*)0x03000024)
#define reg_spi_prod_id    (*(volatile uint32_t*)0x03000028)
#define reg_spi_mask_rev   (*(volatile uint32_t*)0x0300002c)
#define reg_spi_pll_bypass (*(volatile uint32_t*)0x03000030)

#define reg_xtal_out_dest  (*(volatile uint32_t*)0x03000034)
#define reg_pll_out_dest   (*(volatile uint32_t*)0x03000038)
#define reg_trap_out_dest  (*(volatile uint32_t*)0x0300003c)
#define reg_irq7_source    (*(volatile uint32_t*)0x03000040)
#define reg_irq8_source    (*(volatile uint32_t*)0x03000044)
// tim0
#define reg_timer0_config  (*(volatile uint32_t*)0x0300005c)
#define reg_timer0_value   (*(volatile uint32_t*)0x03000060)
#define reg_timer0_data    (*(volatile uint32_t*)0x03000064)
// tim1
#define reg_timer1_config  (*(volatile uint32_t*)0x03000068)
#define reg_timer1_value   (*(volatile uint32_t*)0x0300006c)
#define reg_timer1_data    (*(volatile uint32_t*)0x03000070)
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
