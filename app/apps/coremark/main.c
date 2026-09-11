#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

#include "coremark.h"

#if defined(COREMARK_QUICK_MODE)
#define RS_COREMARK_MODE      "quick"
#define RS_COREMARK_QUALIFIED 0U
#else
#define RS_COREMARK_MODE      "standard"
#define RS_COREMARK_QUALIFIED 1U
#endif

int main(void) {
    int result;
    uint32_t cycles;

    if (rs_uart_init(RS_CPU_CLOCK_HZ, UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 2U);
    }
    result = core_main();
    cycles = (uint32_t)get_time();
    printf("COREMARK_RESULT mode=%s qualified=%u memory=sram iterations=%u cycles=%u cpu_hz=%u\n",
           RS_COREMARK_MODE, RS_COREMARK_QUALIFIED, (uint32_t)ITERATIONS, cycles, RS_CPU_CLOCK_HZ);
    if ((result != 0) || (cycles == 0U)) {
        printf("COREMARK_FAIL result=%d\n", result);
        rs_test_finish(RS_TEST_FAILED, 1U);
    }
    printf("COREMARK_PASS\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
