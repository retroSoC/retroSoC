#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/xpi_regs.h>

#define RS_FLASH_SIZE             UINT32_C(0x01000000)
#define RS_FLASH_SECTOR_SIZE      UINT32_C(4096)
#define RS_FLASH_PAGE_SIZE        UINT32_C(256)
#define RS_FLASH_LOADER_TIMEOUT   UINT32_C(10000000)
#define RS_FLASH_SEQUENCE_WREN    UINT32_C(1)
#define RS_FLASH_SEQUENCE_ERASE   UINT32_C(2)
#define RS_FLASH_SEQUENCE_PROGRAM UINT32_C(3)
#define RS_FLASH_SEQUENCE_STATUS  UINT32_C(4)
#define RS_FLASH_SEQUENCE_ID      UINT32_C(5)

uint8_t rs_xpi_flash_staging[RS_FLASH_SECTOR_SIZE] __attribute__((aligned(4)));
static uint8_t s_sector_cache[RS_FLASH_SECTOR_SIZE] __attribute__((aligned(4)));

int rs_xpi_flash_probe(void);
int rs_xpi_flash_update(uint32_t address, uint32_t length);

static volatile uint32_t *rs_loader_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_XPI_BASE + offset);
}

static void rs_loader_lut_write(uint32_t sequence, const uint16_t *instructions, uint32_t count) {
    uint32_t index;
    uint32_t offset = RS_XPI_REG_LUT_BASE + (sequence * UINT32_C(16));

    for (index = UINT32_C(0); index < RS_XPI_LUT_INSTRUCTION_COUNT; index += UINT32_C(2)) {
        const uint16_t low = (index < count) ? instructions[index] : UINT16_C(0);
        const uint16_t high =
            ((index + UINT32_C(1)) < count) ? instructions[index + UINT32_C(1)] : UINT16_C(0);
        *rs_loader_register(offset) = (uint32_t)low | ((uint32_t)high << UINT32_C(16));
        offset += UINT32_C(4);
    }
}

static int rs_loader_initialize(void) {
    const uint16_t write_enable[] = {
        UINT16_C(0x1006),
        UINT16_C(0x0000),
    };
    const uint16_t erase[] = {
        UINT16_C(0x1020),
        UINT16_C(0x2018),
        UINT16_C(0x0000),
    };
    const uint16_t program[] = {
        UINT16_C(0x1002),
        UINT16_C(0x2018),
        UINT16_C(0x5000),
        UINT16_C(0x0000),
    };
    const uint16_t status[] = {
        UINT16_C(0x1005),
        UINT16_C(0x6001),
        UINT16_C(0x0000),
    };
    const uint16_t read_id[] = {
        UINT16_C(0x109F),
        UINT16_C(0x6003),
        UINT16_C(0x0000),
    };

    if ((*rs_loader_register(RS_XPI_REG_ID) != RS_XPI_ID_VALUE) ||
        (*rs_loader_register(RS_XPI_REG_VERSION) != RS_XPI_VERSION_VALUE)) {
        return -1;
    }
    if ((*rs_loader_register(RS_XPI_REG_STATUS) & RS_XPI_STATUS_BUSY_ALL) != UINT32_C(0)) {
        return -2;
    }
    *rs_loader_register(RS_XPI_REG_CTRL) = UINT32_C(0);
    rs_loader_lut_write(RS_FLASH_SEQUENCE_WREN, write_enable,
                        (uint32_t)(sizeof(write_enable) / sizeof(write_enable[0])));
    rs_loader_lut_write(RS_FLASH_SEQUENCE_ERASE, erase,
                        (uint32_t)(sizeof(erase) / sizeof(erase[0])));
    rs_loader_lut_write(RS_FLASH_SEQUENCE_PROGRAM, program,
                        (uint32_t)(sizeof(program) / sizeof(program[0])));
    rs_loader_lut_write(RS_FLASH_SEQUENCE_STATUS, status,
                        (uint32_t)(sizeof(status) / sizeof(status[0])));
    rs_loader_lut_write(RS_FLASH_SEQUENCE_ID, read_id,
                        (uint32_t)(sizeof(read_id) / sizeof(read_id[0])));
    *rs_loader_register(RS_XPI_REG_CTRL) = RS_XPI_CTRL_ENABLE;
    return 0;
}

static int rs_loader_wait_done(uint32_t success_mask) {
    uint32_t timeout = RS_FLASH_LOADER_TIMEOUT;

    while (timeout-- != UINT32_C(0)) {
        const uint32_t interrupts = *rs_loader_register(RS_XPI_REG_INTR_STATE);
        if ((interrupts & RS_XPI_INTR_ERROR_ALL) != UINT32_C(0)) {
            *rs_loader_register(RS_XPI_REG_INTR_STATE) = interrupts & RS_XPI_INTR_ALL;
            return -3;
        }
        if ((interrupts & success_mask) != UINT32_C(0)) {
            *rs_loader_register(RS_XPI_REG_INTR_STATE) = interrupts & RS_XPI_INTR_ALL;
            return 0;
        }
    }
    *rs_loader_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_ABORT;
    return -4;
}

static int rs_loader_transfer(uint32_t sequence, uint32_t address, const uint8_t *data,
                              uint32_t length) {
    uint32_t offset = UINT32_C(0);

    *rs_loader_register(RS_XPI_REG_FIFO_CTRL) = UINT32_C(0x00031010);
    *rs_loader_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_loader_register(RS_XPI_REG_INDIRECT_ADDR) = address;
    *rs_loader_register(RS_XPI_REG_INDIRECT_COUNT) = length;
    *rs_loader_register(RS_XPI_REG_INDIRECT_CFG) = sequence << UINT32_C(4);

    while (offset < length) {
        uint32_t value = UINT32_C(0);
        uint32_t byte_index;

        for (byte_index = UINT32_C(0);
             (byte_index < UINT32_C(4)) && ((offset + byte_index) < length); byte_index++) {
            value |= (uint32_t)data[offset + byte_index] << (byte_index * UINT32_C(8));
        }
        *rs_loader_register(RS_XPI_REG_TXDATA) = value;
        offset += UINT32_C(4);
    }
    *rs_loader_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_INDIRECT_START;
    return rs_loader_wait_done(RS_XPI_INTR_INDIRECT_DONE);
}

static int rs_loader_write_enable(void) {
    return rs_loader_transfer(RS_FLASH_SEQUENCE_WREN, UINT32_C(0), NULL, UINT32_C(0));
}

static int rs_loader_wait_ready(void) {
    *rs_loader_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_loader_register(RS_XPI_REG_POLL_CFG) = RS_FLASH_SEQUENCE_STATUS << UINT32_C(4);
    *rs_loader_register(RS_XPI_REG_POLL_MASK) = UINT32_C(1);
    *rs_loader_register(RS_XPI_REG_POLL_MATCH) = UINT32_C(0);
    *rs_loader_register(RS_XPI_REG_POLL_INTERVAL) = UINT32_C(16);
    *rs_loader_register(RS_XPI_REG_POLL_TIMEOUT) = RS_FLASH_LOADER_TIMEOUT;
    *rs_loader_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_POLL_START;
    return rs_loader_wait_done(RS_XPI_INTR_POLL_MATCH);
}

static int rs_loader_erase(uint32_t address) {
    int result = rs_loader_write_enable();

    if (result == 0) {
        result = rs_loader_transfer(RS_FLASH_SEQUENCE_ERASE, address, NULL, UINT32_C(0));
    }
    if (result == 0) {
        result = rs_loader_wait_ready();
    }
    return result;
}

static int rs_loader_program_page(uint32_t address, const uint8_t *data) {
    int result = rs_loader_write_enable();

    if (result == 0) {
        result = rs_loader_transfer(RS_FLASH_SEQUENCE_PROGRAM, address, data, RS_FLASH_PAGE_SIZE);
    }
    if (result == 0) {
        result = rs_loader_wait_ready();
    }
    return result;
}

__attribute__((noinline, used)) int rs_xpi_flash_probe(void) {
    uint8_t id[4] = {UINT8_C(0), UINT8_C(0), UINT8_C(0), UINT8_C(0)};
    uint32_t offset = UINT32_C(0);
    int result = rs_loader_initialize();

    if (result != 0) {
        return result;
    }
    *rs_loader_register(RS_XPI_REG_FIFO_CTRL) = UINT32_C(0x00031010);
    *rs_loader_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_loader_register(RS_XPI_REG_INDIRECT_COUNT) = UINT32_C(3);
    *rs_loader_register(RS_XPI_REG_INDIRECT_CFG) = RS_FLASH_SEQUENCE_ID << UINT32_C(4);
    *rs_loader_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_INDIRECT_START;
    result = rs_loader_wait_done(RS_XPI_INTR_INDIRECT_DONE);
    while ((result == 0) && (offset < UINT32_C(3))) {
        if ((*rs_loader_register(RS_XPI_REG_FIFO_STATUS) & RS_XPI_FIFO_RX_EMPTY) == UINT32_C(0)) {
            const uint32_t value = *rs_loader_register(RS_XPI_REG_RXDATA);
            uint32_t byte_index;
            for (byte_index = UINT32_C(0);
                 (byte_index < UINT32_C(4)) && ((offset + byte_index) < UINT32_C(3));
                 byte_index++) {
                id[offset + byte_index] = (uint8_t)(value >> (byte_index * UINT32_C(8)));
            }
            offset += UINT32_C(4);
        }
    }
    if ((result == 0) && (id[0] == UINT8_C(0xEF)) && (id[1] == UINT8_C(0x40)) &&
        (id[2] == UINT8_C(0x18))) {
        return 0;
    }
    return -5;
}

__attribute__((noinline, used)) int rs_xpi_flash_update(uint32_t address, uint32_t length) {
    volatile const uint8_t *flash;
    uint32_t sector_address;
    uint32_t sector_offset;
    uint32_t index;
    int result;

    if ((length == UINT32_C(0)) || (length > RS_FLASH_SECTOR_SIZE) || (address >= RS_FLASH_SIZE) ||
        (length > (RS_FLASH_SIZE - address))) {
        return -6;
    }
    sector_address = address & ~(RS_FLASH_SECTOR_SIZE - UINT32_C(1));
    sector_offset = address - sector_address;
    if (length > (RS_FLASH_SECTOR_SIZE - sector_offset)) {
        return -7;
    }
    result = rs_loader_initialize();
    if (result != 0) {
        return result;
    }
    flash = (volatile const uint8_t *)(uintptr_t)(RS_SOC_FLASH_BASE + sector_address);
    for (index = UINT32_C(0); index < RS_FLASH_SECTOR_SIZE; index++) {
        s_sector_cache[index] = flash[index];
    }
    for (index = UINT32_C(0); index < length; index++) {
        s_sector_cache[sector_offset + index] = rs_xpi_flash_staging[index];
    }

    result = rs_loader_erase(sector_address);
    for (index = UINT32_C(0); (result == 0) && (index < RS_FLASH_SECTOR_SIZE);
         index += RS_FLASH_PAGE_SIZE) {
        result = rs_loader_program_page(sector_address + index, &s_sector_cache[index]);
    }
    for (index = UINT32_C(0); (result == 0) && (index < RS_FLASH_SECTOR_SIZE); index++) {
        if (flash[index] != s_sector_cache[index]) {
            result = -8;
        }
    }
    return result;
}

int main(void) {
    for (;;) {
        __asm__ volatile("ebreak" ::: "memory");
    }
}
