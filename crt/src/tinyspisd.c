#include <firmware.h>
#include <tinylib.h>
#include <tinyprintf.h>
#include <tinyspisd.h>


void ip_spisd_test()
{
    printf("spisd test\n");
    printf("[SPISD] clk div(default): %d\n", reg_spisd_ctrl);
    ip_psram_selftest(0x50000000, 1 * 1024 * 1024);
}