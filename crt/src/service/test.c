#include <retrosoc/core/soc.h>
#include <retrosoc/service/test.h>

void rs_test_finish(rs_test_result_t result, uint8_t code) {
    uint32_t status = RS_SOC_TEST_STATUS_VALID | ((uint32_t)code << RS_SOC_TEST_STATUS_CODE_SHIFT);

    if (result == RS_TEST_PASSED) {
        status |= RS_SOC_TEST_STATUS_PASS;
    }
    reg_sysctrl_test_status = status;
    for (;;) {
    }
}
