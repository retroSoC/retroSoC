#include <firmware.h>
#include <tinyuart.h>

void uart0_init(uint32_t freq, uint32_t bps) {
  reg_uart0_clkdiv = (uint32_t)(freq * 1000000 / bps);
}

void putch(char ch)
{
  // while (((reg_uart1_lsr & 0x100) >> 8) == 1)
  //   ;
  // reg_uart1_trx = (uint32_t)ch;

  reg_uart0_data = ch;
}
