#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/bench.h>

uint32_t rs_bench(bool verbose, uint32_t *instns_p) {
    printf("benckmark test\n");
    uint32_t words[64] = {0U};
    uint8_t *data = (uint8_t *)words;

    uint32_t x32 = 314159265;

    uint32_t cycles_begin, cycles_end;
    uint32_t instns_begin, instns_end;
    __asm__ volatile("rdcycle %0" : "=r"(cycles_begin));
    __asm__ volatile("rdinstret %0" : "=r"(instns_begin));

    printf("cycle and instns read done!\n");

    for (int i = 0; i < 20; i++) {
        for (int k = 0; k < 256; k++) {
            x32 ^= x32 << 13;
            x32 ^= x32 >> 17;
            x32 ^= x32 << 5;
            data[k] = x32;
        }

        for (int k = 0, p = 0; k < 256; k++) {
            if (data[k])
                data[p++] = k;
        }

        for (int k = 0; k < 64; k++) {
            x32 = x32 ^ words[k];
        }
    }

    __asm__ volatile("rdcycle %0" : "=r"(cycles_end));
    __asm__ volatile("rdinstret %0" : "=r"(instns_end));

    if (verbose) {
        printf("Cycles: 0x%x\n", cycles_end - cycles_begin);
        printf("Instns: 0x%x\n", instns_end - instns_begin);
        printf("Chksum: 0x%x\n", x32);
    }

    if (instns_p != NULL)
        *instns_p = instns_end - instns_begin;

    printf("benckmark done\n");
    return cycles_end - cycles_begin;
}
