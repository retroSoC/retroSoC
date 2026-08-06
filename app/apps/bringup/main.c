#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/service/booter.h>
#include <retrosoc/service/test.h>

int main(void) {
    uart0_init(CPU_FREQ, UART_BPS);
    rs_app_info();
    ip_archinfo_test(0, 0);
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
