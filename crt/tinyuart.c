#include <firmware.h>
#include <tinyuart.h>

void putch(char ch)
{
  // while (((reg_cust_uart_lsr & 0x100) >> 8) == 1)
  //   ;
  // reg_cust_uart_trx = (uint32_t)ch;

  reg_uart_data = ch;
}
