#include <limits.h>
#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/i2c.h>

#define RS_I2C_CTRL_OFFSET             UINT32_C(0x00)
#define RS_I2C_SCL_TIMING_OFFSET       UINT32_C(0x04)
#define RS_I2C_START_TIMING_OFFSET     UINT32_C(0x08)
#define RS_I2C_DATA_TIMING_OFFSET      UINT32_C(0x0C)
#define RS_I2C_STOP_TIMING_OFFSET      UINT32_C(0x10)
#define RS_I2C_FILTER_OFFSET           UINT32_C(0x14)
#define RS_I2C_STRETCH_TIMEOUT_OFFSET  UINT32_C(0x18)
#define RS_I2C_BUS_IDLE_TIMEOUT_OFFSET UINT32_C(0x1C)
#define RS_I2C_COMMAND_TIMEOUT_OFFSET  UINT32_C(0x20)
#define RS_I2C_TARGET_ADDR_OFFSET      UINT32_C(0x24)
#define RS_I2C_DATA_CMD_OFFSET         UINT32_C(0x28)
#define RS_I2C_RXDATA_OFFSET           UINT32_C(0x2C)
#define RS_I2C_STATUS_OFFSET           UINT32_C(0x30)
#define RS_I2C_FIFO_LEVEL_OFFSET       UINT32_C(0x34)
#define RS_I2C_COMMAND_OFFSET          UINT32_C(0x38)
#define RS_I2C_CMD_WATERMARK_OFFSET    UINT32_C(0x3C)
#define RS_I2C_RX_WATERMARK_OFFSET     UINT32_C(0x40)
#define RS_I2C_ERROR_STATUS_OFFSET     UINT32_C(0x44)
#define RS_I2C_INTR_STATE_OFFSET       UINT32_C(0x48)
#define RS_I2C_INTR_ENABLE_OFFSET      UINT32_C(0x4C)
#define RS_I2C_INTR_TEST_OFFSET        UINT32_C(0x54)

#define RS_I2C_REG(bus, offset)        RS_SOC_REG32(rs_i2c_base((bus)), (offset))

#define RS_I2C_CTRL_ENABLE             UINT32_C(0x001)
#define RS_I2C_STATUS_ENABLE           UINT32_C(0x001)
#define RS_I2C_STATUS_BUSY             UINT32_C(0x002)
#define RS_I2C_STATUS_CMD_FULL         UINT32_C(0x010)
#define RS_I2C_COMMAND_ABORT           UINT32_C(0x001)
#define RS_I2C_COMMAND_RECOVER         UINT32_C(0x002)
#define RS_I2C_COMMAND_FLUSH_ALL       UINT32_C(0x00C)
#define RS_I2C_DATA_CMD_READ           UINT32_C(0x100)
#define RS_I2C_DATA_CMD_RESTART        UINT32_C(0x200)
#define RS_I2C_DATA_CMD_STOP           UINT32_C(0x400)
#define RS_I2C_DATA_CMD_NACK_LAST      UINT32_C(0x800)
#define RS_I2C_TARGET_TEN_BIT          UINT32_C(0x400)
#define RS_I2C_FIFO_COMMAND_MASK       UINT32_C(0x0FF)
#define RS_I2C_FIFO_RX_SHIFT           16U
#define RS_I2C_FIFO_RX_MASK            UINT32_C(0x0FF)
#define RS_I2C_FIFO_DEPTH              UINT32_C(16)
#define RS_I2C_TIMEOUT_MAX_CYCLES      UINT32_C(0xFFFFFF)

static uintptr_t rs_i2c_base(rs_i2c_bus_t bus) {
    return (bus == RS_I2C_BUS_0) ? (uintptr_t)RS_SOC_RIBP_I2C0_BASE
                                 : (uintptr_t)RS_SOC_RIBP_I2C1_BASE;
}

static bool rs_i2c_bus_valid(rs_i2c_bus_t bus) {
    return (bus == RS_I2C_BUS_0) || (bus == RS_I2C_BUS_1);
}

static bool rs_i2c_address_valid(uint16_t address, bool ten_bit_address) {
    return ten_bit_address ? (address <= UINT16_C(0x03FF)) : (address <= UINT16_C(0x007F));
}

static rs_status_t rs_i2c_timeout_cycles(uint32_t source_clock_hz, uint32_t timeout_us,
                                         uint32_t *cycles) {
    uint64_t value;

    if (cycles == NULL) {
        return RS_EINVAL;
    }
    if (timeout_us == 0U) {
        *cycles = 0U;
        return RS_OK;
    }
    value =
        (((uint64_t)source_clock_hz * (uint64_t)timeout_us) + UINT64_C(999999)) / UINT64_C(1000000);
    if ((value == 0U) || (value > RS_I2C_TIMEOUT_MAX_CYCLES)) {
        return RS_EINVAL;
    }
    *cycles = (uint32_t)value;
    return RS_OK;
}

static rs_status_t rs_i2c_gpio_configure(rs_i2c_bus_t bus) {
    const rs_gpio_config_t pin_config = {
        .mode = (bus == RS_I2C_BUS_0) ? RS_GPIO_MODE_ALT0 : RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = true,
        .open_drain = true,
        .input_cmos = false,
        .filter_enable = false,
        .interrupt_enable = false,
    };
    const uint32_t scl_pin = (bus == RS_I2C_BUS_0) ? UINT32_C(7) : UINT32_C(3);
    const uint32_t sda_pin = (bus == RS_I2C_BUS_0) ? UINT32_C(8) : UINT32_C(4);
    rs_status_t status = rs_gpio_configure(scl_pin, &pin_config);

    if (status == RS_OK) {
        status = rs_gpio_configure(sda_pin, &pin_config);
    }
    return status;
}

static rs_status_t rs_i2c_wait_idle(rs_i2c_bus_t bus, rs_timeout_t timeout) {
    while ((RS_I2C_REG(bus, RS_I2C_STATUS_OFFSET) & RS_I2C_STATUS_BUSY) != 0U) {
        if (timeout == 0U) {
            return RS_ETIMEOUT;
        }
        timeout--;
    }
    return RS_OK;
}

static rs_status_t rs_i2c_prepare(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address,
                                  rs_timeout_t timeout) {
    rs_status_t status;

    if (!rs_i2c_bus_valid(bus) || !rs_i2c_address_valid(address, ten_bit_address)) {
        return RS_EINVAL;
    }
    if ((RS_I2C_REG(bus, RS_I2C_STATUS_OFFSET) & RS_I2C_STATUS_ENABLE) == 0U) {
        return RS_EIO;
    }
    status = rs_i2c_wait_idle(bus, timeout);
    if (status != RS_OK) {
        return status;
    }
    RS_I2C_REG(bus, RS_I2C_COMMAND_OFFSET) = RS_I2C_COMMAND_FLUSH_ALL;
    RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET) = RS_I2C_ERROR_ALL;
    RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_ALL;
    RS_I2C_REG(bus, RS_I2C_TARGET_ADDR_OFFSET) =
        (uint32_t)address | (ten_bit_address ? RS_I2C_TARGET_TEN_BIT : 0U);
    return RS_OK;
}

static uint32_t rs_i2c_command(const uint8_t *prefix, size_t prefix_length, const uint8_t *tx_data,
                               size_t tx_length, size_t rx_length, size_t index) {
    const size_t write_length = prefix_length + tx_length;
    const size_t total_length = write_length + rx_length;
    uint32_t command;

    if (index < write_length) {
        command = (index < prefix_length) ? (uint32_t)prefix[index]
                                          : (uint32_t)tx_data[index - prefix_length];
    } else {
        command = RS_I2C_DATA_CMD_READ;
        if ((index == write_length) && (write_length != 0U)) {
            command |= RS_I2C_DATA_CMD_RESTART;
        }
    }
    if ((index + 1U) == total_length) {
        command |= RS_I2C_DATA_CMD_STOP;
        if (index >= write_length) {
            command |= RS_I2C_DATA_CMD_NACK_LAST;
        }
    }
    return command;
}

static rs_status_t rs_i2c_execute(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address,
                                  const uint8_t *prefix, size_t prefix_length,
                                  const uint8_t *tx_data, size_t tx_length, uint8_t *rx_data,
                                  size_t rx_length, rs_timeout_t timeout) {
    size_t command_index = 0U;
    size_t rx_index = 0U;
    size_t total_length;
    rs_status_t status;

    if ((prefix_length > (SIZE_MAX - tx_length)) ||
        ((prefix_length + tx_length) > (SIZE_MAX - rx_length))) {
        return RS_EINVAL;
    }
    total_length = prefix_length + tx_length + rx_length;
    if ((total_length == 0U) || ((prefix_length != 0U) && (prefix == NULL)) ||
        ((tx_length != 0U) && (tx_data == NULL)) || ((rx_length != 0U) && (rx_data == NULL))) {
        return RS_EINVAL;
    }
    status = rs_i2c_prepare(bus, address, ten_bit_address, timeout);
    if (status != RS_OK) {
        return status;
    }

    while (timeout != 0U) {
        uint32_t levels;
        uint32_t errors;

        errors = RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET);
        if (errors != 0U) {
            return RS_EIO;
        }
        levels = RS_I2C_REG(bus, RS_I2C_FIFO_LEVEL_OFFSET);
        if ((command_index < total_length) &&
            ((levels & RS_I2C_FIFO_COMMAND_MASK) < RS_I2C_FIFO_DEPTH)) {
            RS_I2C_REG(bus, RS_I2C_DATA_CMD_OFFSET) =
                rs_i2c_command(prefix, prefix_length, tx_data, tx_length, rx_length, command_index);
            command_index++;
        }
        if ((rx_index < rx_length) &&
            (((levels >> RS_I2C_FIFO_RX_SHIFT) & RS_I2C_FIFO_RX_MASK) != 0U)) {
            rx_data[rx_index] = (uint8_t)RS_I2C_REG(bus, RS_I2C_RXDATA_OFFSET);
            rx_index++;
        }
        if (((RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) & RS_I2C_INTR_DONE) != 0U) &&
            (command_index == total_length) && (rx_index == rx_length)) {
            RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_DONE;
            return RS_OK;
        }
        timeout--;
    }
    (void)rs_i2c_abort(bus, RS_TIMEOUT_DEFAULT);
    return RS_ETIMEOUT;
}

static rs_status_t rs_i2c_wait_done(rs_i2c_bus_t bus, rs_timeout_t timeout) {
    while (timeout != 0U) {
        if (RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET) != 0U) {
            return RS_EIO;
        }
        if ((RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) & RS_I2C_INTR_DONE) != 0U) {
            RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_DONE;
            return RS_OK;
        }
        timeout--;
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_i2c_configure(rs_i2c_bus_t bus, const rs_i2c_config_t *config,
                             rs_timeout_t timeout) {
    rs_i2c_timing_t timing;
    uint32_t stretch_timeout;
    uint32_t bus_idle_timeout;
    uint32_t command_timeout;
    rs_status_t status;

    if (!rs_i2c_bus_valid(bus) || (config == NULL) || (config->scl_filter_cycles > 15U) ||
        (config->sda_filter_cycles > 15U) || (config->command_watermark >= 16U) ||
        (config->rx_watermark == 0U) || (config->rx_watermark > 16U)) {
        return RS_EINVAL;
    }
    status = rs_i2c_timing_calculate(config->source_clock_hz, config->bus_hz, &timing);
    if (status == RS_OK) {
        status = rs_i2c_timeout_cycles(config->source_clock_hz, config->stretch_timeout_us,
                                       &stretch_timeout);
    }
    if (status == RS_OK) {
        status = rs_i2c_timeout_cycles(config->source_clock_hz, config->bus_idle_timeout_us,
                                       &bus_idle_timeout);
    }
    if (status == RS_OK) {
        status = rs_i2c_timeout_cycles(config->source_clock_hz, config->command_timeout_us,
                                       &command_timeout);
    }
    if (status != RS_OK) {
        return status;
    }
    status = rs_i2c_wait_idle(bus, timeout);
    if (status != RS_OK) {
        return status;
    }
    RS_I2C_REG(bus, RS_I2C_CTRL_OFFSET) = 0U;
    status = rs_i2c_gpio_configure(bus);
    if (status != RS_OK) {
        return status;
    }
    RS_I2C_REG(bus, RS_I2C_COMMAND_OFFSET) = RS_I2C_COMMAND_FLUSH_ALL;
    RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET) = RS_I2C_ERROR_ALL;
    RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_ALL;
    RS_I2C_REG(bus, RS_I2C_SCL_TIMING_OFFSET) =
        ((uint32_t)timing.scl_high_cycles << 16U) | (uint32_t)timing.scl_low_cycles;
    RS_I2C_REG(bus, RS_I2C_START_TIMING_OFFSET) =
        ((uint32_t)timing.start_setup_cycles << 16U) | (uint32_t)timing.start_hold_cycles;
    RS_I2C_REG(bus, RS_I2C_DATA_TIMING_OFFSET) =
        ((uint32_t)timing.data_setup_cycles << 16U) | (uint32_t)timing.data_hold_cycles;
    RS_I2C_REG(bus, RS_I2C_STOP_TIMING_OFFSET) =
        ((uint32_t)timing.bus_free_cycles << 16U) | (uint32_t)timing.stop_setup_cycles;
    RS_I2C_REG(bus, RS_I2C_FILTER_OFFSET) =
        ((uint32_t)config->sda_filter_cycles << 8U) | (uint32_t)config->scl_filter_cycles;
    RS_I2C_REG(bus, RS_I2C_STRETCH_TIMEOUT_OFFSET) = stretch_timeout;
    RS_I2C_REG(bus, RS_I2C_BUS_IDLE_TIMEOUT_OFFSET) = bus_idle_timeout;
    RS_I2C_REG(bus, RS_I2C_COMMAND_TIMEOUT_OFFSET) = command_timeout;
    RS_I2C_REG(bus, RS_I2C_CMD_WATERMARK_OFFSET) = config->command_watermark;
    RS_I2C_REG(bus, RS_I2C_RX_WATERMARK_OFFSET) = config->rx_watermark;
    RS_I2C_REG(bus, RS_I2C_CTRL_OFFSET) = RS_I2C_CTRL_ENABLE;
    return ((RS_I2C_REG(bus, RS_I2C_STATUS_OFFSET) & RS_I2C_STATUS_ENABLE) != 0U) ? RS_OK : RS_EIO;
}

rs_status_t rs_i2c_init(rs_i2c_bus_t bus, uint32_t source_clock_hz, uint32_t bus_hz) {
    const rs_i2c_config_t config = {
        .source_clock_hz = source_clock_hz,
        .bus_hz = bus_hz,
        .stretch_timeout_us = UINT32_C(25000),
        .bus_idle_timeout_us = UINT32_C(25000),
        .command_timeout_us = UINT32_C(100000),
        .scl_filter_cycles = UINT8_C(2),
        .sda_filter_cycles = UINT8_C(2),
        .command_watermark = UINT8_C(4),
        .rx_watermark = UINT8_C(8),
    };
    return rs_i2c_configure(bus, &config, RS_TIMEOUT_DEFAULT);
}

rs_status_t rs_i2c_transfer(rs_i2c_bus_t bus, const rs_i2c_transfer_t *transfer,
                            rs_timeout_t timeout) {
    if (transfer == NULL) {
        return RS_EINVAL;
    }
    return rs_i2c_execute(bus, transfer->address, transfer->ten_bit_address, NULL, 0U,
                          transfer->tx_data, transfer->tx_length, transfer->rx_data,
                          transfer->rx_length, timeout);
}

static rs_status_t rs_i2c_register_prefix(const rs_i2c_register_access_t *access, uint8_t prefix[2],
                                          size_t *prefix_length) {
    if ((access == NULL) || (prefix == NULL) || (prefix_length == NULL)) {
        return RS_EINVAL;
    }

    switch (access->register_address_width) {
    case RS_I2C_REGISTER_ADDRESS_8_BIT:
        if (access->register_address > UINT8_MAX) {
            return RS_EINVAL;
        }
        prefix[0] = (uint8_t)access->register_address;
        *prefix_length = 1U;
        break;
    case RS_I2C_REGISTER_ADDRESS_16_BIT:
        prefix[0] = (uint8_t)(access->register_address >> 8U);
        prefix[1] = (uint8_t)access->register_address;
        *prefix_length = 2U;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_i2c_register_write(rs_i2c_bus_t bus, const rs_i2c_register_access_t *access,
                                  const uint8_t *data, size_t length, rs_timeout_t timeout) {
    uint8_t prefix[2];
    size_t prefix_length;
    rs_status_t status;

    if ((data == NULL) || (length == 0U)) {
        return RS_EINVAL;
    }
    status = rs_i2c_register_prefix(access, prefix, &prefix_length);
    if (status != RS_OK) {
        return status;
    }
    return rs_i2c_execute(bus, access->address, access->ten_bit_address, prefix, prefix_length,
                          data, length, NULL, 0U, timeout);
}

rs_status_t rs_i2c_register_read(rs_i2c_bus_t bus, const rs_i2c_register_access_t *access,
                                 uint8_t *data, size_t length, rs_timeout_t timeout) {
    uint8_t prefix[2];
    size_t prefix_length;
    rs_status_t status;

    if ((data == NULL) || (length == 0U)) {
        return RS_EINVAL;
    }
    status = rs_i2c_register_prefix(access, prefix, &prefix_length);
    if (status != RS_OK) {
        return status;
    }
    return rs_i2c_execute(bus, access->address, access->ten_bit_address, prefix, prefix_length,
                          NULL, 0U, data, length, timeout);
}

rs_status_t rs_i2c_abort(rs_i2c_bus_t bus, rs_timeout_t timeout) {
    if (!rs_i2c_bus_valid(bus)) {
        return RS_EINVAL;
    }
    if ((RS_I2C_REG(bus, RS_I2C_STATUS_OFFSET) & RS_I2C_STATUS_BUSY) == 0U) {
        return RS_OK;
    }
    RS_I2C_REG(bus, RS_I2C_COMMAND_OFFSET) = RS_I2C_COMMAND_ABORT;
    return rs_i2c_wait_idle(bus, timeout);
}

rs_status_t rs_i2c_recover(rs_i2c_bus_t bus, rs_timeout_t timeout) {
    rs_status_t status;

    if (!rs_i2c_bus_valid(bus)) {
        return RS_EINVAL;
    }
    status = rs_i2c_wait_idle(bus, timeout);
    if (status != RS_OK) {
        return status;
    }
    RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET) = RS_I2C_ERROR_ALL;
    RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_ALL;
    RS_I2C_REG(bus, RS_I2C_COMMAND_OFFSET) = RS_I2C_COMMAND_RECOVER;
    while (timeout != 0U) {
        if (RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET) != 0U) {
            return RS_EIO;
        }
        if ((RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) & RS_I2C_INTR_RECOVERY_DONE) != 0U) {
            RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = RS_I2C_INTR_RECOVERY_DONE;
            return RS_OK;
        }
        timeout--;
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_i2c_get_status(rs_i2c_bus_t bus, rs_i2c_status_t *status) {
    uint32_t levels;

    if (!rs_i2c_bus_valid(bus) || (status == NULL)) {
        return RS_EINVAL;
    }
    levels = RS_I2C_REG(bus, RS_I2C_FIFO_LEVEL_OFFSET);
    status->flags = RS_I2C_REG(bus, RS_I2C_STATUS_OFFSET);
    status->command_level = levels & RS_I2C_FIFO_COMMAND_MASK;
    status->rx_level = (levels >> RS_I2C_FIFO_RX_SHIFT) & RS_I2C_FIFO_RX_MASK;
    status->errors = RS_I2C_REG(bus, RS_I2C_ERROR_STATUS_OFFSET);
    status->interrupt_state = RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET);
    return RS_OK;
}

rs_status_t rs_i2c_irq_enable(rs_i2c_bus_t bus, uint32_t mask) {
    if (!rs_i2c_bus_valid(bus) || ((mask & ~RS_I2C_INTR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    RS_I2C_REG(bus, RS_I2C_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_i2c_irq_ack(rs_i2c_bus_t bus, uint32_t mask) {
    if (!rs_i2c_bus_valid(bus) || (mask == 0U) || ((mask & ~RS_I2C_INTR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    RS_I2C_REG(bus, RS_I2C_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_i2c_irq_test(rs_i2c_bus_t bus, uint32_t mask) {
    if (!rs_i2c_bus_valid(bus) || (mask == 0U) || ((mask & ~RS_I2C_INTR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    RS_I2C_REG(bus, RS_I2C_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_i2c_write_dma(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address,
                             const uint8_t *data, size_t length, rs_i2c_dma_workspace_t *workspace,
                             rs_timeout_t timeout) {
    rs_status_t status;
    size_t index;
    const uint32_t mode = (bus == RS_I2C_BUS_0) ? RS_DMA_MODE_I2C0_TX : RS_DMA_MODE_I2C1_TX;

    if (!rs_i2c_bus_valid(bus) || (data == NULL) || (workspace == NULL) || (length == 0U) ||
        (length > RS_I2C_DMA_MAX_BYTES)) {
        return RS_EINVAL;
    }
    status = rs_i2c_prepare(bus, address, ten_bit_address, timeout);
    if (status != RS_OK) {
        return status;
    }
    for (index = 0U; index < length; index++) {
        workspace->words[index] = (uint32_t)data[index];
    }
    workspace->words[length - 1U] |= RS_I2C_DATA_CMD_STOP;
    status = rs_dma_config(mode, (uintptr_t)&workspace->words[0], 1U,
                           rs_i2c_base(bus) + RS_I2C_DATA_CMD_OFFSET, 0U, (uint32_t)length);
    if (status == RS_OK) {
        status = rs_dma_start();
    }
    if (status == RS_OK) {
        status = rs_dma_wait(timeout);
    }
    if (status == RS_OK) {
        status = rs_i2c_wait_done(bus, timeout);
    }
    return status;
}

rs_status_t rs_i2c_read_dma(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address, uint8_t *data,
                            size_t length, rs_i2c_dma_workspace_t *workspace,
                            rs_timeout_t timeout) {
    rs_status_t status;
    size_t index;
    const uint32_t mode = (bus == RS_I2C_BUS_0) ? RS_DMA_MODE_I2C0_RX : RS_DMA_MODE_I2C1_RX;

    if (!rs_i2c_bus_valid(bus) || (data == NULL) || (workspace == NULL) || (length == 0U) ||
        (length > RS_I2C_DMA_MAX_BYTES)) {
        return RS_EINVAL;
    }
    status = rs_i2c_prepare(bus, address, ten_bit_address, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_dma_config(mode, rs_i2c_base(bus) + RS_I2C_RXDATA_OFFSET, 0U,
                           (uintptr_t)&workspace->words[0], 1U, (uint32_t)length);
    if (status != RS_OK) {
        return status;
    }
    for (index = 0U; index < length; index++) {
        uint32_t command = RS_I2C_DATA_CMD_READ;

        workspace->words[index] = 0U;
        if ((index + 1U) == length) {
            command |= RS_I2C_DATA_CMD_STOP | RS_I2C_DATA_CMD_NACK_LAST;
        }
        RS_I2C_REG(bus, RS_I2C_DATA_CMD_OFFSET) = command;
    }
    status = rs_dma_start();
    if (status == RS_OK) {
        status = rs_dma_wait(timeout);
    }
    if (status == RS_OK) {
        status = rs_i2c_wait_done(bus, timeout);
    }
    if (status == RS_OK) {
        for (index = 0U; index < length; index++) {
            data[index] = (uint8_t)workspace->words[index];
        }
    }
    return status;
}
