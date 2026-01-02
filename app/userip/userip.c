#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
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
        reg_user_ip_reg1 = (uint32_t)0xfffe;
        printf("do val: %x\n", reg_user_ip_reg5);
        for(int i = 0; i < 3; ++i) {
            delay_ms(1);
            reg_user_ip_reg5 = ~reg_user_ip_reg5;
            printf("[%d]do val: %x\n", i, reg_user_ip_reg5);
        }

        printf("cs val: %x\n", reg_user_ip_reg2);
        reg_user_ip_reg2 = (uint32_t)0xffff;
        printf("cs val: %x\n", reg_user_ip_reg2);

        printf("pu val: %x\n", reg_user_ip_reg3);
        reg_user_ip_reg3 = (uint32_t)0xffff;
        printf("pu val: %x\n", reg_user_ip_reg3);

        printf("pd val: %x\n", reg_user_ip_reg4);
        reg_user_ip_reg4 = (uint32_t)0xffff;
        printf("pd val: %x\n", reg_user_ip_reg4);

        reg_user_ip_reg1 = (uint32_t)0xfffe;
        for(int i = 0; i < 6; ++i) {
            printf("[%d]di val: %x\n", i, reg_user_ip_reg6);
        }
    }
}