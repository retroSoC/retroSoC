#include <firmware.h>
#include <tinyflash.h>

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