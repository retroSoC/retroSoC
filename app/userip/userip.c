#include <firmware.h>
#include <tinyprintf.h>
#include <userip.h>


void userip_main(int argc, char **argv) {
    // user custom area HACK:
    (void)argv;
    if(argc == 0) {
        printf("[FIXED IP] archinfo test\n");
        printf("[ARCHINFO SYS] %x\n", reg_user_ip_reg0);
        printf("[ARCHINFO IDL] %x\n", reg_user_ip_reg1);
        printf("[ARCHINFO IDH] %x\n", reg_user_ip_reg2);
    } else if(argc == 1) {
        reg_user_ip_reg1 = 2;
        printf("div val: %x\n", reg_user_ip_reg1);
        reg_user_ip_reg2 = 0;
        for(int i = 0; i < 6; ++i) printf("tim val: %d\n", reg_user_ip_reg2);
    } else if(argc == 2) {
        printf("[reg0] %x\n", reg_user_ip_reg0);
    }

}