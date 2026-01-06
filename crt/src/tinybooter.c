#include <firmware.h>
#include <tinyprintf.h>
#include <socver.h>
#include <tinypsram.h>
#include <tinytim.h>
#include <tinyprint.h>
#include <tinystring.h>
#include <tinysh.h>
#include <tinybooter.h>
// HACK:
#if defined(CORE_MDD) || defined(IP_MDD)
#include <../../rtl/mini/mpw/.build/user_design_info.h>
#endif


void app_info() {
    printf("#############################################################\n");
    printf("#############################################################\n");
    printf("compile date: %s %s\n", __DATE__, __TIME__);
    printf("first bootloader done, app section info:\n");
    printf("_flash_wait_start: 0x%x\n", &_flash_wait_start);
    printf("_flash_wait_end:   0x%x\n", &_flash_wait_end);
    printf("_ram_lma:          0x%x\n", &_ram_lma);
    printf("_ram_vma:          0x%x\n", &_ram_vma);
    printf("_ram_start:        0x%x\n", &_ram_start);
    printf("stack point:       0x%x\n", &_stack_point);
    printf("_stext(entry):     0x%x\n", &_start);
    printf("_etext:            0x%x\n", &_etext);
    printf("_psram_lma:        0x%x\n", &_psram_lma);
    printf("_psram_vma:        0x%x\n", &_psram_vma);
    printf("_edata:            0x%x\n", &_edata);
    printf("_sbss:             0x%x\n", &_sbss);
    printf("_ebss:             0x%x\n", &_ebss);
    printf("_heap_start:       0x%x\n\n", &_heap_start);
    printf("uart config: 8n1 %dbps\n", UART_BPS);
    printf("app booting...\n");
    printf("\n");
    printf("          _             _____        _____ \n");
    printf("         | |           / ____|      / ____|\n");
    printf(" _ __ ___| |_ _ __ ___| (___   ___ | |     \n");
    printf("| '__/ _ \\ __| '__/ _ \\\\___ \\ / _ \\| |\n");
    printf("| | |  __/ |_| | | (_) |___) | (_) | |____ \n");
    printf("|_|  \\___|\\__|_|  \\___/_____/ \\___/ \\_____|\n");
    printf("  retroSoC: A Customized ASIC for Retro Stuff!\n");
    printf("    <https://github.com/retroSoC/retroSoC>\n");
    printf("  author:       Yuchi Miao   <https://github.com/maksyuki>\n");
    printf("  contributor:  MrAMS        <https://github.com/MrAMS>\n");
    printf("  license:      MulanPSL-2.0 license\n\n");
    printf("  series:       retroSoC Mini\n");
    printf("  specs:        Gen2\n");
    printf("  version:      %s(commit: %s)\n\n", RETROSOC_BRANCH, RETROSOC_COMMIT);

    printf("User Processors:\n");
#ifndef CORE_MDD
    printf("  CORE:                %s\n", HW_CORE);
#else
    uint32_t core_size = sizeof(user_core_info)/sizeof(user_core_info[0]);
    printf("       %-15s %-12s %-12s %s\n", "[name]", "[isa]", "[maintainer]", "[repo]");
    for(uint32_t i = 0; i < core_size; ++i) {
        if(reg_sysctrl_coresel == i) printf("=>");
        else printf("  ");
        printf("[%d]: %-15s %-12s %-12s %s\n", i, user_core_info[i].name, user_core_info[i].isa, user_core_info[i].maintainer, user_core_info[i].repo);
    }
#endif
    printf("\nUser IPs:\n");
    uint32_t ip_size = sizeof(user_ip_info)/sizeof(user_ip_info[0]);
    printf("       %-15s %-12s %-12s %s\n", "[name]", "[isa]", "[maintainer]", "[repo]");
    for(uint32_t i = 0; i < ip_size; ++i) {
        if(reg_sysctrl_ipsel == i) printf("=>");
        else printf("  ");
        printf("[%d]: %-15s %-12s %-12s %s\n", i, user_ip_info[i].name, user_ip_info[i].isa, user_ip_info[i].maintainer, user_ip_info[i].repo);
    }


    printf("\nSoftware:\n");
    printf("  COMPILER:            %s\n", COMPILER_NAME);
    printf("  CFLAGS:              %s\n", COMPILER_CFLAGS);
    printf("  ISA:                 %s\n", COMPILER_ISA);
    printf("  FREQ:                %dMHz\n\n", CPU_FREQ);

    printf("Inst/Memory Address Range:\n");
    printf("  SPI Flash:           @[0x%08x-0x%08x] %dMiB\n", SPFS_MEM_START, SPFS_MEM_START + SPFS_MEM_OFFST - 1, SPFS_MEM_OFFST / 1024 / 1024);
    printf("  NMI IP MMIO:         @[0x%08x-0x%08x] %dMiB\n", NMI_MEM_START, NMI_MEM_START + NMI_MEM_OFFST - 1, NMI_MEM_OFFST / 1024 / 1024);
    printf("  APB IP MMIO:         @[0x%08x-0x%08x] %dMiB\n", APB_MEM_START, APB_MEM_START + APB_MEM_OFFST - 1, APB_MEM_OFFST / 1024 / 1024);
    printf("  On-chip RAM:         @[0x%08x-0x%08x] %dKiB\n", SRAM_MEM_START, SRAM_MEM_START + SRAM_MEM_OFFST - 1, SRAM_MEM_OFFST / 1024);
    printf("  Extern PSRAM:        @[0x%08x-0x%08x] %dMiB(%dx8MiB)\n", PSRAM_MEM_START, PSRAM_MEM_START + PSRAM_MEM_OFFST - 1, 8 * PSRAM_NUM, PSRAM_NUM);
    printf("  QSPI0 MMIO:          @[0x%08x-0x%08x] %dMiB\n", QSPI_MEM_START, QSPI_MEM_START + QSPI_MEM_OFFST - 1, QSPI_MEM_OFFST / 1024 / 1024);
    printf("  TF Card MMIO:        @[0x%08x-0x%08x] %dGiB\n\n", TF_CARD_START, TF_CARD_START + TF_CARD_OFFST - 1, TF_CARD_OFFST / 1024 / 1024 / 1024);

    printf("Memory Map IO Device:\n");
    printf("                       8 x GPIO          @0x%x\n", &reg_gpio_data);
    printf("                       1 x UART0         @0x%x\n", &reg_uart0_clkdiv);
    printf("                       2 x TIMER(0,1)    @0x%x,0x%x\n", &reg_tim0_cfg, &reg_tim1_cfg);
    printf("                       1 x PSRAM         @0x%x\n", &reg_psram_wait);
    printf("                       1 x SPISD         @0x%x\n", &reg_spisd_mode);
    printf("                       1 x I2C0          @0x%x\n", &reg_i2c0_clkdiv);
    printf("                       1 x I2S           @0x%x\n", &reg_i2s_mode);
    printf("                       1 x ONEWIRE       @0x%x\n", &reg_onewire_clkdiv);
    printf("                       1 x QSPI0         @0x%x\n", &reg_qspi0_mode);
    printf("                       1 x DMA           @0x%x\n", &reg_dma_mode);
    printf("                       1 x SYSCTRL       @0x%x\n", &reg_sysctrl_coresel);
    printf("                       1 x CLINT         @0x%x\n", &reg_clint_clkdiv);
    printf("                       1 x ARCHINFO      @0x%x\n", &reg_archinfo_sys);
    printf("                       1 x RNG           @0x%x\n", &reg_rng_ctrl);
    printf("                       1 x UART1(ADV)    @0x%x\n", &reg_uart1_lcr);
    printf("                       4 x PWM           @0x%x\n", &reg_pwm_ctrl);
    printf("                       1 x PS2           @0x%x\n", &reg_ps2_ctrl);
    printf("                       1 x I2C1(ADV)     @0x%x\n", &reg_i2c1_ctrl);
    printf("                       1 x QSPI1         @0x%x\n", &reg_qspi1_status);
    printf("                       1 x RTC           @0x%x\n", &reg_rtc_ctrl);
    printf("                       1 x WDG           @0x%x\n", &reg_wdg_ctrl);
    printf("                       1 x CRC           @0x%x\n", &reg_crc_ctrl);
    printf("                       1 x TIMER3(ADV)   @0x%x\n", &reg_tim3_ctrl);
    printf("                       1 x USER_IP(4KiB) @0x%x\n\n", &reg_user_ip_reg0);
    printf("#############################################################\n");
    printf("#############################################################\n");
}

uint8_t boot_shell() {
    printf("================================\n");
    printf("      Tiny Booter Shell         \n");
    printf("================================\n");
    printf("0: flash(defalut) 1: uart 2: tf\n");

    char type_res[MAX_CMD_LEN], type_ch;
    uint8_t type_len;

    while(1) {
        printf("tinysh > ");
        type_len = 0;
         do {
            type_ch = getchar();
            if((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') ||
               (type_ch >= '0' && type_ch <= '9') || type_ch == ' ' || type_ch == '.' ||
                type_ch == '/' || type_ch == '_' || type_ch == '"' || type_ch == '/' ||
                type_ch == '*' || type_ch == '-') {
                if(type_len == MAX_CMD_LEN) break;
                putchar(type_ch);
                type_res[type_len++] = type_ch;
            } else if(type_ch == '\b' || type_ch == (char) 127){
                if(type_len == 0) continue;
                printf("\b \b");
                type_res[type_len--] = 0;
            } else if(type_ch == (char) 9) { // tab
                printf("tab\n");
            }

        } while(type_ch != '\n' && type_ch != '\r');
        putchar('\n');

        type_res[type_len] = 0;
        if(strcmp(type_res, "flash") == 0) return 0;
        else if(strcmp(type_res, "uart") == 0) return 1;
        else if(strcmp(type_res, "tf") == 0) return 2;
        else printf("cmd [%s] not found\n", type_res);
    }

}

uint8_t check_key() {
    printf("booter and flash app load done\n");
    printf("whether enter [booter shell] or not...(press key0 to enter)\n\n");

    uint8_t enter_boot_delay = 6, enter_shell = 0;
    for(uint8_t i = 1; i <= enter_boot_delay; ++i) {
        printf("delay %ds...[all %ds]\n", i, enter_boot_delay);
        delay_ms(1000);
        // if(i == 5) enter_shell = 1; // mock the oper
        if(enter_shell) {
            printf("\n");
            return enter_shell;
        }
    }
    printf("\n");
    return enter_shell;
}

void tinybooter() {
    uint8_t boot_mode = 0;

    if(check_key()) boot_mode = boot_shell();
    else printf("no key0 pressed, default ");

    printf("boot mode is [%s]\n\n", boot_mode == 0 ? "FLASH" :
                                    boot_mode == 1 ? "UART" :
                                    boot_mode == 2 ? "TF" : "NONE");

    printf("mem self test start...\n");
    ip_psram_boot();
    printf("mem self test done\n");
}