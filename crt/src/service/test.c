#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/service/test.h>

void rs_test_finish(rs_test_result_t result, uint8_t code) {
    rs_sysctrl_write_test_status(result == RS_TEST_PASSED, code);
    for (;;) {
    }
}
