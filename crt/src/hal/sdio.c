#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/sdio.h>

#define RS_SDIO_DEFAULT_TIMEOUT      UINT32_C(100000)
#define RS_SDIO_DEFAULT_DATA_TIMEOUT UINT32_C(1000000)
#define RS_SDIO_DEFAULT_BUSY_TIMEOUT UINT32_C(1000000)

#define RS_SD_CMD0                   UINT8_C(0)
#define RS_SD_CMD2                   UINT8_C(2)
#define RS_SD_CMD3                   UINT8_C(3)
#define RS_SD_CMD5                   UINT8_C(5)
#define RS_SD_CMD6                   UINT8_C(6)
#define RS_SD_CMD7                   UINT8_C(7)
#define RS_SD_CMD8                   UINT8_C(8)
#define RS_SD_CMD9                   UINT8_C(9)
#define RS_SD_CMD12                  UINT8_C(12)
#define RS_SD_CMD16                  UINT8_C(16)
#define RS_SD_CMD17                  UINT8_C(17)
#define RS_SD_CMD18                  UINT8_C(18)
#define RS_SD_CMD41                  UINT8_C(41)
#define RS_SD_CMD52                  UINT8_C(52)
#define RS_SD_CMD53                  UINT8_C(53)
#define RS_SD_CMD55                  UINT8_C(55)
#define RS_SD_CMD24                  UINT8_C(24)
#define RS_SD_CMD25                  UINT8_C(25)

#define RS_SDIO_CMD6_HIGH_SPEED_ARG  UINT32_C(0x80FFFFF1)
#define RS_SDIO_CMD6_STATUS_BYTES    UINT32_C(64)

#define RS_SD_R1_ADDRESS_ERROR       UINT32_C(0x80000000)
#define RS_SD_R1_ADDRESS_MISALIGN    UINT32_C(0x40000000)
#define RS_SD_R1_BLOCK_LENGTH_ERROR  UINT32_C(0x20000000)
#define RS_SD_R1_ERASE_SEQUENCE      UINT32_C(0x10000000)
#define RS_SD_R1_ERASE_PARAMETER     UINT32_C(0x08000000)
#define RS_SD_R1_WRITE_PROTECT       UINT32_C(0x04000000)
#define RS_SD_R1_LOCKED              UINT32_C(0x02000000)
#define RS_SD_R1_COM_CRC_ERROR       UINT32_C(0x00800000)
#define RS_SD_R1_ILLEGAL_COMMAND     UINT32_C(0x00400000)
#define RS_SD_R1_CARD_ECC_FAILED     UINT32_C(0x00200000)
#define RS_SD_R1_CC_ERROR            UINT32_C(0x00100000)
#define RS_SD_R1_ERROR               UINT32_C(0x00080000)
#define RS_SD_R1_CSD_OVERWRITE       UINT32_C(0x00008000)
#define RS_SD_R1_WP_ERASE_SKIP       UINT32_C(0x00004000)
#define RS_SD_R1_ERROR_MASK                                                                        \
    (RS_SD_R1_ADDRESS_ERROR | RS_SD_R1_ADDRESS_MISALIGN | RS_SD_R1_BLOCK_LENGTH_ERROR |            \
     RS_SD_R1_ERASE_SEQUENCE | RS_SD_R1_ERASE_PARAMETER | RS_SD_R1_WRITE_PROTECT |                 \
     RS_SD_R1_LOCKED | RS_SD_R1_COM_CRC_ERROR | RS_SD_R1_ILLEGAL_COMMAND |                         \
     RS_SD_R1_CARD_ECC_FAILED | RS_SD_R1_CC_ERROR | RS_SD_R1_ERROR | RS_SD_R1_CSD_OVERWRITE |      \
     RS_SD_R1_WP_ERASE_SKIP)

static bool rs_sdio_instance_valid(rs_sdio_instance_t instance) {
    return (instance == RS_SDIO_INSTANCE_0) || (instance == RS_SDIO_INSTANCE_1);
}

static uintptr_t rs_sdio_base(rs_sdio_instance_t instance) {
    switch (instance) {
    case RS_SDIO_INSTANCE_0:
        return (uintptr_t)RS_SOC_APB4_SDIO0_BASE;
    case RS_SDIO_INSTANCE_1:
        return (uintptr_t)RS_SOC_APB4_SDIO1_BASE;
    default:
        return (uintptr_t)0U;
    }
}

static volatile uint32_t *rs_sdio_reg(rs_sdio_instance_t instance, uint32_t offset) {
    uintptr_t base;

    if (!rs_sdio_instance_valid(instance)) {
        return NULL;
    }
    base = rs_sdio_base(instance);
    if (base == (uintptr_t)0U) {
        return NULL;
    }
    return (volatile uint32_t *)(uintptr_t)(base + (uintptr_t)offset);
}

static bool rs_sdio_response_valid(rs_sdio_response_type_t response) {
    switch (response) {
    case RS_SDIO_RESPONSE_NONE:
    case RS_SDIO_RESPONSE_R1:
    case RS_SDIO_RESPONSE_R1B:
    case RS_SDIO_RESPONSE_R2:
    case RS_SDIO_RESPONSE_R3:
    case RS_SDIO_RESPONSE_R4:
    case RS_SDIO_RESPONSE_R5:
    case RS_SDIO_RESPONSE_R6:
    case RS_SDIO_RESPONSE_R7:
        return true;
    default:
        return false;
    }
}

static bool rs_sdio_busy(rs_sdio_instance_t instance) {
    volatile uint32_t *reg = rs_sdio_reg(instance, RS_SDIO_REG_STATUS);

    return (reg != NULL) && ((*reg & RS_SDIO_STATUS_BUSY) != 0U);
}

static rs_status_t rs_sdio_write(rs_sdio_instance_t instance, uint32_t offset, uint32_t value) {
    volatile uint32_t *reg = rs_sdio_reg(instance, offset);

    if (reg == NULL) {
        return RS_EINVAL;
    }
    *reg = value;
    return RS_OK;
}

static rs_status_t rs_sdio_read(rs_sdio_instance_t instance, uint32_t offset, uint32_t *value) {
    volatile uint32_t *reg = rs_sdio_reg(instance, offset);

    if ((reg == NULL) || (value == NULL)) {
        return RS_EINVAL;
    }
    *value = *reg;
    return RS_OK;
}

static rs_status_t rs_sdio_wait_event(rs_sdio_instance_t instance, uint32_t event_mask,
                                      rs_timeout_t timeout) {
    volatile uint32_t *irq_reg = rs_sdio_reg(instance, RS_SDIO_REG_IRQ_STATUS);
    uint32_t events;

    if ((irq_reg == NULL) || (event_mask == 0U)) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        events = *irq_reg;
        if ((events & (RS_SDIO_IRQ_CMD_ERROR | RS_SDIO_IRQ_DATA_ERROR | RS_SDIO_IRQ_DMA_ERROR |
                       RS_SDIO_IRQ_ABORT)) != 0U) {
            return RS_EIO;
        }
        if ((events & event_mask) != 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_sdio_command_result(rs_sdio_instance_t instance) {
    uint32_t status;

    if (rs_sdio_read(instance, RS_SDIO_REG_CMD_STATUS, &status) != RS_OK) {
        return RS_EINVAL;
    }
    if ((status & RS_SDIO_CMD_STATUS_TIMEOUT) != 0U) {
        return RS_ETIMEOUT;
    }
    if ((status & (RS_SDIO_CMD_STATUS_CRC_ERROR | RS_SDIO_CMD_STATUS_INDEX_ERROR)) != 0U) {
        return RS_EFORMAT;
    }
    return ((status & RS_SDIO_CMD_STATUS_ERROR) != 0U) ? RS_EIO : RS_OK;
}

static rs_status_t rs_sdio_data_result(rs_sdio_instance_t instance) {
    uint32_t status;

    if (rs_sdio_read(instance, RS_SDIO_REG_DATA_START, &status) != RS_OK) {
        return RS_EINVAL;
    }
    if ((status & (RS_SDIO_DATA_STATUS_TIMEOUT | RS_SDIO_DATA_STATUS_BUSY_TIMEOUT)) != 0U) {
        return RS_ETIMEOUT;
    }
    if ((status & RS_SDIO_DATA_STATUS_CRC_ERROR) != 0U) {
        return RS_EFORMAT;
    }
    return ((status & RS_SDIO_DATA_STATUS_ERROR) != 0U) ? RS_EIO : RS_OK;
}

static rs_status_t rs_sdio_dma_result(rs_sdio_instance_t instance) {
    uint32_t status;

    if (rs_sdio_read(instance, RS_SDIO_REG_DMA_STATUS, &status) != RS_OK) {
        return RS_EINVAL;
    }
    return ((status & RS_SDIO_DMA_STATUS_ERROR) != 0U) ? RS_EIO : RS_OK;
}

static rs_status_t rs_sdio_response_payload(const rs_sdio_response_t *response, uint32_t *payload) {
    return rs_sdio_response_field(response, 39U, 8U, payload);
}

static rs_status_t rs_sdio_check_card_status(const rs_sdio_response_t *response,
                                             rs_sdio_response_type_t type) {
    uint32_t payload;

    if ((type != RS_SDIO_RESPONSE_R1) && (type != RS_SDIO_RESPONSE_R1B) &&
        (type != RS_SDIO_RESPONSE_R5) && (type != RS_SDIO_RESPONSE_R6)) {
        return RS_OK;
    }
    if (rs_sdio_response_payload(response, &payload) != RS_OK) {
        return RS_EFORMAT;
    }
    if ((type == RS_SDIO_RESPONSE_R6) && ((payload & UINT32_C(0x0000E000)) != 0U)) {
        return RS_EIO;
    }
    if ((type != RS_SDIO_RESPONSE_R6) && ((payload & RS_SD_R1_ERROR_MASK) != 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

static rs_status_t rs_sdio_clock_enable(rs_sdio_instance_t instance, bool enable) {
    uint32_t value;

    if (rs_sdio_read(instance, RS_SDIO_REG_CLOCK_CTRL, &value) != RS_OK) {
        return RS_EINVAL;
    }
    if (enable) {
        value |= UINT32_C(1) << RS_SDIO_CLOCK_CTRL_ENABLE_BIT;
    } else {
        value &= ~(UINT32_C(1) << RS_SDIO_CLOCK_CTRL_ENABLE_BIT);
    }
    return rs_sdio_write(instance, RS_SDIO_REG_CLOCK_CTRL, value);
}

static rs_status_t rs_sdio_host_irq_enable(rs_sdio_instance_t instance, bool enable) {
    uint32_t value;

    if (rs_sdio_read(instance, RS_SDIO_REG_HOST_CTRL, &value) != RS_OK) {
        return RS_EINVAL;
    }
    if (enable) {
        value |= UINT32_C(1) << RS_SDIO_HOST_CTRL_IRQ_BIT;
    } else {
        value &= ~(UINT32_C(1) << RS_SDIO_HOST_CTRL_IRQ_BIT);
    }
    return rs_sdio_write(instance, RS_SDIO_REG_HOST_CTRL, value);
}

static rs_status_t rs_sdio_send_app_command(rs_sdio_instance_t instance, uint16_t rca,
                                            const rs_sdio_command_t *command,
                                            rs_sdio_response_t *response, rs_timeout_t timeout) {
    rs_sdio_command_t app_command = {
        .index = RS_SD_CMD55,
        .argument = (uint32_t)rca << 16U,
        .response = RS_SDIO_RESPONSE_R1,
        .crc_check = true,
        .index_check = true,
    };
    rs_status_t status;

    status = rs_sdio_command_execute(instance, &app_command, response, timeout);
    if (status != RS_OK) {
        return status;
    }
    return rs_sdio_command_execute(instance, command, response, timeout);
}

rs_status_t rs_sdio_probe(rs_sdio_instance_t instance, uint32_t *ip_id, uint32_t *version,
                          uint32_t *capability) {
    if (!rs_sdio_instance_valid(instance) || (ip_id == NULL) || (version == NULL) ||
        (capability == NULL) || (rs_sdio_read(instance, RS_SDIO_REG_IP_ID, ip_id) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_IP_VERSION, version) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_CAPABILITY, capability) != RS_OK)) {
        return RS_EINVAL;
    }
    if ((*ip_id != RS_SDIO_IP_ID_VALUE) || (*version != RS_SDIO_IP_VERSION_VALUE)) {
        return RS_EFORMAT;
    }
    return RS_OK;
}

rs_status_t rs_sdio_reset(rs_sdio_instance_t instance, rs_timeout_t timeout) {
    volatile uint32_t *status_reg;

    if (!rs_sdio_instance_valid(instance)) {
        return RS_EINVAL;
    }
    if (rs_sdio_write(instance, RS_SDIO_REG_HOST_CTRL,
                      UINT32_C(1) << RS_SDIO_HOST_CTRL_ABORT_BIT) != RS_OK) {
        return RS_EINVAL;
    }
    if ((rs_sdio_write(instance, RS_SDIO_REG_CLOCK_CTRL, 0U) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_HOST_CTRL, 0U) != RS_OK) ||
        (rs_sdio_irq_clear(instance, RS_SDIO_IRQ_ALL) != RS_OK) ||
        (rs_sdio_error_clear(instance, RS_SDIO_ERROR_ALL) != RS_OK)) {
        return RS_EINVAL;
    }
    status_reg = rs_sdio_reg(instance, RS_SDIO_REG_STATUS);
    if (status_reg == NULL) {
        return RS_EINVAL;
    }
    return rs_wait_mask(status_reg, RS_SDIO_STATUS_BUSY, 0U, timeout);
}

rs_status_t rs_sdio_clock_set(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                              uint32_t target_clock_hz, rs_sdio_clock_t *clock) {
    rs_sdio_clock_t calculated;
    uint32_t value;
    uint32_t enabled;

    if (!rs_sdio_instance_valid(instance) || rs_sdio_busy(instance) ||
        (rs_sdio_clock_calculate(source_clock_hz, target_clock_hz, &calculated) != RS_OK)) {
        return RS_EINVAL;
    }
    if (rs_sdio_read(instance, RS_SDIO_REG_CLOCK_CTRL, &value) != RS_OK) {
        return RS_EINVAL;
    }
    enabled = value & RS_SDIO_CLOCK_CTRL_ENABLE;
    value = (uint32_t)calculated.half_period << RS_SDIO_CLOCK_CTRL_HALF_PERIOD_LSB;
    value |= enabled;
    if (rs_sdio_write(instance, RS_SDIO_REG_CLOCK_CTRL, value) != RS_OK) {
        return RS_EINVAL;
    }
    if (clock != NULL) {
        *clock = calculated;
    }
    return RS_OK;
}

rs_status_t rs_sdio_bus_width_set(rs_sdio_instance_t instance, rs_sdio_bus_width_t width) {
    uint32_t value;

    if (!rs_sdio_instance_valid(instance) || rs_sdio_busy(instance)) {
        return RS_EINVAL;
    }
    switch (width) {
    case RS_SDIO_BUS_WIDTH_1:
        value = RS_SDIO_BUS_CTRL_WIDTH_1;
        break;
    case RS_SDIO_BUS_WIDTH_4:
        value = RS_SDIO_BUS_CTRL_WIDTH_4;
        break;
    default:
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_BUS_CTRL, value);
}

rs_status_t rs_sdio_timeouts_set(rs_sdio_instance_t instance, uint32_t command_timeout,
                                 uint32_t data_timeout, uint32_t busy_timeout) {
    if (!rs_sdio_instance_valid(instance) || rs_sdio_busy(instance) || (command_timeout == 0U) ||
        (data_timeout == 0U) || (busy_timeout == 0U)) {
        return RS_EINVAL;
    }
    if ((rs_sdio_write(instance, RS_SDIO_REG_TIMEOUT_CMD, command_timeout) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_TIMEOUT_DATA, data_timeout) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_TIMEOUT_BUSY, busy_timeout) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_enable(rs_sdio_instance_t instance, bool enable) {
    uint32_t value;

    if (!rs_sdio_instance_valid(instance) ||
        (rs_sdio_read(instance, RS_SDIO_REG_HOST_CTRL, &value) != RS_OK)) {
        return RS_EINVAL;
    }
    if (enable) {
        value |= UINT32_C(1) << RS_SDIO_HOST_CTRL_ENABLE_BIT;
    } else {
        value &= ~(UINT32_C(1) << RS_SDIO_HOST_CTRL_ENABLE_BIT);
    }
    return rs_sdio_write(instance, RS_SDIO_REG_HOST_CTRL, value);
}

rs_status_t rs_sdio_configure(rs_sdio_instance_t instance, const rs_sdio_config_t *config) {
    rs_sdio_clock_t clock;
    rs_status_t status;

    if ((config == NULL) || !rs_sdio_instance_valid(instance) || (config->source_clock_hz == 0U) ||
        (config->target_clock_hz == 0U) || (config->timeout_cmd == 0U) ||
        (config->timeout_data == 0U) || (config->timeout_busy == 0U)) {
        return RS_EINVAL;
    }
    status = rs_sdio_reset(instance, RS_TIMEOUT_DEFAULT);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_sdio_clock_set(instance, config->source_clock_hz, config->target_clock_hz, &clock) !=
         RS_OK) ||
        (rs_sdio_bus_width_set(instance, config->bus_width) != RS_OK) ||
        (rs_sdio_timeouts_set(instance, config->timeout_cmd, config->timeout_data,
                              config->timeout_busy) != RS_OK) ||
        (rs_sdio_irq_enable(instance, config->enable_interrupts ? RS_SDIO_IRQ_ALL : 0U) != RS_OK) ||
        (rs_sdio_host_irq_enable(instance, config->enable_interrupts) != RS_OK) ||
        (rs_sdio_clock_enable(instance, true) != RS_OK) ||
        (rs_sdio_enable(instance, true) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_status_get(rs_sdio_instance_t instance, rs_sdio_status_t *status) {
    uint32_t present;

    if (!rs_sdio_instance_valid(instance) || (status == NULL)) {
        return RS_EINVAL;
    }
    if ((rs_sdio_read(instance, RS_SDIO_REG_STATUS, &status->raw_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_CMD_STATUS, &status->command_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DATA_START, &status->data_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_FIFO_STATUS, &status->fifo_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_STATUS, &status->dma_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_ERROR_STATUS, &status->error_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_IRQ_STATUS, &status->irq_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_IRQ_ENABLE, &status->irq_enable) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_CLOCK_ACTUAL, &status->clock_actual_hz) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_CURRENT_DESC, &status->current_descriptor) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_BYTES_DONE, &status->bytes_done) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_ERROR_ADDR, &status->dma_error_address) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_ERROR, &status->dma_error) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_LAST_CMD, &status->last_command) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_PRESENT, &present) != RS_OK)) {
        return RS_EINVAL;
    }
    status->busy = (status->raw_status & RS_SDIO_STATUS_BUSY) != 0U;
    status->present = (present & RS_SDIO_PRESENT_CARD) != 0U;
    return RS_OK;
}

rs_status_t rs_sdio_command_start(rs_sdio_instance_t instance, const rs_sdio_command_t *command) {
    uint32_t cfg;

    if (!rs_sdio_instance_valid(instance) || (command == NULL) || (command->index > 63U) ||
        !rs_sdio_response_valid(command->response) || rs_sdio_busy(instance)) {
        return RS_EINVAL;
    }
    if ((rs_sdio_irq_clear(instance, RS_SDIO_IRQ_CMD_DONE | RS_SDIO_IRQ_CMD_ERROR) != RS_OK) ||
        (rs_sdio_error_clear(instance, RS_SDIO_ERROR_CMD_CRC | RS_SDIO_ERROR_CMD_TIMEOUT |
                                           RS_SDIO_ERROR_CMD) != RS_OK)) {
        return RS_EINVAL;
    }
    cfg = (uint32_t)command->index << RS_SDIO_CMD_CFG_INDEX_LSB;
    cfg |= (uint32_t)command->response << RS_SDIO_CMD_CFG_RESP_LSB;
    if (command->crc_check) {
        cfg |= UINT32_C(1) << RS_SDIO_CMD_CFG_CRC_CHECK_BIT;
    }
    if (command->index_check) {
        cfg |= UINT32_C(1) << RS_SDIO_CMD_CFG_INDEX_CHECK_BIT;
    }
    if ((rs_sdio_write(instance, RS_SDIO_REG_CMD_ARG, command->argument) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_CMD_CFG, cfg) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_CMD_START, 1U) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_response_get(rs_sdio_instance_t instance, rs_sdio_response_t *response) {
    if (!rs_sdio_instance_valid(instance) || (response == NULL) ||
        (rs_sdio_read(instance, RS_SDIO_REG_RESP0, &response->words[0]) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_RESP1, &response->words[1]) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_RESP2, &response->words[2]) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_RESP3, &response->words[3]) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_RESP4, &response->words[4]) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_command_wait(rs_sdio_instance_t instance, rs_sdio_response_t *response,
                                 rs_timeout_t timeout) {
    rs_status_t status;

    if (!rs_sdio_instance_valid(instance) || (response == NULL)) {
        return RS_EINVAL;
    }
    status = rs_sdio_wait_event(instance, RS_SDIO_IRQ_CMD_DONE, timeout);
    if (status != RS_OK) {
        if (status == RS_EIO) {
            rs_status_t result = rs_sdio_command_result(instance);

            return (result == RS_OK) ? RS_EIO : result;
        }
        return status;
    }
    status = rs_sdio_command_result(instance);
    if (status != RS_OK) {
        return status;
    }
    return rs_sdio_response_get(instance, response);
}

rs_status_t rs_sdio_command_execute(rs_sdio_instance_t instance, const rs_sdio_command_t *command,
                                    rs_sdio_response_t *response, rs_timeout_t timeout) {
    rs_status_t status;

    status = rs_sdio_command_start(instance, command);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sdio_command_wait(instance, response, timeout);
    if (status != RS_OK) {
        return status;
    }
    return rs_sdio_check_card_status(response, command->response);
}

rs_status_t rs_sdio_data_configure(rs_sdio_instance_t instance,
                                   const rs_sdio_data_config_t *config) {
    uint32_t value;

    if (!rs_sdio_instance_valid(instance) || (config == NULL) || (config->block_size == 0U) ||
        (config->block_count == 0U) || rs_sdio_busy(instance)) {
        return RS_EINVAL;
    }
    switch (config->direction) {
    case RS_SDIO_DATA_FROM_CARD:
    case RS_SDIO_DATA_TO_CARD:
        break;
    default:
        return RS_EINVAL;
    }
    value = (uint32_t)config->direction << RS_SDIO_DATA_CFG_DIRECTION_BIT;
    if (config->dma) {
        value |= UINT32_C(1) << RS_SDIO_DATA_CFG_DMA_BIT;
    }
    if (config->block_mode) {
        value |= UINT32_C(1) << RS_SDIO_DATA_CFG_BLOCK_BIT;
    }
    if (config->fixed_address) {
        value |= UINT32_C(1) << RS_SDIO_DATA_CFG_FIXED_BIT;
    }
    if ((rs_sdio_write(instance, RS_SDIO_REG_BLOCK_SIZE, config->block_size) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_BLOCK_COUNT, config->block_count) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_DATA_CFG, value) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_data_start(rs_sdio_instance_t instance) {
    if (!rs_sdio_instance_valid(instance) || rs_sdio_busy(instance) ||
        (rs_sdio_irq_clear(instance, RS_SDIO_IRQ_DATA_DONE | RS_SDIO_IRQ_DATA_ERROR) != RS_OK) ||
        (rs_sdio_error_clear(instance, RS_SDIO_ERROR_DATA_CRC | RS_SDIO_ERROR_DATA_TIMEOUT |
                                           RS_SDIO_ERROR_DATA) != RS_OK)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_DATA_START, 1U);
}

static rs_status_t rs_sdio_pio_ready(rs_sdio_instance_t instance, rs_timeout_t timeout) {
    volatile uint32_t *status_reg = rs_sdio_reg(instance, RS_SDIO_REG_STATUS);

    if (status_reg == NULL) {
        return RS_EINVAL;
    }
    return rs_wait_mask(status_reg, RS_SDIO_STATUS_PIO_READY, RS_SDIO_STATUS_PIO_READY, timeout);
}

static rs_status_t rs_sdio_pio_store(rs_sdio_instance_t instance, const uint8_t *bytes,
                                     size_t byte_count) {
    volatile uint32_t *word_reg = rs_sdio_reg(instance, RS_SDIO_REG_PIO_DATA);
    uintptr_t address;
    uint16_t half_word;
    uint32_t word;

    if ((word_reg == NULL) || (bytes == NULL)) {
        return RS_EINVAL;
    }
    address = (uintptr_t)word_reg;
    switch (byte_count) {
    case 1U:
        *(volatile uint8_t *)(uintptr_t)address = bytes[0];
        break;
    case 2U:
        half_word = (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8U);
        *(volatile uint16_t *)(uintptr_t)address = half_word;
        break;
    case RS_SDIO_PIO_WORD_SIZE:
        word = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8U) | ((uint32_t)bytes[2] << 16U) |
               ((uint32_t)bytes[3] << 24U);
        *word_reg = word;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_pio_write(rs_sdio_instance_t instance, const void *buffer, size_t byte_count,
                              rs_timeout_t timeout) {
    const uint8_t *bytes = (const uint8_t *)buffer;
    rs_status_t status;
    size_t offset = 0U;

    if (!rs_sdio_instance_valid(instance) || (buffer == NULL) || (byte_count == 0U)) {
        return RS_EINVAL;
    }
    while (offset < byte_count) {
        size_t remaining = byte_count - offset;
        size_t chunk = (remaining >= (size_t)RS_SDIO_PIO_WORD_SIZE) ? (size_t)RS_SDIO_PIO_WORD_SIZE
                                                                    : remaining;

        if (chunk == 3U) {
            chunk = 2U;
        }
        status = rs_sdio_pio_ready(instance, timeout);
        if (status != RS_OK) {
            return status;
        }
        status = rs_sdio_pio_store(instance, &bytes[offset], chunk);
        if (status != RS_OK) {
            return status;
        }
        offset += chunk;
    }
    return RS_OK;
}

rs_status_t rs_sdio_pio_read(rs_sdio_instance_t instance, void *buffer, size_t byte_count,
                             rs_timeout_t timeout) {
    uint8_t *bytes = (uint8_t *)buffer;
    size_t offset = 0U;

    if (!rs_sdio_instance_valid(instance) || (buffer == NULL) || (byte_count == 0U)) {
        return RS_EINVAL;
    }
    while (offset < byte_count) {
        volatile uint32_t *fifo_reg = rs_sdio_reg(instance, RS_SDIO_REG_FIFO_STATUS);
        uint32_t word;
        rs_status_t status;
        size_t remaining = byte_count - offset;
        size_t chunk = (remaining >= (size_t)RS_SDIO_PIO_WORD_SIZE) ? (size_t)RS_SDIO_PIO_WORD_SIZE
                                                                    : remaining;

        if (fifo_reg == NULL) {
            return RS_EINVAL;
        }
        status = rs_wait_not_value(fifo_reg, 0U, timeout);
        if (status != RS_OK) {
            return status;
        }
        if (rs_sdio_read(instance, RS_SDIO_REG_PIO_DATA, &word) != RS_OK) {
            return RS_EIO;
        }
        for (size_t index = 0U; index < chunk; index++) {
            bytes[offset + index] = (uint8_t)(word >> (index * 8U));
        }
        offset += chunk;
    }
    return RS_OK;
}

rs_status_t rs_sdio_data_wait(rs_sdio_instance_t instance, rs_timeout_t timeout) {
    rs_status_t status;

    if (!rs_sdio_instance_valid(instance)) {
        return RS_EINVAL;
    }
    status = rs_sdio_wait_event(instance, RS_SDIO_IRQ_DATA_DONE, timeout);
    if (status != RS_OK) {
        if (status == RS_EIO) {
            rs_status_t result = rs_sdio_data_result(instance);

            return (result == RS_OK) ? RS_EIO : result;
        }
        return status;
    }
    return rs_sdio_data_result(instance);
}

rs_status_t rs_sdio_dma_setup(rs_sdio_instance_t instance, rs_sdio_descriptor_t *descriptors,
                              uint16_t count, uint32_t total_bytes) {
    uintptr_t address;

    if (!rs_sdio_instance_valid(instance) || (total_bytes == 0U) ||
        (rs_sdio_descriptor_chain_validate(descriptors, count, total_bytes) != RS_OK) ||
        rs_sdio_busy(instance)) {
        return RS_EINVAL;
    }
    if (rs_sdio_descriptor_publish_chain(descriptors, count) != RS_OK) {
        return RS_EINVAL;
    }
    address = (uintptr_t)descriptors;
    rs_sdio_memory_barrier();
    if ((rs_sdio_write(instance, RS_SDIO_REG_DESC_BASE, (uint32_t)address) != RS_OK) ||
        (rs_sdio_write(instance, RS_SDIO_REG_DESC_COUNT, count) != RS_OK) ||
        (rs_sdio_irq_clear(instance, RS_SDIO_IRQ_DMA_DONE | RS_SDIO_IRQ_DMA_ERROR) != RS_OK) ||
        (rs_sdio_error_clear(instance, RS_SDIO_ERROR_DMA) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_dma_start(rs_sdio_instance_t instance) {
    /*
     * DATA_START is the coordinated DMA/data-engine launch.  Keep this
     * compatibility entry point as an alias so software cannot start a DMA
     * stream without its card-side consumer.
     */
    return rs_sdio_data_start(instance);
}

rs_status_t rs_sdio_dma_abort(rs_sdio_instance_t instance) {
    if (!rs_sdio_instance_valid(instance)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_DMA_CTRL, UINT32_C(1) << RS_SDIO_DMA_CTRL_ABORT_BIT);
}

rs_status_t rs_sdio_dma_status_get(rs_sdio_instance_t instance, rs_sdio_dma_status_t *status) {
    uint32_t dma_error;

    if (!rs_sdio_instance_valid(instance) || (status == NULL) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_STATUS, &status->raw_status) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_CURRENT_DESC, &status->current_descriptor) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_BYTES_DONE, &status->bytes_done) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_ERROR_ADDR, &status->error_address) != RS_OK) ||
        (rs_sdio_read(instance, RS_SDIO_REG_DMA_ERROR, &dma_error) != RS_OK)) {
        return RS_EINVAL;
    }
    status->busy = (status->raw_status & RS_SDIO_DMA_STATUS_BUSY) != 0U;
    status->done = (status->raw_status & RS_SDIO_DMA_STATUS_DONE) != 0U;
    status->error = (status->raw_status & RS_SDIO_DMA_STATUS_ERROR) != 0U;
    status->error_code = dma_error & UINT32_C(0xFF);
    return status->error ? RS_EIO : RS_OK;
}

rs_status_t rs_sdio_dma_wait(rs_sdio_instance_t instance, rs_timeout_t timeout) {
    rs_status_t status;

    if (!rs_sdio_instance_valid(instance)) {
        return RS_EINVAL;
    }
    status = rs_sdio_wait_event(instance, RS_SDIO_IRQ_DMA_DONE, timeout);
    if (status != RS_OK) {
        if (status == RS_EIO) {
            rs_status_t result = rs_sdio_dma_result(instance);

            return (result == RS_OK) ? RS_EIO : result;
        }
        return status;
    }
    return rs_sdio_dma_result(instance);
}

rs_status_t rs_sdio_irq_enable(rs_sdio_instance_t instance, uint32_t mask) {
    if (!rs_sdio_instance_valid(instance) || ((mask & ~RS_SDIO_IRQ_ALL) != 0U)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_IRQ_ENABLE, mask);
}

rs_status_t rs_sdio_irq_pending(rs_sdio_instance_t instance, uint32_t *mask) {
    if (!rs_sdio_instance_valid(instance) || (mask == NULL)) {
        return RS_EINVAL;
    }
    return rs_sdio_read(instance, RS_SDIO_REG_IRQ_STATUS, mask);
}

rs_status_t rs_sdio_irq_clear(rs_sdio_instance_t instance, uint32_t mask) {
    if (!rs_sdio_instance_valid(instance) || ((mask & ~RS_SDIO_IRQ_ALL) != 0U)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_IRQ_STATUS, mask);
}

rs_status_t rs_sdio_irq_test(rs_sdio_instance_t instance, uint32_t mask) {
    if (!rs_sdio_instance_valid(instance) || ((mask & ~RS_SDIO_IRQ_ALL) != 0U)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_IRQ_TEST, mask);
}

rs_status_t rs_sdio_error_clear(rs_sdio_instance_t instance, uint32_t mask) {
    if (!rs_sdio_instance_valid(instance) || ((mask & ~RS_SDIO_ERROR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    return rs_sdio_write(instance, RS_SDIO_REG_ERROR_STATUS, mask);
}

rs_status_t rs_sdio_controller_selftest(rs_sdio_instance_t instance) {
    rs_sdio_status_t status;
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability;
    uint32_t pending;
    rs_status_t result;

    result = rs_sdio_probe(instance, &ip_id, &version, &capability);
    if (result != RS_OK) {
        return result;
    }
    if ((capability & (RS_SDIO_CAP_PIO | RS_SDIO_CAP_CRC)) != (RS_SDIO_CAP_PIO | RS_SDIO_CAP_CRC)) {
        return RS_ENOTSUP;
    }
    result = rs_sdio_status_get(instance, &status);
    if (result != RS_OK) {
        return result;
    }
    if (!status.present) {
        return RS_EIO;
    }
    result = rs_sdio_irq_enable(instance, RS_SDIO_IRQ_CMD_DONE);
    if (result == RS_OK) {
        result = rs_sdio_irq_clear(instance, RS_SDIO_IRQ_CMD_DONE);
    }
    if (result == RS_OK) {
        result = rs_sdio_irq_test(instance, RS_SDIO_IRQ_CMD_DONE);
    }
    if (result == RS_OK) {
        result = rs_sdio_irq_pending(instance, &pending);
    }
    if (result != RS_OK) {
        return result;
    }
    if ((pending & RS_SDIO_IRQ_CMD_DONE) == 0U) {
        (void)rs_sdio_irq_clear(instance, RS_SDIO_IRQ_CMD_DONE);
        (void)rs_sdio_irq_enable(instance, 0U);
        return RS_EIO;
    }
    result = rs_sdio_irq_clear(instance, RS_SDIO_IRQ_CMD_DONE);
    if (result == RS_OK) {
        result = rs_sdio_irq_enable(instance, 0U);
    }
    return result;
}

static rs_status_t rs_sd_memory_configure(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                                          uint32_t target_clock_hz, rs_sdio_bus_width_t width) {
    const rs_sdio_config_t config = {
        .source_clock_hz = source_clock_hz,
        .target_clock_hz = target_clock_hz,
        .bus_width = width,
        .timeout_cmd = RS_SDIO_DEFAULT_TIMEOUT,
        .timeout_data = RS_SDIO_DEFAULT_DATA_TIMEOUT,
        .timeout_busy = RS_SDIO_DEFAULT_BUSY_TIMEOUT,
        .enable_interrupts = true,
    };

    return rs_sdio_configure(instance, &config);
}

static rs_status_t rs_sd_memory_command(rs_sdio_instance_t instance, uint8_t index,
                                        uint32_t argument, rs_sdio_response_type_t response_type,
                                        rs_sdio_response_t *response, rs_timeout_t timeout) {
    const rs_sdio_command_t command = {
        .index = index,
        .argument = argument,
        .response = response_type,
        .crc_check = response_type != RS_SDIO_RESPONSE_NONE &&
                     response_type != RS_SDIO_RESPONSE_R3 && response_type != RS_SDIO_RESPONSE_R4,
        .index_check = response_type != RS_SDIO_RESPONSE_NONE &&
                       response_type != RS_SDIO_RESPONSE_R2 &&
                       response_type != RS_SDIO_RESPONSE_R3 && response_type != RS_SDIO_RESPONSE_R4,
    };

    return rs_sdio_command_execute(instance, &command, response, timeout);
}

static rs_status_t rs_sd_memory_acmd(rs_sdio_instance_t instance, uint16_t rca, uint8_t index,
                                     uint32_t argument, rs_sdio_response_type_t response_type,
                                     rs_sdio_response_t *response, rs_timeout_t timeout) {
    const rs_sdio_command_t command = {
        .index = index,
        .argument = argument,
        .response = response_type,
        .crc_check = response_type != RS_SDIO_RESPONSE_R3,
        .index_check = response_type != RS_SDIO_RESPONSE_R3,
    };

    return rs_sdio_send_app_command(instance, rca, &command, response, timeout);
}

static rs_status_t rs_sd_memory_try_bus_width(rs_sdio_instance_t instance, uint16_t rca,
                                              rs_sd_memory_info_t *info, rs_timeout_t timeout) {
    rs_sdio_response_t response;
    rs_status_t status;

    status =
        rs_sd_memory_acmd(instance, rca, RS_SD_CMD6, 2U, RS_SDIO_RESPONSE_R1, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sdio_bus_width_set(instance, RS_SDIO_BUS_WIDTH_4);
    if (status == RS_OK) {
        info->bus_width = RS_SDIO_BUS_WIDTH_4;
    }
    return status;
}

static rs_status_t rs_sd_memory_try_high_speed(rs_sdio_instance_t instance,
                                               uint32_t source_clock_hz, rs_sd_memory_info_t *info,
                                               rs_timeout_t timeout) {
    uint32_t status_words[16];
    rs_sdio_response_t response;
    rs_sdio_data_config_t data_config;
    rs_status_t status;
    rs_sdio_clock_t clock;
    _Alignas(16) rs_sdio_descriptor_t descriptor;

    status = rs_sd_memory_command(instance, RS_SD_CMD6, RS_SDIO_CMD6_HIGH_SPEED_ARG,
                                  RS_SDIO_RESPONSE_R1, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)status_words, RS_SDIO_CMD6_STATUS_BYTES,
                                    (uintptr_t)0U, true, false) != RS_OK) ||
        (rs_sdio_dma_setup(instance, &descriptor, 1U, RS_SDIO_CMD6_STATUS_BYTES) != RS_OK)) {
        return RS_EIO;
    }
    data_config.block_size = (uint16_t)RS_SDIO_CMD6_STATUS_BYTES;
    data_config.block_count = 1U;
    data_config.direction = RS_SDIO_DATA_FROM_CARD;
    data_config.dma = true;
    data_config.block_mode = true;
    data_config.fixed_address = false;
    if ((rs_sdio_data_configure(instance, &data_config) != RS_OK) ||
        (rs_sdio_data_start(instance) != RS_OK) ||
        (rs_sdio_data_wait(instance, timeout) != RS_OK) ||
        (rs_sdio_dma_wait(instance, timeout) != RS_OK)) {
        (void)rs_sdio_dma_abort(instance);
        return RS_EIO;
    }
    if (rs_sdio_clock_set(instance, source_clock_hz,
                          (source_clock_hz >= 100000000U) ? 50000000U : 36000000U,
                          &clock) == RS_OK) {
        info->actual_clock_hz = clock.actual_hz;
        info->high_speed = true;
    } else {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_sd_memory_initialize(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                                    rs_sd_memory_info_t *info, rs_timeout_t timeout) {
    rs_sdio_response_t response;
    rs_sdio_clock_t clock;
    uint32_t payload;
    uint32_t ocr = 0U;
    uint32_t attempts;
    rs_status_t status;
    uint16_t rca;
    bool ocr_high_capacity;

    if (!rs_sdio_instance_valid(instance) || (source_clock_hz == 0U) || (info == NULL) ||
        (timeout == 0U)) {
        return RS_EINVAL;
    }
    for (size_t index = 0U; index < 5U; index++) {
        info->cid[index] = 0U;
        info->csd[index] = 0U;
    }
    info->ocr = 0U;
    info->rca = 0U;
    info->capacity_blocks = 0U;
    info->block_length = 0U;
    info->card_type = RS_SD_MEMORY_SDSC;
    info->bus_width = RS_SDIO_BUS_WIDTH_1;
    info->actual_clock_hz = 0U;
    info->high_capacity = false;
    info->high_speed = false;
    info->bus_width_fallback = false;
    info->speed_fallback = false;

    status = rs_sd_memory_configure(instance, source_clock_hz, 400000U, RS_SDIO_BUS_WIDTH_1);
    if (status != RS_OK) {
        return status;
    }
    status =
        rs_sd_memory_command(instance, RS_SD_CMD0, 0U, RS_SDIO_RESPONSE_NONE, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sd_memory_command(instance, RS_SD_CMD8, UINT32_C(0x1AA), RS_SDIO_RESPONSE_R7,
                                  &response, timeout);
    if ((status != RS_OK) || (rs_sdio_response_payload(&response, &payload) != RS_OK) ||
        ((payload & UINT32_C(0xFFF)) != UINT32_C(0x1AA))) {
        return (status == RS_OK) ? RS_EFORMAT : status;
    }

    attempts = timeout;
    do {
        status = rs_sd_memory_acmd(instance, 0U, RS_SD_CMD41, UINT32_C(0x40FF8000),
                                   RS_SDIO_RESPONSE_R3, &response, timeout);
        if (status != RS_OK) {
            return status;
        }
        if (rs_sdio_response_payload(&response, &ocr) != RS_OK) {
            return RS_EFORMAT;
        }
        if ((ocr & UINT32_C(0x80000000)) != 0U) {
            break;
        }
        attempts--;
    } while (attempts != 0U);
    if ((ocr & UINT32_C(0x80000000)) == 0U) {
        return RS_ETIMEOUT;
    }
    info->ocr = ocr;
    ocr_high_capacity = (ocr & UINT32_C(0x40000000)) != 0U;
    info->high_capacity = ocr_high_capacity;

    status =
        rs_sd_memory_command(instance, RS_SD_CMD2, 0U, RS_SDIO_RESPONSE_R2, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    for (size_t index = 0U; index < 5U; index++) {
        info->cid[index] = response.words[index];
    }
    status =
        rs_sd_memory_command(instance, RS_SD_CMD3, 0U, RS_SDIO_RESPONSE_R6, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_sdio_response_field(&response, 31U, 16U, &payload) != RS_OK) ||
        (payload > UINT16_MAX)) {
        return RS_EFORMAT;
    }
    rca = (uint16_t)payload;
    info->rca = rca;
    status = rs_sd_memory_command(instance, RS_SD_CMD9, (uint32_t)rca << 16U, RS_SDIO_RESPONSE_R2,
                                  &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    for (size_t index = 0U; index < 5U; index++) {
        info->csd[index] = response.words[index];
    }
    status = rs_sd_memory_parse_csd(&response, info);
    if (status != RS_OK) {
        return status;
    }
    if (info->high_capacity != ocr_high_capacity) {
        return RS_EFORMAT;
    }
    status = rs_sd_memory_command(instance, RS_SD_CMD7, (uint32_t)rca << 16U, RS_SDIO_RESPONSE_R1B,
                                  &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    if (info->card_type == RS_SD_MEMORY_SDSC) {
        status = rs_sd_memory_command(instance, RS_SD_CMD16, RS_SD_MEMORY_BLOCK_SIZE,
                                      RS_SDIO_RESPONSE_R1, &response, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    status = rs_sd_memory_try_bus_width(instance, rca, info, timeout);
    if (status != RS_OK) {
        info->bus_width_fallback = true;
        info->bus_width = RS_SDIO_BUS_WIDTH_1;
    }
    status = rs_sdio_clock_set(instance, source_clock_hz, 36000000U, &clock);
    if (status != RS_OK) {
        return status;
    }
    info->actual_clock_hz = clock.actual_hz;
    status = rs_sd_memory_try_high_speed(instance, source_clock_hz, info, timeout);
    if (status != RS_OK) {
        info->speed_fallback = true;
        info->high_speed = false;
    }
    return RS_OK;
}

static rs_status_t rs_sd_memory_transfer(rs_sdio_instance_t instance,
                                         const rs_sd_memory_info_t *info, uint32_t block,
                                         uint32_t count, void *buffer, bool write,
                                         rs_timeout_t timeout) {
    uint32_t argument;
    uint64_t byte_count64;
    uint32_t byte_count;
    uint32_t capability;
    uint32_t ip_id;
    uint32_t version;
    rs_sdio_response_t response;
    rs_sdio_data_config_t data_config;
    rs_status_t status;
    _Alignas(16) rs_sdio_descriptor_t descriptor;

    if ((info == NULL) || (buffer == NULL) || (count == 0U) || (timeout == 0U) ||
        (info->capacity_blocks == 0U) || (block >= info->capacity_blocks) ||
        (count > (info->capacity_blocks - block)) ||
        (rs_sd_memory_address(info->card_type, block, &argument) != RS_OK)) {
        return RS_EINVAL;
    }
    byte_count64 = (uint64_t)count * (uint64_t)RS_SD_MEMORY_BLOCK_SIZE;
    if ((byte_count64 == UINT64_C(0)) || (byte_count64 > (uint64_t)UINT32_MAX) ||
        (byte_count64 > (uint64_t)SIZE_MAX)) {
        return RS_EINVAL;
    }
    byte_count = (uint32_t)byte_count64;
    if (rs_sdio_validate_dma_buffer(buffer, (size_t)byte_count) != RS_OK) {
        return RS_EINVAL;
    }
    if (count > UINT16_MAX) {
        return RS_EINVAL;
    }
    status = rs_sdio_probe(instance, &ip_id, &version, &capability);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sd_memory_command(instance,
                                  (count == 1U) ? (write ? RS_SD_CMD24 : RS_SD_CMD17)
                                                : (write ? RS_SD_CMD25 : RS_SD_CMD18),
                                  argument, RS_SDIO_RESPONSE_R1, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    data_config.block_size = (uint16_t)RS_SD_MEMORY_BLOCK_SIZE;
    data_config.block_count = (uint16_t)count;
    data_config.direction = write ? RS_SDIO_DATA_TO_CARD : RS_SDIO_DATA_FROM_CARD;
    data_config.dma = (capability & RS_SDIO_CAP_SG_DMA) != 0U;
    data_config.block_mode = true;
    data_config.fixed_address = false;
    if (!data_config.dma) {
        if ((byte_count % RS_SDIO_PIO_WORD_SIZE) != 0U) {
            return RS_ENOTSUP;
        }
        status = rs_sdio_data_configure(instance, &data_config);
        if (status == RS_OK) {
            status = rs_sdio_data_start(instance);
        }
        if (status == RS_OK) {
            status = write ? rs_sdio_pio_write(instance, buffer, byte_count, timeout)
                           : rs_sdio_pio_read(instance, buffer, byte_count, timeout);
        }
    } else {
        status = rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)buffer, byte_count,
                                            (uintptr_t)0U, true, false);
        if (status == RS_OK) {
            status = rs_sdio_dma_setup(instance, &descriptor, 1U, byte_count);
        }
        if (status == RS_OK) {
            status = rs_sdio_data_configure(instance, &data_config);
        }
        if (status == RS_OK) {
            status = rs_sdio_data_start(instance);
        }
    }
    if (status == RS_OK) {
        status = rs_sdio_data_wait(instance, timeout);
    }
    if ((status == RS_OK) && data_config.dma) {
        status = rs_sdio_dma_wait(instance, timeout);
    }
    if ((status == RS_OK) && (count > 1U)) {
        status = rs_sd_memory_command(instance, RS_SD_CMD12, 0U, RS_SDIO_RESPONSE_R1B, &response,
                                      timeout);
    }
    return status;
}

rs_status_t rs_sd_memory_read_blocks(rs_sdio_instance_t instance, const rs_sd_memory_info_t *info,
                                     uint32_t block, uint32_t count, void *buffer,
                                     rs_timeout_t timeout) {
    return rs_sd_memory_transfer(instance, info, block, count, buffer, false, timeout);
}

rs_status_t rs_sd_memory_write_blocks(rs_sdio_instance_t instance, const rs_sd_memory_info_t *info,
                                      uint32_t block, uint32_t count, const void *buffer,
                                      rs_timeout_t timeout) {
    return rs_sd_memory_transfer(instance, info, block, count, (void *)buffer, true, timeout);
}

static rs_status_t rs_sdio_function_command(rs_sdio_instance_t instance, uint8_t index,
                                            uint32_t argument, rs_sdio_response_t *response,
                                            rs_timeout_t timeout) {
    const rs_sdio_command_t command = {
        .index = index,
        .argument = argument,
        .response = (index == RS_SD_CMD5) ? RS_SDIO_RESPONSE_R4 : RS_SDIO_RESPONSE_R5,
        .crc_check = index != RS_SD_CMD5,
        .index_check = index != RS_SD_CMD5,
    };

    return rs_sdio_command_execute(instance, &command, response, timeout);
}

rs_status_t rs_sdio_function_cmd52_read(rs_sdio_instance_t instance, uint8_t function,
                                        uint32_t address, uint8_t *data, rs_timeout_t timeout) {
    rs_sdio_cmd52_t command = {
        .function = function,
        .address = address,
        .write = false,
        .raw = false,
        .data = 0U,
    };
    rs_sdio_response_t response;
    uint32_t argument;
    uint32_t payload;
    rs_status_t status;

    if ((data == NULL) || (rs_sdio_cmd52_argument(&command, &argument) != RS_OK)) {
        return RS_EINVAL;
    }
    status = rs_sdio_function_command(instance, RS_SD_CMD52, argument, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    if (rs_sdio_response_payload(&response, &payload) != RS_OK) {
        return RS_EFORMAT;
    }
    *data = (uint8_t)payload;
    return RS_OK;
}

rs_status_t rs_sdio_function_cmd52_write(rs_sdio_instance_t instance, uint8_t function,
                                         uint32_t address, uint8_t data, rs_timeout_t timeout) {
    const rs_sdio_cmd52_t command = {
        .function = function,
        .address = address,
        .write = true,
        .raw = false,
        .data = data,
    };
    rs_sdio_response_t response;
    uint32_t argument;
    rs_status_t status;

    if (rs_sdio_cmd52_argument(&command, &argument) != RS_OK) {
        return RS_EINVAL;
    }
    status = rs_sdio_function_command(instance, RS_SD_CMD52, argument, &response, timeout);
    return status;
}

rs_status_t rs_sdio_function_initialize(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                                        rs_sdio_function_info_t *info, rs_timeout_t timeout) {
    rs_sdio_response_t response;
    rs_sdio_clock_t clock;
    uint32_t payload;
    uint32_t attempts;
    uint32_t cmd5_argument = 0U;
    uint8_t value;
    bool high_speed_enabled = false;
    rs_status_t status;

    if (!rs_sdio_instance_valid(instance) || (source_clock_hz == 0U) || (info == NULL) ||
        (timeout == 0U)) {
        return RS_EINVAL;
    }
    *info = (rs_sdio_function_info_t){0};
    status = rs_sd_memory_configure(instance, source_clock_hz, 400000U, RS_SDIO_BUS_WIDTH_1);
    if (status != RS_OK) {
        return status;
    }
    attempts = timeout;
    do {
        status = rs_sdio_function_command(instance, RS_SD_CMD5, cmd5_argument, &response, timeout);
        if (status != RS_OK) {
            return status;
        }
        if (rs_sdio_response_payload(&response, &payload) != RS_OK) {
            return RS_EFORMAT;
        }
        cmd5_argument = payload & UINT32_C(0x00FFFFFF);
        attempts--;
    } while (((payload & UINT32_C(0x80000000)) == 0U) && (attempts != 0U));
    if ((payload & UINT32_C(0x80000000)) == 0U) {
        return RS_ETIMEOUT;
    }
    info->ocr = payload;
    info->function_count = (uint8_t)((payload >> 28U) & 7U);
    if (info->function_count == 0U) {
        return RS_EFORMAT;
    }
    if ((payload & UINT32_C(0x08000000)) != 0U) {
        return RS_ENOTSUP;
    }
    status = rs_sdio_command_execute(instance,
                                     &(const rs_sdio_command_t){
                                         .index = RS_SD_CMD3,
                                         .argument = 0U,
                                         .response = RS_SDIO_RESPONSE_R6,
                                         .crc_check = true,
                                         .index_check = true,
                                     },
                                     &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_sdio_response_field(&response, 31U, 16U, &payload) != RS_OK) ||
        (payload > UINT16_MAX)) {
        return RS_EFORMAT;
    }
    info->rca = (uint16_t)payload;
    status = rs_sd_memory_command(instance, RS_SD_CMD7, (uint32_t)info->rca << 16U,
                                  RS_SDIO_RESPONSE_R1B, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sdio_function_cmd52_read(instance, 0U, 0x00U, &value, timeout);
    if (status != RS_OK) {
        return status;
    }
    if (value == 0U) {
        return RS_EFORMAT;
    }
    info->cccr_version = value;
    status = rs_sdio_function_cmd52_read(instance, 0U, 0x02U, &info->io_enable, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sdio_function_cmd52_read(instance, 0U, 0x03U, &info->io_ready, timeout);
    if (status != RS_OK) {
        return status;
    }
    status =
        rs_sdio_function_cmd52_read(instance, 0U, 0x07U, &info->bus_interface_control, timeout);
    if (status != RS_OK) {
        return status;
    }
    for (uint8_t function = 1U; function <= info->function_count; function++) {
        uint32_t fbr_address = (uint32_t)function * UINT32_C(0x100);
        uint8_t block_size_low;
        uint8_t block_size_high;

        status = rs_sdio_function_cmd52_read(instance, 0U, fbr_address,
                                             &info->function_code[function], timeout);
        if (status != RS_OK) {
            return status;
        }
        status = rs_sdio_function_cmd52_read(instance, 0U, fbr_address + 0x10U, &block_size_low,
                                             timeout);
        if (status != RS_OK) {
            return status;
        }
        status = rs_sdio_function_cmd52_read(instance, 0U, fbr_address + 0x11U, &block_size_high,
                                             timeout);
        if (status != RS_OK) {
            return status;
        }
        info->function_block_size[function] =
            (uint16_t)block_size_low | ((uint16_t)block_size_high << 8U);
    }
    status = rs_sdio_function_cmd52_read(instance, 0U, 0x13U, &value, timeout);
    if ((status == RS_OK) && ((value & UINT8_C(0x01)) != 0U)) {
        status = rs_sdio_function_cmd52_write(instance, 0U, 0x13U, (uint8_t)(value | UINT8_C(0x02)),
                                              timeout);
        if (status == RS_OK) {
            status = rs_sdio_function_cmd52_read(instance, 0U, 0x13U, &value, timeout);
        }
        if ((status == RS_OK) && ((value & UINT8_C(0x02)) != 0U)) {
            high_speed_enabled = true;
        } else {
            info->high_speed_fallback = true;
        }
    } else {
        info->high_speed_fallback = true;
    }
    status = rs_sdio_clock_set(instance, source_clock_hz,
                               high_speed_enabled ? 24000000U : 25000000U, &clock);
    if (status != RS_OK) {
        return status;
    }
    info->high_speed = high_speed_enabled;
    return RS_OK;
}

rs_status_t rs_sdio_function_enable(rs_sdio_instance_t instance, rs_sdio_function_info_t *info,
                                    uint8_t function, rs_timeout_t timeout) {
    uint8_t enable;
    uint8_t ready;
    uint32_t attempts;
    rs_status_t status;

    if ((info == NULL) || (function == 0U) || (function > info->function_count) ||
        (function > 7U) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    status = rs_sdio_function_cmd52_read(instance, 0U, 0x02U, &enable, timeout);
    if (status != RS_OK) {
        return status;
    }
    enable |= (uint8_t)(1U << function);
    status = rs_sdio_function_cmd52_write(instance, 0U, 0x02U, enable, timeout);
    if (status != RS_OK) {
        return status;
    }
    attempts = timeout;
    do {
        status = rs_sdio_function_cmd52_read(instance, 0U, 0x03U, &ready, timeout);
        if (status != RS_OK) {
            return status;
        }
        attempts--;
    } while (((ready & (uint8_t)(1U << function)) == 0U) && (attempts != 0U));
    if ((ready & (uint8_t)(1U << function)) == 0U) {
        return RS_ETIMEOUT;
    }
    info->io_enable = enable;
    info->io_ready = ready;
    return RS_OK;
}

rs_status_t rs_sdio_function_cmd53_transfer(rs_sdio_instance_t instance, uint8_t function,
                                            uint32_t address, void *buffer, size_t byte_count,
                                            bool write, bool block_mode, bool fixed_address,
                                            uint16_t block_size, rs_timeout_t timeout) {
    rs_sdio_cmd53_t command;
    rs_sdio_data_config_t data_config;
    rs_sdio_response_t response;
    uint32_t argument;
    uint32_t blocks;
    uint32_t capability;
    uint32_t ip_id;
    uint32_t version;
    rs_status_t status;
    _Alignas(16) rs_sdio_descriptor_t descriptor;

    if ((buffer == NULL) || (byte_count == 0U) || (timeout == 0U) || (block_size == 0U) ||
        (rs_sdio_validate_dma_buffer(buffer, byte_count) != RS_OK)) {
        return RS_EINVAL;
    }
    if (block_mode) {
        if ((byte_count % (size_t)block_size) != 0U) {
            return RS_EINVAL;
        }
        blocks = (uint32_t)(byte_count / (size_t)block_size);
        if ((blocks == 0U) || (blocks > UINT16_C(512))) {
            return RS_EINVAL;
        }
        command.count = (uint16_t)blocks;
    } else {
        if (byte_count > (size_t)UINT16_C(512)) {
            return RS_EINVAL;
        }
        blocks = 1U;
        command.count = (uint16_t)byte_count;
    }
    command.function = function;
    command.address = address;
    command.write = write;
    command.block_mode = block_mode;
    command.fixed_address = fixed_address;
    if (rs_sdio_cmd53_argument(&command, &argument) != RS_OK) {
        return RS_EINVAL;
    }
    status = rs_sdio_probe(instance, &ip_id, &version, &capability);
    if (status != RS_OK) {
        return status;
    }
    status = rs_sdio_function_command(instance, RS_SD_CMD53, argument, &response, timeout);
    if (status != RS_OK) {
        return status;
    }
    data_config.block_size = block_mode ? block_size : (uint16_t)byte_count;
    data_config.block_count = (uint16_t)blocks;
    data_config.direction = write ? RS_SDIO_DATA_TO_CARD : RS_SDIO_DATA_FROM_CARD;
    data_config.dma = (capability & RS_SDIO_CAP_SG_DMA) != 0U;
    data_config.block_mode = block_mode;
    data_config.fixed_address = fixed_address;
    if (!data_config.dma) {
        if ((byte_count % RS_SDIO_PIO_WORD_SIZE) != 0U) {
            return RS_ENOTSUP;
        }
        status = rs_sdio_data_configure(instance, &data_config);
        if (status == RS_OK) {
            status = rs_sdio_data_start(instance);
        }
        if (status == RS_OK) {
            status = write ? rs_sdio_pio_write(instance, buffer, byte_count, timeout)
                           : rs_sdio_pio_read(instance, buffer, byte_count, timeout);
        }
    } else {
        status = rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)buffer, byte_count,
                                            (uintptr_t)0U, true, false);
        if (status == RS_OK) {
            status = rs_sdio_dma_setup(instance, &descriptor, 1U, (uint32_t)byte_count);
        }
        if (status == RS_OK) {
            status = rs_sdio_data_configure(instance, &data_config);
        }
        if (status == RS_OK) {
            status = rs_sdio_data_start(instance);
        }
    }
    if (status == RS_OK) {
        status = rs_sdio_data_wait(instance, timeout);
    }
    if ((status == RS_OK) && data_config.dma) {
        status = rs_sdio_dma_wait(instance, timeout);
    }
    return status;
}

rs_status_t rs_sdio_function_irq_enable(rs_sdio_instance_t instance, bool enable) {
    uint32_t mask;

    if (!rs_sdio_instance_valid(instance) ||
        (rs_sdio_read(instance, RS_SDIO_REG_IRQ_ENABLE, &mask) != RS_OK)) {
        return RS_EINVAL;
    }
    if (enable) {
        mask |= RS_SDIO_IRQ_DAT1;
    } else {
        mask &= ~RS_SDIO_IRQ_DAT1;
    }
    if ((rs_sdio_irq_enable(instance, mask) != RS_OK) ||
        (rs_sdio_host_irq_enable(instance, mask != 0U) != RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sdio_function_irq_pending(rs_sdio_instance_t instance, bool *pending) {
    uint32_t mask;

    if ((pending == NULL) || (rs_sdio_irq_pending(instance, &mask) != RS_OK)) {
        return RS_EINVAL;
    }
    *pending = (mask & RS_SDIO_IRQ_DAT1) != 0U;
    return RS_OK;
}

rs_status_t rs_sdio_function_irq_ack(rs_sdio_instance_t instance) {
    return rs_sdio_irq_clear(instance, RS_SDIO_IRQ_DAT1);
}
