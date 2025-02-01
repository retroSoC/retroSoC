#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

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

#define reg_spi_config     (*(volatile uint32_t*)0x03000048)
#define reg_spi_data       (*(volatile uint32_t*)0x0300004c)

// NOTE: "config" subsumes "control" and "prescale" fields.
#define reg_i2c_config     (*(volatile uint32_t*)0x03000050)
#define reg_i2c_prescale   (*(volatile uint16_t*)0x03000050)
#define reg_i2c_control    (*(volatile uint16_t*)0x03000052)
// NOTE: "status" and "command" are the same byte (one read, one write)
#define reg_i2c_status     (*(volatile uint32_t*)0x03000054)
#define reg_i2c_command    (*(volatile uint32_t*)0x03000054)
#define reg_i2c_data       (*(volatile uint32_t*)0x03000058)

#define reg_timer0_config  (*(volatile uint32_t*)0x0300005c)
#define reg_timer0_value   (*(volatile uint32_t*)0x03000060)
#define reg_timer0_data    (*(volatile uint32_t*)0x03000064)

#define reg_timer1_config  (*(volatile uint32_t*)0x03000068)
#define reg_timer1_value   (*(volatile uint32_t*)0x0300006c)
#define reg_timer1_data    (*(volatile uint32_t*)0x03000070)

#define reg_archinfo_sys   (*(volatile uint32_t*)0x03001000)
#define reg_archinfo_idl   (*(volatile uint32_t*)0x03001004)
#define reg_archinfo_idh   (*(volatile uint32_t*)0x03001008)

#define reg_rng_ctrl       (*(volatile uint32_t*)0x03002000)
#define reg_rng_seed       (*(volatile uint32_t*)0x03002004)
#define reg_rng_val        (*(volatile uint32_t*)0x03002008)

// command register bits
// bit 7 = start
// bit 6 = stop
// bit 5 = read
// bit 4 = write

// control register bits
// bit 27 = acknowledge
// bit 24 = interrupt acknowledge
// bit 23 = enable
// bit 22 = interrupt enable

// bits 15-0:  clock prescaler
#define     I2C_CMD_STA         0x80
#define     I2C_CMD_STO         0x40
#define     I2C_CMD_RD          0x20
#define     I2C_CMD_WR          0x10
#define     I2C_CMD_ACK         0x08
#define     I2C_CMD_IACK        0x01

#define     I2C_CTRL_EN         0x80
#define     I2C_CTRL_IEN        0x40

// status regiter bits:
// bit 7 = receive acknowledge
// bit 6 = busy (start signal detected)
// bit 5 = arbitration lost
// bit 1 = transfer in progress
// bit 0 = interrupt flag
#define     I2C_STAT_RXACK      0x80
#define     I2C_STAT_BUSY       0x40
#define     I2C_STAT_AL         0x20
#define     I2C_STAT_TIP        0x02
#define     I2C_STAT_IF         0x01

#endif
