#include <firmware.h>
#include <tinyprintf.h>
#include <tinyrng.h>

void ip_rng_test()
{
    printf("[CUST IP] rng test\n");

    reg_cust_rng_ctrl = (uint32_t)1;      // en the core
    reg_cust_rng_seed = (uint32_t)0xFE1C; // set the init seed
    printf("[RNG SEED] %x\n", reg_cust_rng_seed);

    for (int i = 0; i < 5; ++i)
    {
        printf("[RNG VAL] %x\n", reg_cust_rng_val);
    }

    printf("[RNG] reset the seed\n");
    reg_cust_rng_seed = (uint32_t)0;
    for (int i = 0; i < 5; ++i)
    {
        printf("[RNG VAL] %x\n", reg_cust_rng_val);
    }
}