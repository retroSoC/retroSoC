#include <firmware.h>
#include <tinyprintf.h>
#include <userip.h>


void userip_main(int argc, char **argv) {
    // user custom area
    (void)argc;
    (void)argv;
    printf("[USER IP] archinfo test\n");
    printf("[ARCHINFO SYS] %x\n", reg_user_ip_reg0);
    printf("[ARCHINFO IDL] %x\n", reg_user_ip_reg1);
    printf("[ARCHINFO IDH] %x\n", reg_user_ip_reg2);
}