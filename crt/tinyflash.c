#include <firmware.h>
#include <tinyflash.h>
#include <tinyprintf.h>

void flashio(uint8_t *data, int len, uint8_t wrencmd)
{
    uint32_t func[&flashio_worker_end - &flashio_worker_begin];

    uint32_t *src_ptr = &flashio_worker_begin;
    uint32_t *dst_ptr = func;

    while (src_ptr != &flashio_worker_end)
        *(dst_ptr++) = *(src_ptr++);

    ((void (*)(uint8_t *, uint32_t, uint32_t))func)(data, len, wrencmd);
}

void set_flash_qspi_flag()
{
    uint8_t buffer[8];

    // Read Configuration Registers (RDCR1 35h)
    buffer[0] = 0x35;
    buffer[1] = 0x00; // rdata
    flashio(buffer, 2, 0);
    uint8_t sr2 = buffer[1];

    // Write Enable Volatile (50h) + Write Status Register 2 (31h)
    buffer[0] = 0x31;
    buffer[1] = sr2 | 2; // Enable QSPI
    flashio(buffer, 2, 0x50);
}

void set_flash_mode_spi()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00000000;
}

void set_flash_mode_dual()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00400000;
}

void set_flash_mode_quad()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00240000;
}

void set_flash_mode_qddr()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00670000;
}

void enable_flash_crm()
{
    reg_spictrl |= 0x00100000;
}

void cmd_read_flash_id()
{
    uint8_t buffer[17] = {0x9F, /* zeros */};
    flashio(buffer, 17, 0);

    for (int i = 1; i <= 16; i++)
    {
        printf(" %x", buffer[i]);
    }
    printf("\n");
}

uint8_t cmd_read_flash_reg(uint8_t cmd)
{
    uint8_t buffer[2] = {cmd, 0};
    flashio(buffer, 2, 0);
    return buffer[1];
}

void cmd_print_spi_state()
{
    printf("SPI State:  LATENCY %d\n", (reg_spictrl >> 16) & 15);
    printf("  DDR ");
    if ((reg_spictrl & (1 << 22)) != 0)
        printf("ON\n");
    else
        printf("OFF\n");

    printf("  QSPI ");
    if ((reg_spictrl & (1 << 21)) != 0)
        printf("ON\n");
    else
        printf("OFF\n");

    printf("  CRM ");
    if ((reg_spictrl & (1 << 20)) != 0)
        printf("ON\n");
    else
        printf("OFF\n");
}

void cmd_read_flash_regs()
{
    uint8_t sr1 = cmd_read_flash_reg(0x05);
    uint8_t sr2 = cmd_read_flash_reg(0x35);
    uint8_t sr3 = cmd_read_flash_reg(0x15);

    printf("S0 (BUSY) : %d\n", sr1 & 0x01);
    printf("S1 (WEL)  : %d\n", sr1 & 0x02);
    printf("S2 (BP0)  : %d\n", sr1 & 0x04);
    printf("S3 (BP1)  : %d\n", sr1 & 0x08);
    printf("S4 (BP2)  : %d\n", sr1 & 0x10);
    printf("S5 (TB)   : %d\n", sr1 & 0x20);
    printf("S6 (SEC)  : %d\n", sr1 & 0x40);
    printf("S7 (SRP)  : %d\n\n", sr1 & 0x80);

    printf("S8  (SRL) : %d\n", sr2 & 0x01);
    printf("S9  (QE)  : %d\n", sr2 & 0x02);
    printf("S10 ----  : %d\n", sr2 & 0x04);
    printf("S11 (LB1) : %d\n", sr2 & 0x08);
    printf("S12 (LB2) : %d\n", sr2 & 0x10);
    printf("S13 (LB3) : %d\n", sr2 & 0x20);
    printf("S14 (CMP) : %d\n", sr2 & 0x40);
    printf("S15 (SUS) : %d\n\n", sr2 & 0x80);

    printf("S16 ----  : %d\n", sr3 & 0x01);
    printf("S17 ----  : %d\n", sr3 & 0x02);
    printf("S18 (WPS) : %d\n", sr3 & 0x04);
    printf("S19 ----  : %d\n", sr3 & 0x08);
    printf("S20 ----  : %d\n", sr3 & 0x10);
    printf("S21 (DRV0): %d\n", sr3 & 0x20);
    printf("S22 (DRV1): %d\n", sr3 & 0x40);
    printf("S23 (HOLD): %d\n\n", sr3 & 0x80);
}
