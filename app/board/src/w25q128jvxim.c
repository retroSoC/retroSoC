#include <stddef.h>

#include <retrosoc/board/w25q128jvxim.h>
#include <retrosoc/hal/xpi.h>
#include <retrosoc/lib/printf.h>

#define RS_W25_SEQUENCE UINT8_C(14)

static rs_status_t rs_w25_read(uint8_t command, uint8_t *data, uint16_t length) {
    uint16_t instructions[3];
    rs_xpi_transfer_t transfer;
    rs_status_t status;

    if ((data == NULL) || (length == UINT16_C(0))) {
        return RS_EINVAL;
    }
    instructions[0] = rs_xpi_instruction(RS_XPI_INSTR_COMMAND, RS_XPI_PADS_1, command);
    instructions[1] = rs_xpi_instruction(RS_XPI_INSTR_RECEIVE, RS_XPI_PADS_1, UINT8_C(0));
    instructions[2] = rs_xpi_instruction(RS_XPI_INSTR_STOP, RS_XPI_PADS_1, UINT8_C(0));

    status = rs_xpi_enable(false, RS_TIMEOUT_DEFAULT);
    if (status == RS_OK) {
        status =
            rs_xpi_lut_write(RS_W25_SEQUENCE, instructions,
                             sizeof(instructions) / sizeof(instructions[0]), RS_TIMEOUT_DEFAULT);
    }
    if (status == RS_OK) {
        status = rs_xpi_enable(true, RS_TIMEOUT_DEFAULT);
    }
    if (status != RS_OK) {
        return status;
    }

    transfer.slot = UINT8_C(0);
    transfer.sequence = RS_W25_SEQUENCE;
    transfer.address = UINT32_C(0);
    transfer.tx_data = NULL;
    transfer.rx_data = data;
    transfer.byte_count = length;
    return rs_xpi_transfer(&transfer, RS_TIMEOUT_DEFAULT);
}

void ip_norflash_test(int argc, char **argv) {
    uint8_t jedec_id[3] = {UINT8_C(0), UINT8_C(0), UINT8_C(0)};
    uint8_t status_register = UINT8_C(0);
    rs_status_t status;

    (void)argc;
    (void)argv;
    printf("W25Q128 read-only XPI test\n");
    status = rs_xpi_probe();
    if (status == RS_OK) {
        status = rs_w25_read(UINT8_C(0x9F), jedec_id, (uint16_t)sizeof(jedec_id));
    }
    if (status == RS_OK) {
        status = rs_w25_read(UINT8_C(0x05), &status_register, UINT16_C(1));
    }
    if (status != RS_OK) {
        printf("W25Q128 XPI test failed: %d\n", (int)status);
        return;
    }
    printf("JEDEC ID: %02x %02x %02x, SR1: %02x\n", (unsigned int)jedec_id[0],
           (unsigned int)jedec_id[1], (unsigned int)jedec_id[2], (unsigned int)status_register);
}
