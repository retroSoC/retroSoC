#include <firmware.h>
#include <tinyuart.h>

void putch(char ch)
{
  reg_uart_data = ch;
}
