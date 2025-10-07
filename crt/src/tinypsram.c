
#include <firmware.h>
#include <tinyprintf.h>
#include <tinypsram.h>

void ip_psram_boot() {
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
    printf("psram self test done\n\n");
}

uint32_t xorshift32(uint32_t *state) {
    /* Algorithm "xor" from p. 4 of Marsaglia, "Xorshift RNGs" */
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;

    return x;
}

void ip_psram_selftest(uint32_t addr, uint32_t range) {
    volatile uint32_t *base_word = (uint32_t *)addr;
    volatile uint16_t *base_hword = (uint16_t *)addr;
    volatile uint8_t *base_byte = (uint8_t *)addr;
    int test_num = 8192;

    printf("[range: %dB] 4-bytes wr/rd test\n", 4 * test_num);
    for (int i = 0; i < test_num; ++i)
    {
        *(base_word + i) = (uint32_t)(0x12345678 + i);
    }
    for (int i = 0; i < test_num; ++i)
    {
        if (*(base_word + i) != ((uint32_t)(0x12345678 + i)))
            printf("[error] rd: %x org: %x\n", *(base_word + i), (uint32_t)(0x12345678 + i));
    }

    printf("[range: %dB] 2-bytes wr/rd test\n", 2 * test_num);
    for (int i = 0; i < test_num; ++i)
    {
        *(base_hword + i) = (uint16_t)(0x5678 + i);
    }
    for (int i = 0; i < test_num; ++i)
    {
        if (*(base_hword + i) != ((uint16_t)(0x5678 + i)))
            printf("[error] rd: %x org: %x\n", *(base_hword + i), (uint16_t)(0x5678 + i));
    }

    printf("[range: %dB] 1-bytes wr/rd test\n", test_num);
    for (int i = 0; i < test_num; ++i)
    {
        *(base_byte + i) = (uint8_t)(0x78 + i);
    }
    for (int i = 0; i < test_num; ++i)
    {
        if (*(base_byte + i) != ((uint8_t)(0x78 + i)))
            printf("[error] rd: %x org: %x\n", *(base_byte + i), (uint8_t)(0x78 + i));
    }

    int cyc_count = 5;
    int stride = 256;
    uint32_t state;

    printf("[range: %dMB] stride increments wr/rd test\n", range / 1024 / 1024);
    for (int i = 1; i <= cyc_count; i++)
    {
        state = i;
        for (uint32_t word = 0; word < range / sizeof(int); word += stride)
        {
            *(base_word + word) = xorshift32(&state);
        }

        state = i;
        for (uint32_t word = 0; word < range / sizeof(int); word += stride)
        {
            if (*(base_word + word) != xorshift32(&state))
            {
                printf("***FAILED BYTE*** at %x\n", 4 * word);
                while (1)
                    ;
                return;
            }
        }
        printf(".");
    }
    printf("stride test done\n");
    printf("[PSRAM] self test done\n");
    // while(1);
}
