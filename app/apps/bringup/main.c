#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/service/booter.h>

int main(void) {
    uart0_init(CPU_FREQ, UART_BPS);
    rs_app_info();
    ip_archinfo_test(0, 0);
    return 0;
}
