#include <firmware.h>
#include <tinyprintf.h>
#include <tinyps2.h>

void ip_ps2_test()
{
    printf("[CUST IP] ps2 test\n");

    reg_cust_ps2_ctrl = (uint32_t)0b11;
    uint32_t kdb_code, i = 0;
    for (int i = 0; i < 36;)
    {
        kdb_code = reg_cust_ps2_data;
        if (kdb_code != 0)
        {
            ++i;
            printf("[PS2 DAT] %x\n", kdb_code);
        }
    }
}