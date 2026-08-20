#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/lib/printf.h>

#define RS_SPISD_CMD0                UINT8_C(0)
#define RS_SPISD_CMD6                UINT8_C(6)
#define RS_SPISD_CMD8                UINT8_C(8)
#define RS_SPISD_CMD9                UINT8_C(9)
#define RS_SPISD_CMD16               UINT8_C(16)
#define RS_SPISD_CMD17               UINT8_C(17)
#define RS_SPISD_CMD18               UINT8_C(18)
#define RS_SPISD_CMD23               UINT8_C(23)
#define RS_SPISD_CMD24               UINT8_C(24)
#define RS_SPISD_CMD25               UINT8_C(25)
#define RS_SPISD_CMD41               UINT8_C(41)
#define RS_SPISD_CMD55               UINT8_C(55)
#define RS_SPISD_CMD58               UINT8_C(58)
#define RS_SPISD_CMD59               UINT8_C(59)

#define RS_SPISD_R1_IDLE             UINT8_C(0x01)
#define RS_SPISD_R1_ILLEGAL_COMMAND  UINT8_C(0x04)
#define RS_SPISD_ACMD41_HCS          UINT32_C(0x40000000)
#define RS_SPISD_OCR_CCS             UINT32_C(0x40000000)
#define RS_SPISD_CMD6_HIGH_SPEED_ARG UINT32_C(0x80FFFFF1)
#define RS_SPISD_CMD6_STATUS_BYTES   UINT32_C(64)
#define RS_SPISD_CMD6_GROUP1_BYTE    UINT32_C(16)

static rs_spisd_card_info_t rs_spisd_card_info;
static _Alignas(4) uint8_t rs_spisd_sector_buffer[RS_SPISD_SECTOR_SIZE];

static volatile uint32_t *rs_spisd_reg(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_SPISD_BASE + offset);
}

static uint32_t rs_spisd_reg_read(uint32_t offset) {
    return *rs_spisd_reg(offset);
}

static void rs_spisd_reg_write(uint32_t offset, uint32_t value) {
    *rs_spisd_reg(offset) = value;
}

static rs_status_t rs_spisd_wait_idle(rs_timeout_t timeout) {
    return rs_wait_mask(rs_spisd_reg(RS_SPISD_REG_STATUS), RS_SPISD_STATUS_BUSY, 0U, timeout);
}

static bool rs_spisd_response_type_valid(rs_spisd_response_type_t response) {
    switch (response) {
    case RS_SPISD_RESPONSE_NONE:
    case RS_SPISD_RESPONSE_R1:
    case RS_SPISD_RESPONSE_R1B:
    case RS_SPISD_RESPONSE_R2:
    case RS_SPISD_RESPONSE_R3:
    case RS_SPISD_RESPONSE_R7:
        return true;
    default:
        return false;
    }
}

static void rs_spisd_response_read(rs_spisd_response_type_t type, rs_spisd_response_t *response) {
    uint32_t low;
    uint32_t high;

    if (response == NULL) {
        return;
    }
    low = rs_spisd_reg_read(RS_SPISD_REG_RESP0);
    high = rs_spisd_reg_read(RS_SPISD_REG_RESP1) & UINT32_C(0xFF);
    if ((type == RS_SPISD_RESPONSE_R3) || (type == RS_SPISD_RESPONSE_R7)) {
        response->bytes[0] = (uint8_t)high;
        response->bytes[1] = (uint8_t)(low >> 24U);
        response->bytes[2] = (uint8_t)(low >> 16U);
        response->bytes[3] = (uint8_t)(low >> 8U);
        response->bytes[4] = (uint8_t)low;
    } else if (type == RS_SPISD_RESPONSE_R2) {
        response->bytes[0] = (uint8_t)(low >> 8U);
        response->bytes[1] = (uint8_t)low;
        response->bytes[2] = 0U;
        response->bytes[3] = 0U;
        response->bytes[4] = 0U;
    } else {
        response->bytes[0] = (uint8_t)low;
        response->bytes[1] = 0U;
        response->bytes[2] = 0U;
        response->bytes[3] = 0U;
        response->bytes[4] = 0U;
    }
}

static rs_status_t rs_spisd_result(void) {
    const uint32_t irq = rs_spisd_reg_read(RS_SPISD_REG_IRQ_STATUS);
    const uint32_t command_status = rs_spisd_reg_read(RS_SPISD_REG_CMD_STATUS);
    const uint32_t data_status = rs_spisd_reg_read(RS_SPISD_REG_DATA_STATUS);
    const uint32_t dma_status = rs_spisd_reg_read(RS_SPISD_REG_DMA_STATUS);

    if (((command_status & RS_SPISD_CMD_STATUS_TIMEOUT) != 0U) ||
        ((data_status & (RS_SPISD_DATA_STATUS_TIMEOUT | RS_SPISD_DATA_STATUS_BUSY_TIMEOUT)) !=
         0U)) {
        return RS_ETIMEOUT;
    }
    if ((data_status & RS_SPISD_DATA_STATUS_CRC_ERROR) != 0U) {
        return RS_EFORMAT;
    }
    if ((irq & (RS_SPISD_IRQ_CMD_ERROR | RS_SPISD_IRQ_DATA_ERROR | RS_SPISD_IRQ_DMA_ERROR |
                RS_SPISD_IRQ_ABORT)) != 0U) {
        return RS_EIO;
    }
    if (((command_status & RS_SPISD_CMD_STATUS_ERROR) != 0U) ||
        ((data_status & RS_SPISD_DATA_STATUS_ERROR) != 0U) ||
        ((dma_status & RS_SPISD_DMA_STATUS_ERROR) != 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

static void rs_spisd_command_prepare(const rs_spisd_command_t *command, bool data_present,
                                     bool auto_stop) {
    uint32_t config = (uint32_t)command->index;

    config |= (uint32_t)command->response << RS_SPISD_CMD_CFG_RESP_LSB;
    if (command->stuff_byte) {
        config |= UINT32_C(1) << RS_SPISD_CMD_CFG_STUFF_BIT;
    }
    if (data_present) {
        config |= UINT32_C(1) << RS_SPISD_CMD_CFG_DATA_BIT;
    }
    if (auto_stop) {
        config |= UINT32_C(1) << RS_SPISD_CMD_CFG_AUTO_STOP_BIT;
    }
    rs_spisd_reg_write(RS_SPISD_REG_IRQ_STATUS, RS_SPISD_IRQ_ALL);
    rs_spisd_reg_write(RS_SPISD_REG_ERROR_STATUS, RS_SPISD_ERROR_ALL);
    rs_spisd_reg_write(RS_SPISD_REG_CMD_ARG, command->argument);
    rs_spisd_reg_write(RS_SPISD_REG_CMD_CFG, config);
}

static uint32_t rs_spisd_response_payload(const rs_spisd_response_t *response) {
    return ((uint32_t)response->bytes[1] << 24U) | ((uint32_t)response->bytes[2] << 16U) |
           ((uint32_t)response->bytes[3] << 8U) | (uint32_t)response->bytes[4];
}

static uint32_t rs_spisd_load_word(const uint8_t *buffer) {
    return (uint32_t)buffer[0] | ((uint32_t)buffer[1] << 8U) | ((uint32_t)buffer[2] << 16U) |
           ((uint32_t)buffer[3] << 24U);
}

static void rs_spisd_store_word(uint8_t *buffer, uint32_t word) {
    buffer[0] = (uint8_t)word;
    buffer[1] = (uint8_t)(word >> 8U);
    buffer[2] = (uint8_t)(word >> 16U);
    buffer[3] = (uint8_t)(word >> 24U);
}

static rs_status_t rs_spisd_data_command(uint8_t index, uint32_t argument, bool to_card, bool dma,
                                         bool multi_block, uint16_t block_size,
                                         uint16_t block_count) {
    const rs_spisd_command_t command = {
        .index = index,
        .argument = argument,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    uint32_t data_config = UINT32_C(1) << RS_SPISD_DATA_CRC_BIT;

    if (to_card) {
        data_config |= UINT32_C(1) << RS_SPISD_DATA_DIRECTION_BIT;
    }
    if (dma) {
        data_config |= UINT32_C(1) << RS_SPISD_DATA_DMA_BIT;
    }
    if (multi_block) {
        data_config |= UINT32_C(1) << RS_SPISD_DATA_MULTI_BIT;
    }
    rs_spisd_reg_write(RS_SPISD_REG_BLOCK_SIZE, block_size);
    rs_spisd_reg_write(RS_SPISD_REG_BLOCK_COUNT, block_count);
    rs_spisd_reg_write(RS_SPISD_REG_DATA_CFG, data_config);
    rs_spisd_command_prepare(&command, true, multi_block && !to_card);
    rs_spisd_reg_write(RS_SPISD_REG_CMD_START, 1U);
    return RS_OK;
}

static rs_status_t rs_spisd_transfer_pio(uint8_t *buffer, size_t byte_count, uint8_t index,
                                         uint32_t argument, bool to_card, uint16_t block_size,
                                         uint16_t block_count, rs_timeout_t timeout) {
    size_t offset = 0U;
    uint32_t fifo_status;
    uint32_t word;
    const bool multi_block = block_count > 1U;

    if ((buffer == NULL) || (byte_count == 0U) || ((byte_count & 3U) != 0U)) {
        return RS_EINVAL;
    }
    if (to_card) {
        while ((offset < byte_count) &&
               ((rs_spisd_reg_read(RS_SPISD_REG_FIFO_STATUS) & RS_SPISD_FIFO_TX_FULL) == 0U)) {
            rs_spisd_reg_write(RS_SPISD_REG_PIO_DATA, rs_spisd_load_word(&buffer[offset]));
            offset += 4U;
        }
    }
    (void)rs_spisd_data_command(index, argument, to_card, false, multi_block, block_size,
                                block_count);
    while ((rs_spisd_reg_read(RS_SPISD_REG_STATUS) & RS_SPISD_STATUS_BUSY) != 0U) {
        if (timeout == 0U) {
            (void)rs_spisd_abort(RS_TIMEOUT_DEFAULT);
            return RS_ETIMEOUT;
        }
        --timeout;
        fifo_status = rs_spisd_reg_read(RS_SPISD_REG_FIFO_STATUS);
        if (to_card) {
            if ((offset < byte_count) && ((fifo_status & RS_SPISD_FIFO_TX_FULL) == 0U)) {
                rs_spisd_reg_write(RS_SPISD_REG_PIO_DATA, rs_spisd_load_word(&buffer[offset]));
                offset += 4U;
            }
        } else if ((offset < byte_count) && ((fifo_status & RS_SPISD_FIFO_RX_EMPTY) == 0U)) {
            word = rs_spisd_reg_read(RS_SPISD_REG_PIO_DATA);
            rs_spisd_store_word(&buffer[offset], word);
            offset += 4U;
        } else {
            /* Poll until the serial engine or FIFO can make progress. */
        }
    }
    if (!to_card) {
        while ((offset < byte_count) &&
               ((rs_spisd_reg_read(RS_SPISD_REG_FIFO_STATUS) & RS_SPISD_FIFO_RX_EMPTY) == 0U)) {
            word = rs_spisd_reg_read(RS_SPISD_REG_PIO_DATA);
            rs_spisd_store_word(&buffer[offset], word);
            offset += 4U;
        }
    }
    if (offset != byte_count) {
        return RS_EIO;
    }
    return rs_spisd_result();
}

static rs_status_t rs_spisd_transfer_dma(uint8_t *buffer, size_t byte_count, uint8_t index,
                                         uint32_t argument, bool to_card, uint16_t block_count,
                                         rs_timeout_t timeout) {
    _Alignas(16) rs_spisd_descriptor_t descriptors[2];
    rs_spisd_descriptor_t *descriptor = &descriptors[0];
    const uintptr_t buffer_address = (uintptr_t)buffer;
    uintptr_t descriptor_address = (uintptr_t)descriptor;
    rs_status_t status;

    if ((descriptor_address & UINT32_C(0xFFF)) >= UINT32_C(0xFF0)) {
        descriptor = &descriptors[1];
        descriptor_address = (uintptr_t)descriptor;
    }
    if ((buffer == NULL) || (byte_count == 0U) || (byte_count > UINT32_MAX) ||
        ((buffer_address & 3U) != 0U) || (buffer_address > UINT32_MAX) ||
        (descriptor_address > UINT32_MAX)) {
        return RS_EINVAL;
    }
    if ((rs_spisd_descriptor_prepare(descriptor, buffer_address, byte_count, (uintptr_t)0U, true,
                                     true) != RS_OK) ||
        (rs_spisd_descriptor_publish(descriptor) != RS_OK)) {
        return RS_EINVAL;
    }
    rs_spisd_reg_write(RS_SPISD_REG_DESC_BASE, (uint32_t)descriptor_address);
    rs_spisd_reg_write(RS_SPISD_REG_DESC_COUNT, 1U);
    status = rs_spisd_data_command(index, argument, to_card, true, block_count > 1U,
                                   (uint16_t)RS_SPISD_SECTOR_SIZE, block_count);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spisd_wait_idle(timeout);
    rs_spisd_memory_barrier();
    if (status != RS_OK) {
        (void)rs_spisd_abort(RS_TIMEOUT_DEFAULT);
        return status;
    }
    status = rs_spisd_result();
    if ((status == RS_OK) &&
        (((descriptor->control_status & RS_SPISD_DESC_DONE) == 0U) ||
         ((descriptor->control_status & (RS_SPISD_DESC_OWN | RS_SPISD_DESC_ERROR)) != 0U))) {
        status = RS_EIO;
    }
    return status;
}

static rs_status_t rs_spisd_send_app_command(uint8_t index, uint32_t argument,
                                             rs_spisd_response_t *response, rs_timeout_t timeout) {
    const rs_spisd_command_t prefix = {
        .index = RS_SPISD_CMD55,
        .argument = 0U,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    const rs_spisd_command_t command = {
        .index = index,
        .argument = argument,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    rs_spisd_response_t prefix_response;
    rs_status_t status;

    status = rs_spisd_command_execute(&prefix, &prefix_response, timeout);
    if ((status != RS_OK) || ((prefix_response.bytes[0] & (uint8_t)~RS_SPISD_R1_IDLE) != 0U)) {
        return (status == RS_OK) ? RS_EIO : status;
    }
    return rs_spisd_command_execute(&command, response, timeout);
}

rs_status_t rs_spisd_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability) {
    if ((ip_id == NULL) || (version == NULL) || (capability == NULL)) {
        return RS_EINVAL;
    }
    *ip_id = rs_spisd_reg_read(RS_SPISD_REG_IP_ID);
    *version = rs_spisd_reg_read(RS_SPISD_REG_IP_VERSION);
    *capability = rs_spisd_reg_read(RS_SPISD_REG_CAPABILITY);
    return ((*ip_id == RS_SPISD_IP_ID_VALUE) && (*version == RS_SPISD_IP_VERSION_VALUE))
               ? RS_OK
               : RS_EFORMAT;
}

rs_status_t rs_spisd_clock_set(uint32_t source_clock_hz, uint32_t target_clock_hz,
                               uint32_t *actual_clock_hz) {
    rs_spisd_clock_t clock;
    uint32_t control;

    if (((rs_spisd_reg_read(RS_SPISD_REG_STATUS) & RS_SPISD_STATUS_BUSY) != 0U) ||
        (rs_spisd_clock_calculate(source_clock_hz, target_clock_hz, &clock) != RS_OK)) {
        return RS_EINVAL;
    }
    control =
        rs_spisd_reg_read(RS_SPISD_REG_CLOCK_CTRL) & (UINT32_C(1) << RS_SPISD_CLOCK_ENABLE_BIT);
    control |= (uint32_t)clock.half_period << RS_SPISD_CLOCK_HALF_PERIOD_LSB;
    rs_spisd_reg_write(RS_SPISD_REG_CLOCK_CTRL, control);
    if (actual_clock_hz != NULL) {
        *actual_clock_hz = clock.actual_hz;
    }
    return RS_OK;
}

rs_status_t rs_spisd_command_execute(const rs_spisd_command_t *command,
                                     rs_spisd_response_t *response, rs_timeout_t timeout) {
    rs_status_t status;

    if ((command == NULL) || (command->index > UINT8_C(63)) ||
        !rs_spisd_response_type_valid(command->response) ||
        ((rs_spisd_reg_read(RS_SPISD_REG_STATUS) & RS_SPISD_STATUS_BUSY) != 0U)) {
        return RS_EINVAL;
    }
    rs_spisd_command_prepare(command, false, false);
    rs_spisd_reg_write(RS_SPISD_REG_CMD_START, 1U);
    status = rs_spisd_wait_idle(timeout);
    if (status != RS_OK) {
        (void)rs_spisd_abort(RS_TIMEOUT_DEFAULT);
        return status;
    }
    rs_spisd_response_read(command->response, response);
    return rs_spisd_result();
}

rs_status_t rs_spisd_abort(rs_timeout_t timeout) {
    uint32_t control = rs_spisd_reg_read(RS_SPISD_REG_HOST_CTRL);

    control |= UINT32_C(1) << RS_SPISD_HOST_CTRL_ABORT_BIT;
    rs_spisd_reg_write(RS_SPISD_REG_HOST_CTRL, control);
    return rs_spisd_wait_idle(timeout);
}

rs_status_t rs_spisd_irq_enable(uint32_t mask) {
    uint32_t control;

    if ((mask & ~RS_SPISD_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    rs_spisd_reg_write(RS_SPISD_REG_IRQ_ENABLE, mask);
    control = rs_spisd_reg_read(RS_SPISD_REG_HOST_CTRL);
    control |= UINT32_C(1) << RS_SPISD_HOST_CTRL_IRQ_BIT;
    rs_spisd_reg_write(RS_SPISD_REG_HOST_CTRL, control);
    return RS_OK;
}

rs_status_t rs_spisd_irq_clear(uint32_t mask) {
    if ((mask & ~RS_SPISD_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    rs_spisd_reg_write(RS_SPISD_REG_IRQ_STATUS, mask);
    return RS_OK;
}

uint32_t rs_spisd_irq_status(void) {
    return rs_spisd_reg_read(RS_SPISD_REG_IRQ_STATUS);
}

rs_status_t rs_spisd_initialize(uint32_t source_clock_hz, rs_timeout_t timeout) {
    const rs_spisd_command_t cmd0 = {
        .index = RS_SPISD_CMD0,
        .argument = 0U,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    const rs_spisd_command_t cmd8 = {
        .index = RS_SPISD_CMD8,
        .argument = UINT32_C(0x000001AA),
        .response = RS_SPISD_RESPONSE_R7,
        .stuff_byte = false,
    };
    const rs_spisd_command_t cmd58 = {
        .index = RS_SPISD_CMD58,
        .argument = 0U,
        .response = RS_SPISD_RESPONSE_R3,
        .stuff_byte = false,
    };
    const rs_spisd_command_t cmd16 = {
        .index = RS_SPISD_CMD16,
        .argument = RS_SPISD_SECTOR_SIZE,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    const rs_spisd_command_t cmd59 = {
        .index = RS_SPISD_CMD59,
        .argument = 1U,
        .response = RS_SPISD_RESPONSE_R1,
        .stuff_byte = false,
    };
    rs_spisd_response_t response;
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability;
    uint32_t control;
    uint32_t actual_clock;
    uint32_t retries;
    bool card_v2;
    bool ocr_high_capacity;
    rs_status_t status;

    status = rs_spisd_probe(&ip_id, &version, &capability);
    if ((status != RS_OK) || (source_clock_hz == 0U)) {
        return (status == RS_OK) ? RS_EINVAL : status;
    }
    if ((capability & RS_SPISD_CAP_REQUIRED) != RS_SPISD_CAP_REQUIRED) {
        return RS_ENOTSUP;
    }
    rs_spisd_card_info.initialized = false;
    (void)rs_spisd_abort(timeout);
    rs_spisd_reg_write(RS_SPISD_REG_IRQ_STATUS, RS_SPISD_IRQ_ALL);
    rs_spisd_reg_write(RS_SPISD_REG_ERROR_STATUS, RS_SPISD_ERROR_ALL);
    rs_spisd_reg_write(RS_SPISD_REG_TIMEOUT_CMD, source_clock_hz);
    rs_spisd_reg_write(RS_SPISD_REG_TIMEOUT_DATA, source_clock_hz);
    rs_spisd_reg_write(RS_SPISD_REG_TIMEOUT_BUSY,
                       (source_clock_hz > (UINT32_MAX / 5U)) ? UINT32_MAX : source_clock_hz * 5U);
    rs_spisd_reg_write(RS_SPISD_REG_HOST_CTRL, UINT32_C(1) << RS_SPISD_HOST_CTRL_ENABLE_BIT);
    status = rs_spisd_clock_set(source_clock_hz, RS_SPISD_INIT_CLOCK_HZ, &actual_clock);
    if (status != RS_OK) {
        return status;
    }
    control = rs_spisd_reg_read(RS_SPISD_REG_CLOCK_CTRL);
    control |=
        (UINT32_C(1) << RS_SPISD_CLOCK_ENABLE_BIT) | (UINT32_C(1) << RS_SPISD_CLOCK_TRAIN_BIT);
    rs_spisd_reg_write(RS_SPISD_REG_CLOCK_CTRL, control);
    status = rs_spisd_wait_idle(timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spisd_command_execute(&cmd0, &response, timeout);
    if ((status != RS_OK) || (response.bytes[0] != RS_SPISD_R1_IDLE)) {
        return (status == RS_OK) ? RS_EIO : status;
    }
    status = rs_spisd_command_execute(&cmd8, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    card_v2 = (response.bytes[0] == RS_SPISD_R1_IDLE);
    if (card_v2) {
        if ((response.bytes[3] != UINT8_C(0x01)) || (response.bytes[4] != UINT8_C(0xAA))) {
            return RS_EFORMAT;
        }
    } else if (response.bytes[0] != (RS_SPISD_R1_IDLE | RS_SPISD_R1_ILLEGAL_COMMAND)) {
        return RS_EIO;
    }
    retries = timeout;
    do {
        status = rs_spisd_send_app_command(RS_SPISD_CMD41, card_v2 ? RS_SPISD_ACMD41_HCS : 0U,
                                           &response, timeout);
        if (status != RS_OK) {
            return status;
        }
        if (response.bytes[0] == 0U) {
            break;
        }
        if (retries == 0U) {
            return RS_ETIMEOUT;
        }
        --retries;
    } while (response.bytes[0] == RS_SPISD_R1_IDLE);
    if (response.bytes[0] != 0U) {
        return RS_EIO;
    }
    status = rs_spisd_command_execute(&cmd58, &response, timeout);
    if ((status != RS_OK) || (response.bytes[0] != 0U)) {
        return (status == RS_OK) ? RS_EIO : status;
    }
    rs_spisd_card_info.ocr = rs_spisd_response_payload(&response);
    ocr_high_capacity = card_v2 && ((rs_spisd_card_info.ocr & RS_SPISD_OCR_CCS) != 0U);
    status =
        rs_spisd_transfer_pio(rs_spisd_card_info.csd, sizeof(rs_spisd_card_info.csd), RS_SPISD_CMD9,
                              0U, false, (uint16_t)sizeof(rs_spisd_card_info.csd), 1U, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spisd_parse_csd(rs_spisd_card_info.csd, &rs_spisd_card_info);
    if ((status != RS_OK) || (rs_spisd_card_info.high_capacity != ocr_high_capacity)) {
        return (status == RS_OK) ? RS_EFORMAT : status;
    }
    if (!rs_spisd_card_info.high_capacity) {
        status = rs_spisd_command_execute(&cmd16, &response, timeout);
        if ((status != RS_OK) || (response.bytes[0] != 0U)) {
            return (status == RS_OK) ? RS_EIO : status;
        }
    }
    status = rs_spisd_command_execute(&cmd59, &response, timeout);
    if ((status != RS_OK) ||
        ((response.bytes[0] != 0U) && (response.bytes[0] != RS_SPISD_R1_ILLEGAL_COMMAND))) {
        return (status == RS_OK) ? RS_EIO : status;
    }
    status = rs_spisd_clock_set(source_clock_hz, RS_SPISD_DEFAULT_HZ, &actual_clock);
    if (status != RS_OK) {
        return status;
    }
    rs_spisd_card_info.actual_clock_hz = actual_clock;
    rs_spisd_card_info.high_speed = false;
    rs_spisd_card_info.initialized = true;
    return RS_OK;
}

rs_status_t rs_spisd_high_speed_enable(uint32_t source_clock_hz, rs_timeout_t timeout) {
    _Alignas(4) uint8_t switch_status[RS_SPISD_CMD6_STATUS_BYTES];
    rs_spisd_clock_t clock;
    uint32_t target_clock_hz;
    rs_status_t status;

    if (!rs_spisd_card_info.initialized || (timeout == 0U)) {
        return RS_EINVAL;
    }
    target_clock_hz = source_clock_hz / 2U;
    if (target_clock_hz > RS_SPISD_HIGH_SPEED_HZ) {
        target_clock_hz = RS_SPISD_HIGH_SPEED_HZ;
    }
    status = rs_spisd_clock_calculate(source_clock_hz, target_clock_hz, &clock);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spisd_transfer_pio(switch_status, sizeof(switch_status), RS_SPISD_CMD6,
                                   RS_SPISD_CMD6_HIGH_SPEED_ARG, false,
                                   (uint16_t)sizeof(switch_status), 1U, timeout);
    if (status != RS_OK) {
        return status;
    }
    if ((switch_status[RS_SPISD_CMD6_GROUP1_BYTE] & UINT8_C(0x0F)) != UINT8_C(1)) {
        return RS_ENOTSUP;
    }
    status =
        rs_spisd_clock_set(source_clock_hz, target_clock_hz, &rs_spisd_card_info.actual_clock_hz);
    if (status == RS_OK) {
        rs_spisd_card_info.high_speed = true;
    }
    return status;
}

rs_status_t rs_spisd_card_info_get(rs_spisd_card_info_t *info) {
    if ((info == NULL) || !rs_spisd_card_info.initialized) {
        return RS_EINVAL;
    }
    *info = rs_spisd_card_info;
    return RS_OK;
}

rs_status_t rs_spisd_sector_read(uint8_t *buffer, uint32_t sector, uint32_t count) {
    uint32_t argument;
    size_t byte_count;
    uint8_t command;
    rs_status_t status;

    if (!rs_spisd_card_info.initialized) {
        status = rs_spisd_initialize((uint32_t)CPU_FREQ * UINT32_C(1000000), RS_TIMEOUT_DEFAULT);
        if (status != RS_OK) {
            return status;
        }
    }
    if ((buffer == NULL) || (count == 0U) || (sector >= rs_spisd_card_info.capacity_blocks) ||
        (count > (rs_spisd_card_info.capacity_blocks - sector)) ||
        (count > (SIZE_MAX / RS_SPISD_SECTOR_SIZE)) || (count > UINT16_MAX)) {
        return RS_EINVAL;
    }
    status = rs_spisd_card_address(rs_spisd_card_info.card_type, sector, &argument);
    if (status != RS_OK) {
        return status;
    }
    byte_count = (size_t)count * RS_SPISD_SECTOR_SIZE;
    command = (count > 1U) ? RS_SPISD_CMD18 : RS_SPISD_CMD17;
    if ((((uintptr_t)buffer & 3U) == 0U) && ((uintptr_t)buffer <= UINT32_MAX)) {
        return rs_spisd_transfer_dma(buffer, byte_count, command, argument, false, (uint16_t)count,
                                     RS_TIMEOUT_DEFAULT);
    }
    return rs_spisd_transfer_pio(buffer, byte_count, command, argument, false,
                                 (uint16_t)RS_SPISD_SECTOR_SIZE, (uint16_t)count,
                                 RS_TIMEOUT_DEFAULT);
}

rs_status_t rs_spisd_sector_write(const uint8_t *buffer, uint32_t sector, uint32_t count) {
    uint32_t argument;
    size_t byte_count;
    uint8_t command;
    rs_spisd_response_t response;
    rs_status_t status;

    if (!rs_spisd_card_info.initialized) {
        status = rs_spisd_initialize((uint32_t)CPU_FREQ * UINT32_C(1000000), RS_TIMEOUT_DEFAULT);
        if (status != RS_OK) {
            return status;
        }
    }
    if ((buffer == NULL) || (count == 0U) || (sector >= rs_spisd_card_info.capacity_blocks) ||
        (count > (rs_spisd_card_info.capacity_blocks - sector)) ||
        (count > (SIZE_MAX / RS_SPISD_SECTOR_SIZE)) || (count > UINT16_MAX)) {
        return RS_EINVAL;
    }
    status = rs_spisd_card_address(rs_spisd_card_info.card_type, sector, &argument);
    if (status != RS_OK) {
        return status;
    }
    if (count > 1U) {
        status = rs_spisd_send_app_command(RS_SPISD_CMD23, count, &response, RS_TIMEOUT_DEFAULT);
        if ((status != RS_OK) || (response.bytes[0] != 0U)) {
            return (status == RS_OK) ? RS_EIO : status;
        }
    }
    byte_count = (size_t)count * RS_SPISD_SECTOR_SIZE;
    command = (count > 1U) ? RS_SPISD_CMD25 : RS_SPISD_CMD24;
    if ((((uintptr_t)buffer & 3U) == 0U) && ((uintptr_t)buffer <= UINT32_MAX)) {
        return rs_spisd_transfer_dma((uint8_t *)(uintptr_t)buffer, byte_count, command, argument,
                                     true, (uint16_t)count, RS_TIMEOUT_DEFAULT);
    }
    return rs_spisd_transfer_pio((uint8_t *)(uintptr_t)buffer, byte_count, command, argument, true,
                                 (uint16_t)RS_SPISD_SECTOR_SIZE, (uint16_t)count,
                                 RS_TIMEOUT_DEFAULT);
}

rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address) {
    uint8_t *destination = (uint8_t *)buffer;
    uintptr_t card_offset;
    uint32_t sector;
    size_t sector_offset;
    size_t chunk;
    rs_status_t status;

    if ((buffer == NULL) || (address < (uintptr_t)TF_CARD_START)) {
        return RS_EINVAL;
    }
    if (byte_count == 0U) {
        return RS_OK;
    }
    card_offset = address - (uintptr_t)TF_CARD_START;
    while (byte_count != 0U) {
        if ((card_offset / RS_SPISD_SECTOR_SIZE) > UINT32_MAX) {
            return RS_EINVAL;
        }
        sector = (uint32_t)(card_offset / RS_SPISD_SECTOR_SIZE);
        sector_offset = (size_t)(card_offset % RS_SPISD_SECTOR_SIZE);
        chunk = RS_SPISD_SECTOR_SIZE - sector_offset;
        if (chunk > byte_count) {
            chunk = byte_count;
        }
        status = rs_spisd_sector_read(rs_spisd_sector_buffer, sector, 1U);
        if (status != RS_OK) {
            return status;
        }
        for (size_t index = 0U; index < chunk; ++index) {
            destination[index] = rs_spisd_sector_buffer[sector_offset + index];
        }
        destination = &destination[chunk];
        card_offset += chunk;
        byte_count -= chunk;
    }
    return RS_OK;
}

rs_status_t rs_spisd_sector_sync(rs_timeout_t timeout) {
    const rs_status_t status = rs_spisd_wait_idle(timeout);

    rs_spisd_memory_barrier();
    return status;
}

void ip_spisd_test(void) {
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability;
    rs_spisd_card_info_t info;

    printf("spisd test\n");
    if (rs_spisd_probe(&ip_id, &version, &capability) != RS_OK) {
        printf("[SPISD] probe failed\n");
    } else {
        printf("[SPISD] id=%x version=%x capability=%x\n", ip_id, version, capability);
    }
    if (rs_spisd_card_info_get(&info) == RS_OK) {
        printf("[SPISD] blocks=%u clock=%u Hz\n", info.capacity_blocks, info.actual_clock_hz);
    }
}

void ip_spisd_read(uint32_t address, uint32_t length) {
    uint32_t value;

    printf("spisd read test\n");
    for (uint32_t index = 0U; index < length; ++index) {
        if (rs_spisd_read_bytes(&value, sizeof(value),
                                (uintptr_t)address + (index * sizeof(value))) != RS_OK) {
            printf("spisd read failed\n");
            return;
        }
        printf("addr: %x val: %x\n", address + (index * sizeof(value)), value);
    }
}
