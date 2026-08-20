#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <socver.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/lib/console.h>
#include <retrosoc/lib/string.h>
#include <retrosoc/service/shell.h>
#include <retrosoc/service/booter.h>
#include <user_design_info.h>

void rs_app_info(void) {
    uint8_t selected_core;
    uint8_t selected_ip;

    selected_core = 0U;
    selected_ip = 0U;
    (void)rs_sysctrl_get_core_select(&selected_core);
    (void)rs_sysctrl_get_ip_select(&selected_ip);
    printf("#############################################################\n");
    printf("#############################################################\n");
    printf("compile date: %s %s\n", __DATE__, __TIME__);
    printf("first bootloader done, app section info:\n");
    printf("_flash_wait_start: %p\n", (void *)&_flash_wait_start);
    printf("_flash_wait_end:   %p\n", (void *)&_flash_wait_end);
    printf("_ram_lma:          %p\n", (void *)&_ram_lma);
    printf("_ram_vma:          %p\n", (void *)&_ram_vma);
    printf("_ram_start:        %p\n", (void *)&_ram_start);
    printf("stack point:       %p\n", (void *)&_stack_point);
    printf("_stext(entry):     %p\n", (void *)&_start);
    printf("_etext:            %p\n", (void *)&_etext);
    printf("_psram_lma:        %p\n", (void *)&_psram_lma);
    printf("_psram_vma:        %p\n", (void *)&_psram_vma);
    printf("_edata:            %p\n", (void *)&_edata);
    printf("_sbss:             %p\n", (void *)&_sbss);
    printf("_ebss:             %p\n", (void *)&_ebss);
    printf("_heap_start:       %p\n\n", (void *)&_heap_start);
    printf("uart config: 8n1 %dbps\n", UART_BPS);
    printf("app booting...\n");
    printf("\n");
    printf("          _             _____        _____ \n");
    printf("         | |           / ____|      / ____|\n");
    printf(" _ __ ___| |_ _ __ ___| (___   ___ | |     \n");
    printf("| '__/ _ \\ __| '__/ _ \\\\___ \\ / _ \\| |\n");
    printf("| | |  __/ |_| | | (_) |___) | (_) | |____ \n");
    printf("|_|  \\___|\\__|_|  \\___/_____/ \\___/ \\_____|\n");
    printf("  retroSoC: A Customized ASIC for Retro Stuff\n");
    printf("    <https://github.com/retroSoC/retroSoC>\n");
    printf("  author:       Yuchi Miao   <https://github.com/maksyuki>\n");
    printf("  contributor:  MrAMS        <https://github.com/MrAMS>\n");
    printf("  license:      MulanPSL-2.0 license\n\n");
    printf("  series:       retroSoC Mini\n");
    printf("  specs:        Gen2 Plus\n");
    printf("  version:      %s(commit: %s)\n\n", RETROSOC_BRANCH, RETROSOC_COMMIT);

    printf("User Processors:\n");
    uint32_t core_size = sizeof(user_core_info) / sizeof(user_core_info[0]);
    printf("       %-15s %-12s %-12s %s\n", "[name]", "[isa]", "[maintainer]", "[repo]");
    for (uint32_t i = 0; i < core_size; ++i) {
        if (selected_core == i)
            printf("=>");
        else
            printf("  ");
        printf("[%d]: %-15s %-12s %-12s %s\n", i, user_core_info[i].name, user_core_info[i].isa,
               user_core_info[i].maintainer, user_core_info[i].repo);
    }

    printf("\nUser IPs:\n");
    uint32_t ip_size = sizeof(user_ip_info) / sizeof(user_ip_info[0]);
    printf("       %-15s %-12s %-12s %s\n", "[name]", "[isa]", "[maintainer]", "[repo]");
    for (uint32_t i = 0; i < ip_size; ++i) {
        if (selected_ip == i)
            printf("=>");
        else
            printf("  ");
        printf("[%d]: %-15s %-12s %-12s %s\n", i, user_ip_info[i].name, user_ip_info[i].isa,
               user_ip_info[i].maintainer, user_ip_info[i].repo);
    }

    printf("\nSoftware:\n");
    printf("  COMPILER:            %s\n", COMPILER_NAME);
    printf("  CFLAGS:              %s\n", COMPILER_CFLAGS);
    printf("  ISA:                 %s\n", COMPILER_ISA);
    printf("  FREQ:                %dMHz\n\n", CPU_FREQ);

    printf("Inst/Memory Address Range:\n");
    printf("  XPI NOR:             @[0x%08x-0x%08x] %3d MiB\n", SPFS_MEM_START,
           SPFS_MEM_START + SPFS_MEM_OFFST - 1, SPFS_MEM_OFFST / 1024 / 1024);
#if RS_SOC_HAS_SRAM
    printf("  On-chip RAM:         @[0x%08x-0x%08x] %3d KiB\n", SRAM_MEM_START,
           SRAM_MEM_START + SRAM_MEM_OFFST - 1, SRAM_MEM_OFFST / 1024);
#endif
    printf("  Off-chip SDRAM:      @[0x%08x-0x%08x] %3d MiB\n", SDRAM_MEM_START,
           SDRAM_MEM_START + SDRAM_MEM_OFFST - 1, SDRAM_MEM_OFFST / 1024 / 1024);
    printf("  Off-chip PSRAM:      @[0x%08x-0x%08x] %3d MiB\n", PSRAM_MEM_START,
           PSRAM_MEM_START + PSRAM_MEM_OFFST - 1, PSRAM_MEM_OFFST / 1024 / 1024);
    printf("  XPI MMIO:            @[0x%08x-0x%08x] %3d MiB\n", XPI_MEM_START,
           XPI_MEM_START + XPI_MEM_OFFST - 1, XPI_MEM_OFFST / 1024 / 1024);
    printf("  Reserved (old SPISD):@[0x%08x-0x%08x]\n\n", TF_CARD_START,
           TF_CARD_START + TF_CARD_OFFST - 1);

    printf("Memory Map IO Device:\n");
    printf("                       1 x GPIO(32PIN)   @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_GPIO_ADMIN_BASE);
    printf("                       1 x UART0         @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_UART0_BASE);
    printf("                       2 x TIMER(0,1)    @%p,%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_TIM0_BASE, (void *)(uintptr_t)RS_SOC_APB4_TIM1_BASE);
    printf("                       1 x PSRAM         @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_PSRAM_BASE);
    printf("                       1 x SPISD         @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_SPISD_BASE);
    printf("                       1 x I2C0          @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_I2C0_BASE);
    printf("                       1 x I2S           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_I2S_BASE);
    printf("                       1 x WS2812        @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_WS2812_BASE);
    printf("                       1 x XPI V2        @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_XPI_BASE);
    printf("                       1 x DMA(6CH)      @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_DMA_BASE);
    printf("                       1 x SYSCTRL       @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_SYSCTRL_BASE);
    printf("                       1 x CRYPTO        @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_CRYPTO_BASE);
    printf("                       1 x CLINT         @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_CLINT_BASE);
    printf("                       1 x SDRAM         @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_SDRAM_BASE);
    printf("                       1 x DVP           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_DVP_BASE);
    printf("                       1 x I2C1          @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_I2C1_BASE);
    printf("                       1 x ARCHINFO      @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_ARCHINFO_BASE);
    printf("                       1 x RNG           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_RNG_BASE);
    printf("                       1 x PWM V2(4CH)   @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_PWM_BASE);
    printf("                       1 x PS2           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_PS2_BASE);
    printf("                       1 x RTC           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_RTC_BASE);
    printf("                       1 x WDG V2        @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_WDG_BASE);
    printf("                       1 x CRC           @%p\n",
           (void *)(uintptr_t)RS_SOC_APB4_CRC_BASE);
    printf("                       1 x USER_IP(4KiB) @%p\n", (void *)&reg_user_ip_reg0);
    printf("\n");
    printf("#############################################################\n");
    printf("#############################################################\n");
}

static uint8_t rs_booter_shell(void) {
    printf("================================\n");
    printf("       retroSoC Booter Shell    \n");
    printf("================================\n");
    printf("0: flash(defalut) 1: uart 2: tf\n");

    char type_res[RS_SHELL_MAX_COMMAND_LENGTH + 1U];
    char type_ch;
    size_t type_len;

    for (;;) {
        printf("rs_shell > ");
        type_len = 0U;
        do {
            type_ch = getchar();
            if ((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') ||
                (type_ch >= '0' && type_ch <= '9') || type_ch == ' ' || type_ch == '.' ||
                type_ch == '/' || type_ch == '_' || type_ch == '"' || type_ch == '/' ||
                type_ch == '*' || type_ch == '-') {
                if ((type_len + 1U) >= sizeof(type_res)) {
                    continue;
                }
                putchar(type_ch);
                type_res[type_len++] = type_ch;
            } else if (type_ch == '\b' || type_ch == (char)127) {
                if (type_len == 0)
                    continue;
                printf("\b \b");
                type_res[type_len--] = 0;
            } else if (type_ch == (char)9) { // tab
                printf("tab\n");
            }

        } while (type_ch != '\n' && type_ch != '\r');
        putchar('\n');

        type_res[type_len] = 0;
        if (strcmp(type_res, "flash") == 0)
            return 0;
        else if (strcmp(type_res, "uart") == 0)
            return 1;
        else if (strcmp(type_res, "tf") == 0)
            return 2;
        else
            printf("cmd [%s] not found\n", type_res);
    }
}

static uint8_t rs_booter_check_key(void) {
    printf("booter and flash app load done\n");
    printf("whether enter [booter shell] or not...(press key0 to enter)\n\n");

    uint8_t enter_boot_delay = 6, enter_shell = 0;
    for (uint8_t i = 1; i <= enter_boot_delay; ++i) {
        printf("delay %ds...[all %ds]\n", i, enter_boot_delay);
        if (rs_timer_delay_ms(RS_TIMER_0, 1000U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            printf("booter timer delay failed\n");
            return 0U;
        }
        // if(i == 5) enter_shell = 1; // mock the oper
        if (enter_shell) {
            printf("\n");
            return enter_shell;
        }
    }
    printf("\n");
    return enter_shell;
}

void rs_booter(void) {
    uint8_t boot_mode = 0;

    if (rs_booter_check_key() != 0U) {
        boot_mode = rs_booter_shell();
    } else
        printf("no key0 pressed, default ");

    printf("boot mode is [%s]\n\n", boot_mode == 0   ? "FLASH"
                                    : boot_mode == 1 ? "UART"
                                    : boot_mode == 2 ? "TF"
                                                     : "NONE");

    printf("mem self test start...\n");
    ip_psram_boot();
    printf("mem self test done\n");
}
