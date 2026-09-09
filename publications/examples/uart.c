#include <retrosoc/hal/uart.h>

rs_status_t example_uart(uint32_t source_clock_hz, uint32_t baud_rate)
{
    return rs_uart_init(source_clock_hz, baud_rate);
}
