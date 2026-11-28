#include <retrosoc/core/soc.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

#include "piolite_p4_scenarios.h"

int main(void) {
    uint8_t code = rs_piolite_p4_run_selected();
    if ((rs_uart_init(RS_PCLK_CLOCK_HZ, UINT32_C(1000000)) != RS_OK) || rs_p4_report_overflow()) {
        code = UINT8_C(255);
    }
    rs_p4_report_printf("PIOLITE_P4_RESULT scenario=%s code=%u\n", rs_piolite_p4_scenario_name(),
                        (unsigned int)code);
    rs_sysctrl_write_test_status(code == 0U, code);
    rs_p4_report_flush();
    for (;;) {
    }
}
