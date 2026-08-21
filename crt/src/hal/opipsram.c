#include <stddef.h>

#include <retrosoc/core/wait.h>
#include <retrosoc/hal/opipsram.h>

static volatile uint32_t *rs_opipsram_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_OPIPSRAM_BASE + offset);
}

static bool rs_opipsram_profile_valid(rs_opipsram_profile_t profile) {
    return (profile == RS_OPIPSRAM_PROFILE_OPI) || (profile == RS_OPIPSRAM_PROFILE_HYPERBUS);
}

static uint32_t rs_opipsram_command_value(uint16_t command, rs_opipsram_command_width_t width) {
    return ((uint32_t)command & RS_OPIPSRAM_CMD_VALUE_MASK) |
           (((uint32_t)width == (uint32_t)RS_OPIPSRAM_COMMAND_WIDTH_16) ? RS_OPIPSRAM_CMD_WIDTH_16
                                                                        : UINT32_C(0));
}

static uint32_t rs_opipsram_opi_timing_value(const rs_opipsram_opi_config_t *config) {
    uint32_t value;

    value =
        ((uint32_t)config->address_width - UINT32_C(3)) & RS_OPIPSRAM_OPI_TIMING_ADDR_BYTES_MASK;
    value |= ((uint32_t)config->dummy_cycles << RS_OPIPSRAM_OPI_TIMING_DUMMY_SHIFT) &
             RS_OPIPSRAM_OPI_TIMING_DUMMY_MASK;
    value |= ((uint32_t)config->latency_cycles << RS_OPIPSRAM_OPI_TIMING_LATENCY_SHIFT) &
             RS_OPIPSRAM_OPI_TIMING_LATENCY_MASK;
    if ((config->dqs_policy == RS_OPIPSRAM_DQS_READ) ||
        (config->dqs_policy == RS_OPIPSRAM_DQS_READ_WRITE)) {
        value |= RS_OPIPSRAM_OPI_TIMING_DQS_READ;
    }
    if ((config->dqs_policy == RS_OPIPSRAM_DQS_WRITE) ||
        (config->dqs_policy == RS_OPIPSRAM_DQS_READ_WRITE)) {
        value |= RS_OPIPSRAM_OPI_TIMING_DQS_WRITE;
    }
    value |= (uint32_t)config->burst_boundary << RS_OPIPSRAM_OPI_TIMING_BURST_SHIFT;
    return value;
}

static uint32_t rs_opipsram_hyper_timing_value(const rs_opipsram_hyperbus_config_t *config) {
    uint32_t value = (uint32_t)config->initial_latency;

    value |= (uint32_t)config->additional_latency << RS_OPIPSRAM_HYPER_TIMING_ADDITIONAL_SHIFT;
    value |= (uint32_t)config->read_recovery_cycles << RS_OPIPSRAM_HYPER_TIMING_READ_RECOVERY_SHIFT;
    value |= (uint32_t)config->write_recovery_cycles
             << RS_OPIPSRAM_HYPER_TIMING_WRITE_RECOVERY_SHIFT;
    if (config->rwds_additional_latency) {
        value |= RS_OPIPSRAM_HYPER_TIMING_RWDS_LATENCY_ENABLE;
    }
    return value;
}

static rs_status_t rs_opipsram_wait_interrupt(uint32_t interrupt, rs_timeout_t timeout) {
    rs_status_t status;
    uint32_t interrupt_state;

    status = rs_wait_mask(rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE), interrupt, interrupt,
                          timeout);
    interrupt_state = *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE);
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) = interrupt_state & RS_OPIPSRAM_INTERRUPT_ALL;
    if (status != RS_OK) {
        return status;
    }
    if ((interrupt_state & RS_OPIPSRAM_INTERRUPT_TIMEOUT) != UINT32_C(0)) {
        return RS_ETIMEOUT;
    }
    if ((interrupt_state & RS_OPIPSRAM_INTERRUPT_ERROR) != UINT32_C(0)) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_opipsram_configure(const rs_opipsram_config_t *config) {
    uint32_t controller_status;
    uint32_t profile_status;
    uint32_t control;
    uint32_t clock_config;
    uint32_t cs_timing;

    if ((rs_opipsram_config_validate(config) != RS_OK) ||
        !rs_opipsram_profile_valid(config->profile)) {
        return RS_EINVAL;
    }
    controller_status = *rs_opipsram_register(RS_OPIPSRAM_REG_STATUS);
    profile_status = *rs_opipsram_register(RS_OPIPSRAM_REG_PROFILE_STATUS);
    if (((controller_status & RS_OPIPSRAM_STATUS_BUSY) != UINT32_C(0)) ||
        ((controller_status & RS_OPIPSRAM_STATUS_PROFILE_LOCK) != UINT32_C(0)) ||
        ((profile_status & RS_OPIPSRAM_PROFILE_STATUS_LOCKED) != UINT32_C(0))) {
        return RS_EIO;
    }

    *rs_opipsram_register(RS_OPIPSRAM_REG_CTRL) = UINT32_C(0);
    *rs_opipsram_register(RS_OPIPSRAM_REG_PROTOCOL_CFG) = (uint32_t)config->profile;
    *rs_opipsram_register(RS_OPIPSRAM_REG_DEVICE_SIZE) = config->device_size;
    *rs_opipsram_register(RS_OPIPSRAM_REG_OPI_READ_CMD) =
        rs_opipsram_command_value(config->opi.read_command, config->opi.command_width);
    *rs_opipsram_register(RS_OPIPSRAM_REG_OPI_WRITE_CMD) =
        rs_opipsram_command_value(config->opi.write_command, config->opi.command_width);
    *rs_opipsram_register(RS_OPIPSRAM_REG_OPI_REG_READ_CMD) =
        rs_opipsram_command_value(config->opi.register_read_command, config->opi.command_width);
    *rs_opipsram_register(RS_OPIPSRAM_REG_OPI_REG_WRITE_CMD) =
        rs_opipsram_command_value(config->opi.register_write_command, config->opi.command_width);
    *rs_opipsram_register(RS_OPIPSRAM_REG_OPI_TIMING) = rs_opipsram_opi_timing_value(&config->opi);
    *rs_opipsram_register(RS_OPIPSRAM_REG_HYPER_TIMING) =
        rs_opipsram_hyper_timing_value(&config->hyperbus);
    clock_config = (uint32_t)config->timing.divider & RS_OPIPSRAM_CLK_DIVIDER_MASK;
    clock_config |= RS_OPIPSRAM_CLK_PHY_RATIO_2X;
    *rs_opipsram_register(RS_OPIPSRAM_REG_CLK_CONFIG) = clock_config;
    cs_timing = (uint32_t)config->timing.cs_setup_cycles;
    cs_timing |= (uint32_t)config->timing.cs_hold_cycles << RS_OPIPSRAM_CS_HOLD_SHIFT;
    cs_timing |= (uint32_t)config->timing.cs_high_cycles << RS_OPIPSRAM_CS_HIGH_SHIFT;
    *rs_opipsram_register(RS_OPIPSRAM_REG_CS_TIMING) = cs_timing;
    *rs_opipsram_register(RS_OPIPSRAM_REG_POWERUP_CYCLES) = config->timing.powerup_cycles;
    *rs_opipsram_register(RS_OPIPSRAM_REG_TIMEOUT_CYCLES) = config->timing.timeout_cycles;
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) = RS_OPIPSRAM_INTERRUPT_ALL;

    control = config->enable ? RS_OPIPSRAM_CTRL_ENABLE : UINT32_C(0);
    if (config->memory_enable) {
        control |= RS_OPIPSRAM_CTRL_MEMORY_ENABLE;
    }
    if (config->auto_initialize) {
        control |= RS_OPIPSRAM_CTRL_AUTO_INIT;
    }
    if (config->line_buffer) {
        control |= RS_OPIPSRAM_CTRL_LINE_BUFFER;
    }
    *rs_opipsram_register(RS_OPIPSRAM_REG_CTRL) = control;
    return RS_OK;
}

rs_status_t rs_opipsram_initialize(rs_timeout_t timeout) {
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) = RS_OPIPSRAM_INTERRUPT_ALL;
    *rs_opipsram_register(RS_OPIPSRAM_REG_COMMAND) = RS_OPIPSRAM_COMMAND_INIT;
    return rs_opipsram_wait_interrupt(RS_OPIPSRAM_INTERRUPT_INIT_DONE, timeout);
}

rs_status_t rs_opipsram_abort(void) {
    *rs_opipsram_register(RS_OPIPSRAM_REG_COMMAND) = RS_OPIPSRAM_COMMAND_ABORT;
    return RS_OK;
}

rs_status_t rs_opipsram_soft_reset(rs_timeout_t timeout) {
    *rs_opipsram_register(RS_OPIPSRAM_REG_COMMAND) = RS_OPIPSRAM_COMMAND_SOFT_RESET;
    return rs_wait_mask(rs_opipsram_register(RS_OPIPSRAM_REG_STATUS), RS_OPIPSRAM_STATUS_BUSY,
                        UINT32_C(0), timeout);
}

rs_status_t rs_opipsram_get_status(rs_opipsram_status_t *status) {
    uint32_t controller_status;
    uint32_t last_error;

    if (status == NULL) {
        return RS_EINVAL;
    }
    controller_status = *rs_opipsram_register(RS_OPIPSRAM_REG_STATUS);
    last_error = *rs_opipsram_register(RS_OPIPSRAM_REG_LAST_ERROR);
    status->last_error = (rs_opipsram_error_t)(last_error & RS_OPIPSRAM_LAST_ERROR_CLASS_MASK);
    status->last_error_address = *rs_opipsram_register(RS_OPIPSRAM_REG_LAST_ERROR_ADDR);
    status->profile_status = *rs_opipsram_register(RS_OPIPSRAM_REG_PROFILE_STATUS);
    status->busy = (controller_status & RS_OPIPSRAM_STATUS_BUSY) != UINT32_C(0);
    status->initialized = (controller_status & RS_OPIPSRAM_STATUS_INITIALIZED) != UINT32_C(0);
    status->ready = (controller_status & RS_OPIPSRAM_STATUS_READY) != UINT32_C(0);
    status->quiesced = (controller_status & RS_OPIPSRAM_STATUS_QUIESCED) != UINT32_C(0);
    status->trained = (controller_status & RS_OPIPSRAM_STATUS_TRAINED) != UINT32_C(0);
    status->error = (controller_status & RS_OPIPSRAM_STATUS_ERROR) != UINT32_C(0);
    status->profile_locked =
        ((controller_status & RS_OPIPSRAM_STATUS_PROFILE_LOCK) != UINT32_C(0)) ||
        ((status->profile_status & RS_OPIPSRAM_PROFILE_STATUS_LOCKED) != UINT32_C(0));
    status->hyperbus =
        ((controller_status & RS_OPIPSRAM_STATUS_HYPER) != UINT32_C(0)) ||
        ((status->profile_status & RS_OPIPSRAM_PROFILE_STATUS_PROFILE_MASK) != UINT32_C(0));
    return RS_OK;
}

rs_status_t rs_opipsram_indirect(const rs_opipsram_indirect_t *command, uint64_t *read_data,
                                 rs_timeout_t timeout) {
    uint32_t control;
    uint32_t device_size;
    rs_status_t status;

    if ((command == NULL) || ((!command->write) && (read_data == NULL))) {
        return RS_EINVAL;
    }
    device_size = command->register_space ? RS_OPIPSRAM_MAX_DEVICE_SIZE
                                          : *rs_opipsram_register(RS_OPIPSRAM_REG_DEVICE_SIZE);
    if (rs_opipsram_indirect_validate(command, device_size) != RS_OK) {
        return RS_EINVAL;
    }
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) = RS_OPIPSRAM_INTERRUPT_ALL;
    *rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_ADDR) = command->address;
    *rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_WDATA_LO) = (uint32_t)command->write_data;
    *rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_WDATA_HI) =
        (uint32_t)(command->write_data >> UINT32_C(32));
    control = ((uint32_t)command->length << RS_OPIPSRAM_INDIRECT_LENGTH_SHIFT) |
              RS_OPIPSRAM_INDIRECT_START;
    if (command->write) {
        control |= RS_OPIPSRAM_INDIRECT_WRITE;
    }
    if (command->register_space) {
        control |= RS_OPIPSRAM_INDIRECT_REGISTER_SPACE;
    }
    *rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_CTRL) = control;
    status = rs_opipsram_wait_interrupt(RS_OPIPSRAM_INTERRUPT_INDIRECT_DONE, timeout);
    if ((status == RS_OK) && !command->write) {
        *read_data =
            (uint64_t)*rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_RDATA_LO) |
            ((uint64_t)*rs_opipsram_register(RS_OPIPSRAM_REG_INDIRECT_RDATA_HI) << UINT32_C(32));
    }
    return status;
}

rs_status_t rs_opipsram_indirect_read(uint32_t address, bool register_space, uint8_t length,
                                      uint64_t *read_data, rs_timeout_t timeout) {
    const rs_opipsram_indirect_t command = {
        .write = false,
        .register_space = register_space,
        .length = length,
        .address = address,
        .write_data = UINT64_C(0),
    };

    return rs_opipsram_indirect(&command, read_data, timeout);
}

rs_status_t rs_opipsram_indirect_write(uint32_t address, bool register_space, uint8_t length,
                                       uint64_t write_data, rs_timeout_t timeout) {
    const rs_opipsram_indirect_t command = {
        .write = true,
        .register_space = register_space,
        .length = length,
        .address = address,
        .write_data = write_data,
    };

    return rs_opipsram_indirect(&command, NULL, timeout);
}

rs_status_t rs_opipsram_irq_enable(uint32_t mask) {
    if ((mask & ~RS_OPIPSRAM_INTERRUPT_ALL) != UINT32_C(0)) {
        return RS_EINVAL;
    }
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_ENABLE) = mask;
    return RS_OK;
}

rs_status_t rs_opipsram_irq_pending(uint32_t *pending) {
    if (pending == NULL) {
        return RS_EINVAL;
    }
    *pending = *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) & RS_OPIPSRAM_INTERRUPT_ALL;
    return RS_OK;
}

rs_status_t rs_opipsram_irq_clear(uint32_t mask) {
    if ((mask & ~RS_OPIPSRAM_INTERRUPT_ALL) != UINT32_C(0)) {
        return RS_EINVAL;
    }
    *rs_opipsram_register(RS_OPIPSRAM_REG_INTR_STATE) = mask;
    return RS_OK;
}

rs_status_t rs_opipsram_get_delay_tap(rs_opipsram_delay_tap_t *tap) {
    uint32_t value;

    if (tap == NULL) {
        return RS_EINVAL;
    }
    value = *rs_opipsram_register(RS_OPIPSRAM_REG_RX_DELAY);
    tap->fine = (uint8_t)(value & RS_OPIPSRAM_RX_DELAY_FINE_MASK);
    tap->coarse =
        (uint8_t)((value & RS_OPIPSRAM_RX_DELAY_COARSE_MASK) >> RS_OPIPSRAM_RX_DELAY_COARSE_SHIFT);
    return RS_OK;
}

rs_status_t rs_opipsram_set_delay_tap(const rs_opipsram_delay_tap_t *tap) {
    uint32_t status;
    uint32_t value;

    if ((tap == NULL) || (tap->fine > RS_OPIPSRAM_MAX_TAP) ||
        (tap->coarse > RS_OPIPSRAM_MAX_COARSE_TAP)) {
        return RS_EINVAL;
    }
    status = *rs_opipsram_register(RS_OPIPSRAM_REG_STATUS);
    if ((status & RS_OPIPSRAM_STATUS_BUSY) != UINT32_C(0)) {
        return RS_EIO;
    }
    value = (uint32_t)tap->fine | ((uint32_t)tap->coarse << RS_OPIPSRAM_RX_DELAY_COARSE_SHIFT);
    *rs_opipsram_register(RS_OPIPSRAM_REG_RX_DELAY) = value;
    return RS_OK;
}

static uint32_t rs_opipsram_xorshift32(uint32_t *state) {
    uint32_t value;

    value = *state;
    value ^= value << UINT32_C(13);
    value ^= value >> UINT32_C(17);
    value ^= value << UINT32_C(5);
    *state = value;
    return value;
}

rs_status_t rs_opipsram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                                 rs_opipsram_test_failure_t *failure) {
    volatile uint32_t *memory;
    uint64_t end_address;
    uint32_t words;
    uint32_t state;
    uint32_t index;

    if ((address < (uintptr_t)RS_SOC_OPIPSRAM_BASE) || (address > (uintptr_t)UINT32_MAX) ||
        ((address % sizeof(uint32_t)) != 0U) || (size < sizeof(uint32_t)) || (word_limit == 0U)) {
        return RS_EINVAL;
    }
    end_address = (uint64_t)address + (uint64_t)size;
    if (end_address > ((uint64_t)RS_SOC_OPIPSRAM_END + UINT64_C(1))) {
        return RS_EINVAL;
    }
    memory = (volatile uint32_t *)address;
    words = size / (uint32_t)sizeof(uint32_t);
    if (words > word_limit) {
        words = word_limit;
    }
    state = UINT32_C(0x13579BDF);
    for (index = UINT32_C(0); index < words; index++) {
        memory[index] = rs_opipsram_xorshift32(&state);
    }
    state = UINT32_C(0x13579BDF);
    for (index = UINT32_C(0); index < words; index++) {
        uint32_t expected = rs_opipsram_xorshift32(&state);
        uint32_t actual = memory[index];

        if (actual != expected) {
            if (failure != NULL) {
                failure->address = (uint32_t)address + (index * (uint32_t)sizeof(uint32_t));
                failure->expected = expected;
                failure->actual = actual;
            }
            return RS_EIO;
        }
    }
    return RS_OK;
}

rs_status_t rs_opipsram_dma_copy(uint32_t channel, uintptr_t source, uintptr_t destination,
                                 uint32_t byte_count, uint8_t priority, uint8_t burst_beats) {
    rs_dma_config_t config;
    rs_status_t status;

    status = rs_opipsram_dma_copy_validate(channel, source, destination, byte_count, priority,
                                           burst_beats, &config);
    if (status != RS_OK) {
        return status;
    }
    status = rs_dma_configure(channel, &config);
    if (status != RS_OK) {
        return status;
    }
    return rs_dma_start(channel);
}
