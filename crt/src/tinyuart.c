#include <firmware.h>
#include <tinyuart.h>

void putch(char ch)
{
  // while (((reg_uart1_lsr & 0x100) >> 8) == 1)
  //   ;
  // reg_uart1_trx = (uint32_t)ch;

  reg_uart0_data = ch;
}
