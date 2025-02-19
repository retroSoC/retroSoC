#include <firmware.h>
#include <tinyprintf.h>
#include <tinyhkspi.h>

void ip_hk_spi_test()
{
    printf("[IP] housekeeping spi test\n");
    printf("[HK CONFIG]   %x\n", reg_spi_commconfig);
    printf("[HK ENB]      %x\n", reg_spi_enables);
    printf("[HK PLL]      %x\n", reg_spi_pll_config);
    printf("[HK MFGR ID]  %x\n", reg_spi_mfgr_id);
    printf("[HK PROD ID]  %x\n", reg_spi_prod_id);
    printf("[HK MASK REV] %x\n", reg_spi_mask_rev);
    printf("[HK PLL BYP]  %x\n", reg_spi_pll_bypass);
}
