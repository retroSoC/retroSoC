#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/crc.h>

void ip_crc_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("[APB IP] crc test\n");

    reg_crc_ctrl = (uint32_t)0;
    reg_crc_init = (uint32_t)0xFFFF;
    reg_crc_xorv = (uint32_t)0;
    reg_crc_ctrl = (uint32_t)0b1001001;

    uint32_t val = 0x123456;
    for (uint32_t i = 0U; i < 16U; ++i) {
        reg_crc_data = val + i;
        if (rs_wait_not_value(&reg_crc_stat, 0U, RS_TIMEOUT_DEFAULT) != RS_OK) {
            printf("crc calculation timed out\n");
            return;
        }
        printf("cnt: %d crc: %x\n", i, reg_crc_data);
    }
}
