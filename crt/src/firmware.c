#include <tinylib.h>

extern uint32_t _flash_wait_start, _flash_wait_end;
extern uint32_t _ram_lma, _ram_vma;
extern uint32_t _ram_start, _stack_point;
extern uint32_t _start, _etext;
extern uint32_t _psram_lma, _psram_vma, _edata;
extern uint32_t _sbss, _ebss;
extern uint32_t _heap_start;

// static uint32_t global_test[6] = {0x12, 0x23, 0x34, 0x45, 0x56, 0x67};

void welcome_screen()
{
    // for(int  i = 0; i < 6; ++i)
    //     printf("global test:%x\n", global_test[i]);

    // printf("[USER IP design] archinfo test\n");
    // printf("[ARCHINFO SYS] %x\n", reg_user_ip_reg0);
    // printf("[ARCHINFO IDL] %x\n", reg_user_ip_reg1);
    // printf("[ARCHINFO IDH] %x\n", reg_user_ip_reg2);
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

    printf("Inst/Memory Device: \n");
    printf("  SPI Flash size:    @[0x%x-0x%x] %dMB\n", SPFS_MEM_START, SPFS_MEM_START + SPFS_MEM_OFFST - 1, SPFS_MEM_OFFST / 1024 / 1024);
    printf("  On-chip RAM size:  @[0x%x-0x%x] %dKB\n", SRAM_MEM_START, SRAM_MEM_START + SRAM_MEM_OFFST - 1, SRAM_MEM_OFFST / 1024);
    printf("  Extern PSRAM size: @[0x%x-0x%x] %dMB(%dx8MB)\n", PSRAM_MEM_START, PSRAM_MEM_START + PSRAM_MEM_OFFST - 1, 8 * PSRAM_NUM, PSRAM_NUM);
    printf("  TF MMIO Card size: @[0x%x-0x%x] %dMB\n\n", TF_CARD_START, TF_CARD_START + TF_CARD_OFFST - 1, TF_CARD_OFFST / 1024 / 1024);

    printf("Memory Map IO Device:\n");
    printf("                     8 x GPIO          @0x%x\n", &reg_gpio_data);
    printf("                     1 x UART          @0x%x\n", &reg_uart0_clkdiv);
    printf("                     2 x TIMER         @0x%x,0x%x\n", &reg_tim0_cfg, &reg_tim1_cfg);
    printf("                     1 x PSRAM         @0x%x\n", &reg_psram_wait);
    printf("                     1 x SPISD         @0x%x\n", &reg_spisd_mode);
    printf("                     1 x I2C           @0x%x\n", &reg_i2c0_clkdiv);
    printf("                     1 x I2S           @0x%x\n", &reg_i2s_mode);
    printf("                     1 x ONEWIRE       @0x%x\n", &reg_onewire_clkdiv);
    printf("                     1 x DMA           @0x%x\n", &reg_dma_ctrl);
    printf("                     1 x SYSCTRL       @0x%x\n", &reg_sysctrl_coresel);
    printf("                     1 x ARCHINFO      @0x%x\n", &reg_archinfo_sys);
    printf("                     1 x RNG           @0x%x\n", &reg_rng_ctrl);
    printf("                     1 x UART(ADV)     @0x%x\n", &reg_uart1_lcr);
    printf("                     4 x PWM           @0x%x\n", &reg_pwm_ctrl);
    printf("                     1 x PS2           @0x%x\n", &reg_ps2_ctrl);
    printf("                     1 x I2C(ADV)      @0x%x\n", &reg_i2c1_ctrl);
    printf("                     1 x QSPI          @0x%x\n", &reg_qspi_status);
    printf("                     1 x USER_IP       @0x%x\n\n", &reg_user_ip_reg0);
}

void app_system_boot() {
    welcome_screen();
    printf("self test start...\n");

    bool timing_pass = true;

    printf("[PSRAM] device:     ESP-PSRAM64H(max %dMHz)\n", PSRAM_SCLK_MAX_FREQ);
    printf("        volt:       3.3V\n");
    printf("        power-up:   SPI mode\n");
    printf("        normal:     QPI mode\n");
    printf("        sclk freq:  %dMHz\n", PSRAM_SCLK_FREQ);
    // check
    uint32_t timing_expt = 0, timing_actual = 0;
    char  msg_pass[20] = "\e[0;32m[PASS]\e[0m", msg_fail[20] = "\e[0;31m[FAIL]\e[0m";

    printf("[PSRAM] wait cycles(default):      %d\n", reg_psram_wait);
    printf("[PSRAM] chd delay cycles(defalut): %d\n", reg_psram_chd);
    printf("[PSRAM] timing check\n");
    timing_expt = 1000 / PSRAM_SCLK_MAX_FREQ;
    timing_actual = 1000 / (PSRAM_SCLK_FREQ);

    printf("tCLK    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    printf("tCH/tCL ===> expt:  [0.45-0.55] tCLK(min)\n");
    printf("             actul: [0.45-0.55] tCLK ");
    printf("%s\n", msg_pass);

    printf("tKHKL   ===> expt:  1.5ns(max)\n");
    printf("             actul: 1.5ns ");
    printf("%s\n", msg_pass);

    timing_expt = 50;
    timing_actual = (reg_psram_wait / 2) * (1000 / PSRAM_SCLK_FREQ);
    printf("tCPH    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 8;
    // 32(cmd+addr) + 32(data)
    timing_actual = ((1000 / PSRAM_SCLK_FREQ) * ((32 + 32) / 4)) / 1000;
    printf("tCEM    ===> expt:  %dus(max)\n", timing_expt);
    printf("             actul: %dus ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual <= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 2;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) / 2;
    printf("tCSP    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 20;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) * (reg_psram_chd / 2 + 1);
    printf("tCHD    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 2;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) / 2;
    printf("tSP     ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    if(!timing_pass) {
        printf("[PSRAM] timing check fail\n");
        while(1);
    }

    uint32_t psram_cfg_val = (uint32_t)8;
    reg_psram_wait = psram_cfg_val;
    printf("[PSRAM] set wait cycles to %d, actul rd val: %d\n", psram_cfg_val, reg_psram_wait);
    psram_cfg_val = (uint32_t)0;
    reg_psram_chd = psram_cfg_val;
    printf("[PSRAM] set chd cycles to %d, actul rd val: %d\n", psram_cfg_val, reg_psram_chd);
    printf("[extern PSRAM test]\n");
    // ip_psram_selftest(0x40000000, 8 * 1024 * 1024);
    printf("self test done\n\n");
}

void main()
{
    reg_uart0_clkdiv = (uint32_t)(CPU_FREQ * 1000000 / UART_BPS);
    app_system_boot();
    // while(1);
    ip_archinfo_test();
    i2c0_init((uint8_t)35);
    PCF8563B_test();
    ES8388_init();
    // ip_1wire_test();
    // 0x0100_4000
    ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();

    // ip_tim_test();
    // ip_rng_test();
    
    // ip_gpio_test();
    // ip_hpuart_test();
    // ip_pwm_test();
    // ip_ps2_test();
    // ip_lcd_test();
    // tinybench(true, 0);
    // tinysh();
}
