#include <firmware.h>
#include <tinyprintf.h>
#include <tinyrng.h>

void ip_rng_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("[APB IP] rng test\n");

    reg_rng_ctrl = (uint32_t)1;      // en the core
    reg_rng_seed = (uint32_t)0xFE1C; // set the init seed
    printf("[rng seed] %x\n", reg_rng_seed);

    for (int i = 0; i < 5; ++i) {
        printf("[rng val] %x\n", reg_rng_val);
    }

    printf("reset the seed\n");
    reg_rng_seed = (uint32_t)0;
    printf("[rng seed] %x\n", reg_rng_seed);
    for (int i = 0; i < 5; ++i) {
        printf("[rng val] %x\n", reg_rng_val);
    }
}