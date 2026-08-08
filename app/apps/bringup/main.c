#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/service/booter.h>
#include <retrosoc/service/test.h>

int main(void) {
    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        return 1;
    }
    rs_app_info();
    ip_archinfo_test(0, 0);
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
