#ifndef _RETROSOC_H_
#define _RETROSOC_H_

#include <stdint.h>
#include <stdbool.h>

// memory map definitions
#define reg_spictrl        (*(volatile uint32_t*)0x02000000)
#define reg_uart_clkdiv    (*(volatile uint32_t*)0x03000078)
#define reg_uart_data      (*(volatile uint32_t*)0x0300007c)
// NOTE: "config" subsumes "control" and "prescale" fields.
#define reg_i2c_config     (*(volatile uint32_t*)0x030000d4)
#define reg_i2c_control    (*(volatile uint16_t*)0x030000d6)
#define reg_i2c_prescale   (*(volatile uint16_t*)0x030000d4)
// NOTE: "status" and "command" are the same byte (one read, one write)
#define reg_i2c_status     (*(volatile uint32_t*)0x030000d8)
#define reg_i2c_command    (*(volatile uint32_t*)0x030000d8)
#define reg_i2c_data       (*(volatile uint32_t*)0x030000dc)

#define reg_timer_config   (*(volatile uint32_t*)0x030000f4)
#define reg_timer_value    (*(volatile uint32_t*)0x030000f8)
#define reg_timer_data     (*(volatile uint32_t*)0x030000fc)

#define reg_spi_config     (*(volatile uint32_t*)0x030000b8)
#define reg_spi_data       (*(volatile uint32_t*)0x030000bc)

#define reg_gpio_data      (*(volatile uint32_t*)0x03000000)
#define reg_gpio_enb       (*(volatile uint32_t*)0x03000004)
#define reg_gpio_pub       (*(volatile uint32_t*)0x03000008)
#define reg_gpio_pdb       (*(volatile uint32_t*)0x0300000c)

#define reg_spi_commconfig (*(volatile uint32_t*)0x03000080)
#define reg_spi_enables    (*(volatile uint32_t*)0x03000084)
#define reg_spi_pll_config (*(volatile uint32_t*)0x03000088)
#define reg_spi_mfgr_id    (*(volatile uint32_t*)0x0300008c)
#define reg_spi_prod_id    (*(volatile uint32_t*)0x03000090)
#define reg_spi_mask_rev   (*(volatile uint32_t*)0x03000094)
#define reg_spi_pll_bypass (*(volatile uint32_t*)0x03000098)

#define reg_xtal_out_dest  (*(volatile uint32_t*)0x030000a0)
#define reg_pll_out_dest   (*(volatile uint32_t*)0x030000a4)
#define reg_trap_out_dest  (*(volatile uint32_t*)0x030000a8)

#define reg_irq7_source    (*(volatile uint32_t*)0x030000b0)
#define reg_irq8_source    (*(volatile uint32_t*)0x030000b4)
#endif
