
#include <firmware.h>
#include <tinyprintf.h>
#include <tinypsram.h>

uint32_t xorshift32(uint32_t *state)
{
    /* Algorithm "xor" from p. 4 of Marsaglia, "Xorshift RNGs" */
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;

    return x;
}

void ip_psram_selftest(uint32_t addr, uint32_t range)
{
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
        for (int word = 0; word < range / sizeof(int); word += stride)
        {
            *(base_word + word) = xorshift32(&state);
        }

        state = i;
        for (int word = 0; word < range / sizeof(int); word += stride)
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
