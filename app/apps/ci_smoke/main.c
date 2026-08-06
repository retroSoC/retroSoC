#include <retrosoc/core/soc.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

static bool rs_ci_smoke_archinfo_matches_reset_values(void) {
    const uint32_t archinfo_sys = reg_archinfo_sys;
    const uint32_t archinfo_idl = reg_archinfo_idl;
    const uint32_t archinfo_idh = reg_archinfo_idh;

    return (archinfo_sys == UINT32_C(0x000F1010)) && (archinfo_idl == UINT32_C(0xFFFF2022)) &&
           (archinfo_idh == UINT32_C(0x00FFFFFF));
}

int main(void) {
    uart0_init(CPU_FREQ, UART_BPS);

    if (!rs_ci_smoke_archinfo_matches_reset_values()) {
        rs_test_finish(RS_TEST_FAILED, 1U);
    }

    printf("ci_smoke: archinfo readback passed\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
