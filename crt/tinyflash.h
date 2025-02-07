#ifndef TINYFLASH_H__
#define TINYFLASH_H__

#include <stdint.h>

// a pointer to this is a null pointer, but the compiler does not
// know that because "sram" is a linker symbol from sections.lds.
extern uint32_t sram;
extern uint32_t flashio_worker_begin;
extern uint32_t flashio_worker_end;

void flashio(uint8_t *data, int len, uint8_t wrencmd);
void set_flash_qspi_flag();
void set_flash_mode_spi();
void set_flash_mode_dual();
void set_flash_mode_quad();
void set_flash_mode_qddr();
void enable_flash_crm();
void cmd_read_flash_id();
uint8_t cmd_read_flash_reg(uint8_t cmd);
void cmd_print_spi_state();
void cmd_read_flash_regs();

#endif