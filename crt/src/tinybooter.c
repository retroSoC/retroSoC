#include <firmware.h>
#include <tinyprintf.h>
#include <tinyver.h>
#include <tinypsram.h>
#include <tinybooter.h>


void app_boot_info() {
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
    printf("  version: v%s(commit: %s)\n", TINYLIB_VERSION, TINYLIB_COMMIT);
    printf("  license: MulanPSL-2.0 license\n\n");

    printf("Processor:\n");
    printf("  CORE:              %s\n", HW_CORE);
    printf("  ISA:               %s\n", SW_ISA);
    printf("  FREQ:              %dMHz\n\n", CPU_FREQ);

    printf("Inst/Memory Address Range:\n");
    printf("  SPI Flash:    @[0x%x-0x%x] %dMiB\n", SPFS_MEM_START, SPFS_MEM_START + SPFS_MEM_OFFST - 1, SPFS_MEM_OFFST / 1024 / 1024);
    printf("  NMI IP MMIO:  @[0x%x-0x%x] %dMiB\n", NMI_MEM_START, NMI_MEM_START + NMI_MEM_OFFST - 1, NMI_MEM_OFFST / 1024 / 1024);
    printf("  APB IP MMIO:  @[0x%x-0x%x] %dMiB\n", APB_MEM_START, APB_MEM_START + APB_MEM_OFFST - 1, APB_MEM_OFFST / 1024 / 1024);
    printf("  On-chip RAM:  @[0x%x-0x%x] %dKiB\n", SRAM_MEM_START, SRAM_MEM_START + SRAM_MEM_OFFST - 1, SRAM_MEM_OFFST / 1024);
    printf("  Extern PSRAM: @[0x%x-0x%x] %dMiB(%dx8MiB)\n", PSRAM_MEM_START, PSRAM_MEM_START + PSRAM_MEM_OFFST - 1, 8 * PSRAM_NUM, PSRAM_NUM);
    printf("  QSPI0 MMIO:   @[0x%x-0x%x] %dMiB\n", QSPI_MEM_START, QSPI_MEM_START + QSPI_MEM_OFFST - 1, QSPI_MEM_OFFST / 1024 / 1024);
    printf("  TF Card MMIO: @[0x%x-0x%x] %dGiB\n\n", TF_CARD_START, TF_CARD_START + TF_CARD_OFFST - 1, TF_CARD_OFFST / 1024 / 1024 / 1024);

    printf("Memory Map IO Device:\n");
    printf("                     8 x GPIO          @0x%x\n", &reg_gpio_data);
    printf("                     1 x UART0         @0x%x\n", &reg_uart0_clkdiv);
    printf("                     2 x TIMER(0,1)    @0x%x,0x%x\n", &reg_tim0_cfg, &reg_tim1_cfg);
    printf("                     1 x PSRAM         @0x%x\n", &reg_psram_wait);
    printf("                     1 x SPISD         @0x%x\n", &reg_spisd_mode);
    printf("                     1 x I2C0          @0x%x\n", &reg_i2c0_clkdiv);
    printf("                     1 x I2S           @0x%x\n", &reg_i2s_mode);
    printf("                     1 x ONEWIRE       @0x%x\n", &reg_onewire_clkdiv);
    printf("                     1 x QSPI0         @0x%x\n", &reg_qspi0_mode);
    printf("                     1 x DMA           @0x%x\n", &reg_dma_mode);
    printf("                     1 x SYSCTRL       @0x%x\n", &reg_sysctrl_coresel);
    printf("                     1 x ARCHINFO      @0x%x\n", &reg_archinfo_sys);
    printf("                     1 x RNG           @0x%x\n", &reg_rng_ctrl);
    printf("                     1 x UART1(ADV)    @0x%x\n", &reg_uart1_lcr);
    printf("                     4 x PWM           @0x%x\n", &reg_pwm_ctrl);
    printf("                     1 x PS2           @0x%x\n", &reg_ps2_ctrl);
    printf("                     1 x I2C1(ADV)     @0x%x\n", &reg_i2c1_ctrl);
    printf("                     1 x QSPI1         @0x%x\n", &reg_qspi1_status);
    printf("                     1 x RTC           @0x%x\n", &reg_rtc_ctrl);
    printf("                     1 x WDG           @0x%x\n", &reg_wdg_ctrl);
    printf("                     1 x CRC           @0x%x\n", &reg_crc_ctrl);
    printf("                     1 x TIMER3(ADV)   @0x%x\n", &reg_tim3_ctrl);
    printf("                     1 x USER_IP(4KiB) @0x%x\n\n", &reg_user_ip_reg0);
    printf("#############################################################\n");
    printf("#############################################################\n");
}

void boot_mode_select() {
    // delay some seconds
    // detect gpio1 gpio0 io voltage level
    // 0: flash 1: uart 2: TF 3: RESV
}
void app_system_boot() {
    app_boot_info();

    printf("mem self test start...\n");
    ip_psram_boot();
    printf("mem self test done\n");
    // printf("boot mode select...\n");
    
    boot_mode_select();

    printf("boot mode select [FLASH]\n");

}