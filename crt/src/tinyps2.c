#include <firmware.h>
#include <tinyprintf.h>
#include <tinyps2.h>

void ip_ps2_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("[APB IP] ps2 test\n");

    reg_ps2_ctrl = (uint32_t)0b11;
    printf("ps2 ctrl: %x\n", reg_ps2_ctrl);
    uint32_t kdb_code;
    while(1)
    {
        kdb_code = reg_ps2_data;
        if (kdb_code != 0)
        {
            if(kdb_code == 0x76) break;
            printf("[PS2 DAT] %x\n", kdb_code);
        }
    }

    reg_ps2_ctrl = (uint32_t)0b00;
    printf("ps2 ctrl: %x\n", reg_ps2_ctrl);
}