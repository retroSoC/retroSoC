#include <limits.h>
#include <stddef.h>

#include <retrosoc/core/wait.h>
#include <retrosoc/hal/xpi.h>

#define RS_XPI_PERIPHERAL_SLOT     UINT8_C(1)
#define RS_XPI_PERIPHERAL_SEQUENCE UINT8_C(15)

static volatile uint32_t *rs_xpi_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_XPI_BASE + offset);
}

static bool rs_xpi_power_of_two(uint32_t value) {
    return (value != UINT32_C(0)) && ((value & (value - UINT32_C(1))) == UINT32_C(0));
}

static bool rs_xpi_transfer_valid(const rs_xpi_transfer_t *transfer) {
    if ((transfer == NULL) || (transfer->slot >= RS_XPI_SLOT_COUNT) ||
        (transfer->sequence >= RS_XPI_LUT_SEQUENCE_COUNT) ||
        (transfer->address >= RS_XPI_SLOT_WINDOW_SIZE) ||
        ((transfer->tx_data != NULL) && (transfer->rx_data != NULL))) {
        return false;
    }
    if ((transfer->byte_count != UINT16_C(0)) && (transfer->tx_data == NULL) &&
        (transfer->rx_data == NULL)) {
        return false;
    }
    return true;
}

static rs_status_t rs_xpi_wait_idle(rs_timeout_t timeout) {
    return rs_wait_mask(rs_xpi_register(RS_XPI_REG_STATUS), RS_XPI_STATUS_BUSY_ALL, UINT32_C(0),
                        timeout);
}

static uint32_t rs_xpi_pack_word(const uint8_t *data, uint32_t offset, uint32_t length) {
    uint32_t value = UINT32_C(0);
    uint32_t byte_index;

    for (byte_index = UINT32_C(0); (byte_index < UINT32_C(4)) && ((offset + byte_index) < length);
         byte_index++) {
        value |= (uint32_t)data[offset + byte_index] << (byte_index * UINT32_C(8));
    }
    return value;
}

static void rs_xpi_unpack_word(uint32_t value, uint8_t *data, uint32_t offset, uint32_t length) {
    uint32_t byte_index;

    for (byte_index = UINT32_C(0); (byte_index < UINT32_C(4)) && ((offset + byte_index) < length);
         byte_index++) {
        data[offset + byte_index] = (uint8_t)(value >> (byte_index * UINT32_C(8)));
    }
}

static rs_status_t rs_xpi_interrupt_result(uint32_t interrupt_state) {
    if ((interrupt_state & RS_XPI_INTR_TIMEOUT) != UINT32_C(0)) {
        return RS_ETIMEOUT;
    }
    if ((interrupt_state & (RS_XPI_INTR_AXI_ERROR | RS_XPI_INTR_SEQUENCE_ERROR)) != UINT32_C(0)) {
        return RS_EIO;
    }
    return RS_OK;
}

static rs_status_t rs_xpi_wait_completion(uint32_t done_mask, rs_timeout_t timeout,
                                          uint32_t *interrupt_state) {
    uint32_t state;

    while (timeout-- != UINT32_C(0)) {
        state = *rs_xpi_register(RS_XPI_REG_INTR_STATE);
        if ((state & (done_mask | RS_XPI_INTR_ERROR_ALL)) != UINT32_C(0)) {
            *interrupt_state = state;
            return rs_xpi_interrupt_result(state);
        }
    }
    *interrupt_state = *rs_xpi_register(RS_XPI_REG_INTR_STATE);
    return RS_ETIMEOUT;
}

uint16_t rs_xpi_instruction(rs_xpi_instruction_opcode_t opcode, rs_xpi_pads_t pads,
                            uint8_t operand) {
    return (uint16_t)(((uint16_t)opcode << UINT16_C(12)) | ((uint16_t)pads << UINT16_C(10)) |
                      (uint16_t)operand);
}

rs_status_t rs_xpi_probe(void) {
    if ((*rs_xpi_register(RS_XPI_REG_ID) != RS_XPI_ID_VALUE) ||
        (*rs_xpi_register(RS_XPI_REG_VERSION) != RS_XPI_VERSION_VALUE) ||
        (*rs_xpi_register(RS_XPI_REG_CAPABILITY) != RS_XPI_CAPABILITY_VALUE)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

rs_status_t rs_xpi_enable(bool enable, rs_timeout_t timeout) {
    rs_status_t status = rs_xpi_wait_idle(timeout);

    if (status != RS_OK) {
        return status;
    }
    *rs_xpi_register(RS_XPI_REG_CTRL) = enable ? RS_XPI_CTRL_ENABLE : UINT32_C(0);
    return RS_OK;
}

rs_status_t rs_xpi_slot_configure(uint8_t slot, const rs_xpi_slot_config_t *config,
                                  rs_timeout_t timeout) {
    uint32_t control = UINT32_C(0);
    uint32_t sequence;
    uint32_t timing;

    if ((config == NULL) || (slot >= RS_XPI_SLOT_COUNT) || (config->device_size == UINT32_C(0)) ||
        (config->device_size > RS_XPI_SLOT_WINDOW_SIZE) ||
        (config->read_sequence >= RS_XPI_LUT_SEQUENCE_COUNT) ||
        (config->write_sequence >= RS_XPI_LUT_SEQUENCE_COUNT) ||
        (config->timeout_cycles == UINT32_C(0)) ||
        ((config->burst_boundary != UINT32_C(0)) &&
         ((config->burst_boundary < UINT32_C(4)) ||
          (config->burst_boundary > RS_XPI_SLOT_WINDOW_SIZE) ||
          !rs_xpi_power_of_two(config->burst_boundary)))) {
        return RS_EINVAL;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CTRL) & RS_XPI_CTRL_ENABLE) != UINT32_C(0)) {
        return RS_EIO;
    }
    if (rs_xpi_wait_idle(timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CONFIG_LOCK) &
         (RS_XPI_CONFIG_LOCK_GLOBAL | (RS_XPI_CONFIG_LOCK_SLOT0 << slot))) != UINT32_C(0)) {
        return RS_EIO;
    }

    if (config->enable) {
        control |= RS_XPI_SLOT_ENABLE;
    }
    if (config->memory_read_enable) {
        control |= RS_XPI_SLOT_MM_READ_ENABLE;
    }
    if (config->memory_write_enable) {
        control |= RS_XPI_SLOT_MM_WRITE_ENABLE;
    }
    if (config->mode3) {
        control |= RS_XPI_SLOT_MODE3;
    }
    sequence = (uint32_t)config->read_sequence | ((uint32_t)config->write_sequence << UINT32_C(4));
    timing = (uint32_t)config->clock_divider | ((uint32_t)config->cs_setup_cycles << UINT32_C(8)) |
             ((uint32_t)config->cs_hold_cycles << UINT32_C(16)) |
             ((uint32_t)config->cs_high_cycles << UINT32_C(24));

    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_CTRL) = control;
    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_DEVICE_SIZE) = config->device_size;
    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_SEQ_CFG) = sequence;
    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_TIMING) = timing;
    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_TIMEOUT) = config->timeout_cycles;
    RS_XPI_SLOT_REG(slot, RS_XPI_REG_SLOT_BOUNDARY) = config->burst_boundary;
    return RS_OK;
}

rs_status_t rs_xpi_lut_write(uint8_t sequence, const uint16_t *instructions,
                             size_t instruction_count, rs_timeout_t timeout) {
    uint32_t instruction_index;
    uint32_t offset;
    uint16_t low;
    uint16_t high;

    if ((sequence >= RS_XPI_LUT_SEQUENCE_COUNT) || (instructions == NULL) ||
        (instruction_count == 0U) || (instruction_count > RS_XPI_LUT_INSTRUCTION_COUNT)) {
        return RS_EINVAL;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CTRL) & RS_XPI_CTRL_ENABLE) != UINT32_C(0)) {
        return RS_EIO;
    }
    if (rs_xpi_wait_idle(timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CONFIG_LOCK) &
         (RS_XPI_CONFIG_LOCK_GLOBAL | RS_XPI_CONFIG_LOCK_LUT)) != UINT32_C(0)) {
        return RS_EIO;
    }

    offset = RS_XPI_REG_LUT_BASE + ((uint32_t)sequence * UINT32_C(16));
    for (instruction_index = UINT32_C(0); instruction_index < RS_XPI_LUT_INSTRUCTION_COUNT;
         instruction_index += UINT32_C(2)) {
        low = (instruction_index < instruction_count)
                  ? instructions[instruction_index]
                  : rs_xpi_instruction(RS_XPI_INSTR_STOP, RS_XPI_PADS_1, UINT8_C(0));
        high = ((instruction_index + UINT32_C(1)) < instruction_count)
                   ? instructions[instruction_index + UINT32_C(1)]
                   : rs_xpi_instruction(RS_XPI_INSTR_STOP, RS_XPI_PADS_1, UINT8_C(0));
        *rs_xpi_register(offset) = (uint32_t)low | ((uint32_t)high << UINT32_C(16));
        offset += UINT32_C(4);
    }
    return RS_OK;
}

rs_status_t rs_xpi_transfer(const rs_xpi_transfer_t *transfer, rs_timeout_t timeout) {
    uint32_t transmit_offset = UINT32_C(0);
    uint32_t receive_offset = UINT32_C(0);
    uint32_t interrupt_state;
    uint32_t fifo_status;
    uint32_t fifo_control;
    bool complete = false;

    if (!rs_xpi_transfer_valid(transfer)) {
        return RS_EINVAL;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CTRL) & RS_XPI_CTRL_ENABLE) == UINT32_C(0)) {
        return RS_EIO;
    }
    if (rs_xpi_wait_idle(timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }

    fifo_control = *rs_xpi_register(RS_XPI_REG_FIFO_CTRL);
    *rs_xpi_register(RS_XPI_REG_FIFO_CTRL) =
        fifo_control | RS_XPI_FIFO_TX_FLUSH | RS_XPI_FIFO_RX_FLUSH;
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_ADDR) = transfer->address;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_COUNT) = transfer->byte_count;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_CFG) =
        (uint32_t)transfer->slot | ((uint32_t)transfer->sequence << UINT32_C(4));
    *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_INDIRECT_START;

    while (timeout-- != UINT32_C(0)) {
        fifo_status = *rs_xpi_register(RS_XPI_REG_FIFO_STATUS);
        if ((transfer->tx_data != NULL) && (transmit_offset < transfer->byte_count) &&
            ((fifo_status & RS_XPI_FIFO_TX_FULL) == UINT32_C(0))) {
            *rs_xpi_register(RS_XPI_REG_TXDATA) =
                rs_xpi_pack_word(transfer->tx_data, transmit_offset, transfer->byte_count);
            transmit_offset += UINT32_C(4);
        }
        if ((transfer->rx_data != NULL) && (receive_offset < transfer->byte_count) &&
            ((fifo_status & RS_XPI_FIFO_RX_EMPTY) == UINT32_C(0))) {
            rs_xpi_unpack_word(*rs_xpi_register(RS_XPI_REG_RXDATA), transfer->rx_data,
                               receive_offset, transfer->byte_count);
            receive_offset += UINT32_C(4);
        }
        interrupt_state = *rs_xpi_register(RS_XPI_REG_INTR_STATE);
        if ((interrupt_state & (RS_XPI_INTR_INDIRECT_DONE | RS_XPI_INTR_ERROR_ALL)) !=
            UINT32_C(0)) {
            complete = true;
            break;
        }
    }

    interrupt_state = *rs_xpi_register(RS_XPI_REG_INTR_STATE);
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = interrupt_state & RS_XPI_INTR_ALL;
    if (!complete) {
        *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_ABORT;
        return RS_ETIMEOUT;
    }
    if (rs_xpi_interrupt_result(interrupt_state) != RS_OK) {
        return rs_xpi_interrupt_result(interrupt_state);
    }
    while ((transfer->rx_data != NULL) && (receive_offset < transfer->byte_count)) {
        fifo_status = *rs_xpi_register(RS_XPI_REG_FIFO_STATUS);
        if ((fifo_status & RS_XPI_FIFO_RX_EMPTY) != UINT32_C(0)) {
            return RS_EIO;
        }
        rs_xpi_unpack_word(*rs_xpi_register(RS_XPI_REG_RXDATA), transfer->rx_data, receive_offset,
                           transfer->byte_count);
        receive_offset += UINT32_C(4);
    }
    return RS_OK;
}

rs_status_t rs_xpi_transfer_dma(const rs_xpi_transfer_t *transfer, rs_xpi_dma_direction_t direction,
                                uint32_t channel, rs_timeout_t timeout) {
    rs_dma_config_t dma_config;
    rs_status_t status;
    uintptr_t buffer;
    uint32_t dma_control;
    uint32_t interrupt_state;

    if (!rs_xpi_transfer_valid(transfer) ||
        ((direction != RS_XPI_DMA_TRANSMIT) && (direction != RS_XPI_DMA_RECEIVE)) ||
        (transfer->byte_count == UINT16_C(0)) ||
        ((transfer->byte_count % sizeof(uint32_t)) != UINT16_C(0)) ||
        ((direction == RS_XPI_DMA_TRANSMIT) && (transfer->tx_data == NULL)) ||
        ((direction == RS_XPI_DMA_RECEIVE) && (transfer->rx_data == NULL))) {
        return RS_EINVAL;
    }
    if ((*rs_xpi_register(RS_XPI_REG_CTRL) & RS_XPI_CTRL_ENABLE) == UINT32_C(0)) {
        return RS_EIO;
    }
    status = rs_xpi_wait_idle(timeout);
    if (status != RS_OK) {
        return status;
    }
    buffer = (direction == RS_XPI_DMA_TRANSMIT) ? (uintptr_t)transfer->tx_data
                                                : (uintptr_t)transfer->rx_data;
    if ((buffer % sizeof(uint32_t)) != (uintptr_t)0U) {
        return RS_EINVAL;
    }

    dma_config.kind = RS_DMA_KIND_MM_TO_MM;
    dma_config.request =
        (direction == RS_XPI_DMA_TRANSMIT) ? RS_DMA_REQUEST_XPI_TX : RS_DMA_REQUEST_XPI_RX;
    dma_config.source =
        (direction == RS_XPI_DMA_TRANSMIT) ? buffer : (uintptr_t)rs_xpi_register(RS_XPI_REG_RXDATA);
    dma_config.destination =
        (direction == RS_XPI_DMA_TRANSMIT) ? (uintptr_t)rs_xpi_register(RS_XPI_REG_TXDATA) : buffer;
    dma_config.byte_count = transfer->byte_count;
    dma_config.width = RS_DMA_WIDTH_32;
    dma_config.source_increment = direction == RS_XPI_DMA_TRANSMIT;
    dma_config.destination_increment = direction == RS_XPI_DMA_RECEIVE;
    dma_config.priority = UINT8_C(2);
    dma_config.burst_beats = UINT8_C(1);

    status = rs_dma_configure(channel, &dma_config);
    if (status != RS_OK) {
        return status;
    }
    *rs_xpi_register(RS_XPI_REG_FIFO_CTRL) |= RS_XPI_FIFO_TX_FLUSH | RS_XPI_FIFO_RX_FLUSH;
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_ADDR) = transfer->address;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_COUNT) = transfer->byte_count;
    *rs_xpi_register(RS_XPI_REG_INDIRECT_CFG) =
        (uint32_t)transfer->slot | ((uint32_t)transfer->sequence << UINT32_C(4));
    dma_control = (direction == RS_XPI_DMA_TRANSMIT) ? RS_XPI_DMA_TX_ENABLE : RS_XPI_DMA_RX_ENABLE;
    *rs_xpi_register(RS_XPI_REG_DMA_CTRL) = dma_control;
    status = rs_dma_start(channel);
    if (status == RS_OK) {
        *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_INDIRECT_START;
        status = rs_dma_wait(channel, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_wait_completion(RS_XPI_INTR_INDIRECT_DONE, timeout, &interrupt_state);
    }
    if (status != RS_OK) {
        interrupt_state = *rs_xpi_register(RS_XPI_REG_INTR_STATE);
    }
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = interrupt_state & RS_XPI_INTR_ALL;
    *rs_xpi_register(RS_XPI_REG_DMA_CTRL) = UINT32_C(0);
    if (status != RS_OK) {
        (void)rs_dma_abort_wait(channel, timeout);
        *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_ABORT;
        return status;
    }
    return rs_xpi_interrupt_result(interrupt_state);
}

rs_status_t rs_xpi_poll(const rs_xpi_poll_config_t *config, rs_timeout_t timeout) {
    rs_status_t status;
    uint32_t interrupt_state;

    if ((config == NULL) || (config->slot >= RS_XPI_SLOT_COUNT) ||
        (config->sequence >= RS_XPI_LUT_SEQUENCE_COUNT) ||
        (config->timeout_cycles == UINT32_C(0))) {
        return RS_EINVAL;
    }
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ALL;
    *rs_xpi_register(RS_XPI_REG_POLL_CFG) =
        (uint32_t)config->slot | ((uint32_t)config->sequence << UINT32_C(4));
    *rs_xpi_register(RS_XPI_REG_POLL_MASK) = config->mask;
    *rs_xpi_register(RS_XPI_REG_POLL_MATCH) = config->match;
    *rs_xpi_register(RS_XPI_REG_POLL_INTERVAL) = config->interval_cycles;
    *rs_xpi_register(RS_XPI_REG_POLL_TIMEOUT) = config->timeout_cycles;
    *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_POLL_START;
    status = rs_xpi_wait_completion(RS_XPI_INTR_POLL_MATCH, timeout, &interrupt_state);
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = interrupt_state & RS_XPI_INTR_ALL;
    return status;
}

rs_status_t rs_xpi_abort(rs_timeout_t timeout) {
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = RS_XPI_INTR_ABORT_DONE;
    *rs_xpi_register(RS_XPI_REG_COMMAND) = RS_XPI_COMMAND_ABORT;
    return rs_wait_mask(rs_xpi_register(RS_XPI_REG_STATUS), RS_XPI_STATUS_BUSY_ALL, UINT32_C(0),
                        timeout);
}

rs_status_t rs_xpi_irq_enable(uint32_t mask) {
    if ((mask & ~RS_XPI_INTR_ALL) != UINT32_C(0)) {
        return RS_EINVAL;
    }
    *rs_xpi_register(RS_XPI_REG_INTR_ENABLE) = mask;
    return RS_OK;
}

rs_status_t rs_xpi_irq_pending(uint32_t *pending) {
    if (pending == NULL) {
        return RS_EINVAL;
    }
    *pending = *rs_xpi_register(RS_XPI_REG_INTR_STATE) & RS_XPI_INTR_ALL;
    return RS_OK;
}

rs_status_t rs_xpi_irq_clear(uint32_t mask) {
    if ((mask & ~RS_XPI_INTR_ALL) != UINT32_C(0)) {
        return RS_EINVAL;
    }
    *rs_xpi_register(RS_XPI_REG_INTR_STATE) = mask;
    return RS_OK;
}

rs_status_t rs_xpi_error_get(rs_xpi_error_t *error) {
    uint32_t state;
    uint32_t info;

    if (error == NULL) {
        return RS_EINVAL;
    }
    state = *rs_xpi_register(RS_XPI_REG_ERROR_STATE);
    info = *rs_xpi_register(RS_XPI_REG_ERROR_INFO);
    error->valid = (state & RS_XPI_ERROR_VALID) != UINT32_C(0);
    error->code = (rs_xpi_error_code_t)(state & RS_XPI_ERROR_CODE_MASK);
    error->address = *rs_xpi_register(RS_XPI_REG_ERROR_ADDR);
    error->slot = (uint8_t)((info & RS_XPI_ERROR_INFO_SLOT_MASK) >> RS_XPI_ERROR_INFO_SLOT_SHIFT);
    error->instruction =
        (uint8_t)((info & RS_XPI_ERROR_INFO_PC_MASK) >> RS_XPI_ERROR_INFO_PC_SHIFT);
    return RS_OK;
}

rs_status_t rs_xpi_error_clear(void) {
    *rs_xpi_register(RS_XPI_REG_ERROR_STATE) = RS_XPI_ERROR_VALID;
    return RS_OK;
}

rs_status_t rs_xpi_performance_enable(bool enable, bool clear) {
    *rs_xpi_register(RS_XPI_REG_PERF_CTRL) =
        (enable ? RS_XPI_PERF_ENABLE : UINT32_C(0)) | (clear ? RS_XPI_PERF_CLEAR : UINT32_C(0));
    return RS_OK;
}

rs_status_t rs_xpi_performance_get(rs_xpi_performance_t *performance) {
    if (performance == NULL) {
        return RS_EINVAL;
    }
    performance->axi_read_bytes = *rs_xpi_register(RS_XPI_REG_PERF_AXI_READ_BYTES);
    performance->axi_write_bytes = *rs_xpi_register(RS_XPI_REG_PERF_AXI_WRITE_BYTES);
    performance->phy_bytes = *rs_xpi_register(RS_XPI_REG_PERF_PHY_BYTES);
    performance->commands = *rs_xpi_register(RS_XPI_REG_PERF_COMMANDS);
    performance->stall_cycles = *rs_xpi_register(RS_XPI_REG_PERF_STALL_CYCLES);
    return RS_OK;
}

rs_status_t rs_xpi_config_lock(uint32_t mask) {
    if ((mask & ~RS_XPI_CONFIG_LOCK_ALL) != UINT32_C(0)) {
        return RS_EINVAL;
    }
    *rs_xpi_register(RS_XPI_REG_CONFIG_LOCK) = mask;
    return RS_OK;
}

rs_status_t rs_xpi_peripheral_initialize(rs_timeout_t timeout) {
    const uint16_t instructions[] = {
        UINT16_C(0x5000),
        UINT16_C(0x0000),
    };
    const rs_xpi_slot_config_t slot_config = {
        .enable = true,
        .memory_read_enable = false,
        .memory_write_enable = false,
        .mode3 = false,
        .device_size = RS_XPI_SLOT_WINDOW_SIZE,
        .read_sequence = RS_XPI_PERIPHERAL_SEQUENCE,
        .write_sequence = RS_XPI_PERIPHERAL_SEQUENCE,
        .clock_divider = UINT8_C(1),
        .cs_setup_cycles = UINT8_C(1),
        .cs_hold_cycles = UINT8_C(1),
        .cs_high_cycles = UINT8_C(2),
        .timeout_cycles = UINT32_C(0x00010000),
        .burst_boundary = UINT32_C(0),
    };
    rs_status_t status;

    status = rs_xpi_enable(false, timeout);
    if (status == RS_OK) {
        status = rs_xpi_slot_configure(RS_XPI_PERIPHERAL_SLOT, &slot_config, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_lut_write(RS_XPI_PERIPHERAL_SEQUENCE, instructions,
                                  sizeof(instructions) / sizeof(instructions[0]), timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_enable(true, timeout);
    }
    return status;
}

rs_status_t rs_xpi_peripheral_write(const uint8_t *data, size_t length, rs_timeout_t timeout) {
    rs_xpi_transfer_t transfer;
    size_t offset = 0U;
    rs_status_t status = RS_OK;

    if ((data == NULL) || (length == 0U)) {
        return RS_EINVAL;
    }
    while ((status == RS_OK) && (offset < length)) {
        const size_t remaining = length - offset;
        const uint16_t chunk = (remaining > (size_t)RS_XPI_MAX_TRANSFER_BYTES)
                                   ? RS_XPI_MAX_TRANSFER_BYTES
                                   : (uint16_t)remaining;
        transfer.slot = RS_XPI_PERIPHERAL_SLOT;
        transfer.sequence = RS_XPI_PERIPHERAL_SEQUENCE;
        transfer.address = UINT32_C(0);
        transfer.tx_data = &data[offset];
        transfer.rx_data = NULL;
        transfer.byte_count = chunk;
        status = rs_xpi_transfer(&transfer, timeout);
        offset += chunk;
    }
    return status;
}

rs_status_t rs_xpi_peripheral_write_dma(const void *data, size_t length, uint32_t channel,
                                        rs_timeout_t timeout) {
    rs_xpi_transfer_t transfer;

    if ((data == NULL) || (length == 0U) || (length > (size_t)RS_XPI_MAX_TRANSFER_BYTES) ||
        ((length % sizeof(uint32_t)) != 0U)) {
        return RS_EINVAL;
    }
    transfer.slot = RS_XPI_PERIPHERAL_SLOT;
    transfer.sequence = RS_XPI_PERIPHERAL_SEQUENCE;
    transfer.address = UINT32_C(0);
    transfer.tx_data = (const uint8_t *)data;
    transfer.rx_data = NULL;
    transfer.byte_count = (uint16_t)length;
    return rs_xpi_transfer_dma(&transfer, RS_XPI_DMA_TRANSMIT, channel, timeout);
}
