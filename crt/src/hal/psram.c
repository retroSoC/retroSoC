#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/clock.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/lib/printf.h>

#define RS_PSRAM_CTRL_OFFSET                  UINT32_C(0x000)
#define RS_PSRAM_COMMAND_OFFSET               UINT32_C(0x004)
#define RS_PSRAM_STATUS_OFFSET                UINT32_C(0x008)
#define RS_PSRAM_CHIP_ENABLE_OFFSET           UINT32_C(0x00C)
#define RS_PSRAM_CHIP_PRESENT_OFFSET          UINT32_C(0x010)
#define RS_PSRAM_CHIP_READY_OFFSET            UINT32_C(0x014)
#define RS_PSRAM_CHIP_MODE_OFFSET             UINT32_C(0x018)
#define RS_PSRAM_CHIP_ERROR_OFFSET            UINT32_C(0x01C)
#define RS_PSRAM_CLK_CONFIG_OFFSET            UINT32_C(0x020)
#define RS_PSRAM_POWERUP_CYCLES_OFFSET        UINT32_C(0x024)
#define RS_PSRAM_CS_SETUP_CYCLES_OFFSET       UINT32_C(0x028)
#define RS_PSRAM_CS_HIGH_CYCLES_OFFSET        UINT32_C(0x02C)
#define RS_PSRAM_CS_HOLD_CYCLES_OFFSET        UINT32_C(0x030)
#define RS_PSRAM_CS_MAX_LOW_CYCLES_OFFSET     UINT32_C(0x034)
#define RS_PSRAM_ACCESS_TIMEOUT_CYCLES_OFFSET UINT32_C(0x038)
#define RS_PSRAM_INDIRECT_CTRL_OFFSET         UINT32_C(0x040)
#define RS_PSRAM_INDIRECT_ADDR_OFFSET         UINT32_C(0x044)
#define RS_PSRAM_INDIRECT_WDATA_LO_OFFSET     UINT32_C(0x048)
#define RS_PSRAM_INDIRECT_WDATA_HI_OFFSET     UINT32_C(0x04C)
#define RS_PSRAM_INDIRECT_RDATA_LO_OFFSET     UINT32_C(0x050)
#define RS_PSRAM_INDIRECT_RDATA_HI_OFFSET     UINT32_C(0x054)
#define RS_PSRAM_LAST_ERROR_OFFSET            UINT32_C(0x058)
#define RS_PSRAM_LAST_ERROR_ADDR_OFFSET       UINT32_C(0x05C)
#define RS_PSRAM_CHIP_ID_BASE_OFFSET          UINT32_C(0x060)
#define RS_PSRAM_INTR_STATE_OFFSET            UINT32_C(0x080)
#define RS_PSRAM_INTR_ENABLE_OFFSET           UINT32_C(0x084)
#define RS_PSRAM_INTR_TEST_OFFSET             UINT32_C(0x08C)

#define RS_PSRAM_CTRL_ENABLE_MASK             UINT32_C(0x00000001)
#define RS_PSRAM_CTRL_MEMORY_ENABLE_MASK      UINT32_C(0x00000002)
#define RS_PSRAM_CTRL_AUTO_INIT_MASK          UINT32_C(0x00000004)
#define RS_PSRAM_CTRL_WRAP32_MASK             UINT32_C(0x00000008)
#define RS_PSRAM_COMMAND_INIT_MASK            UINT32_C(0x00000001)
#define RS_PSRAM_COMMAND_RECOVER_MASK         UINT32_C(0x00000002)
#define RS_PSRAM_COMMAND_ABORT_MASK           UINT32_C(0x00000004)
#define RS_PSRAM_COMMAND_CHIP_SHIFT           8U
#define RS_PSRAM_STATUS_INIT_BUSY_MASK        UINT32_C(0x00000001)
#define RS_PSRAM_STATUS_AXI_BUSY_MASK         UINT32_C(0x00000002)
#define RS_PSRAM_STATUS_INDIRECT_BUSY_MASK    UINT32_C(0x00000004)
#define RS_PSRAM_STATUS_PHY_BUSY_MASK         UINT32_C(0x00000008)
#define RS_PSRAM_STATUS_QUIESCED_MASK         UINT32_C(0x00000010)
#define RS_PSRAM_STATUS_READY_MASK            UINT32_C(0x00000020)
#define RS_PSRAM_STATUS_BUSY_MASK             UINT32_C(0x0000000F)
#define RS_PSRAM_CLK_ABOVE_84MHZ_MASK         UINT32_C(0x00010000)
#define RS_PSRAM_INDIRECT_CHIP_SHIFT          8U
#define RS_PSRAM_INDIRECT_LENGTH_SHIFT        16U
#define RS_PSRAM_INDIRECT_START_MASK          UINT32_C(0x80000000)

static volatile uint32_t *rs_psram_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_RIBP_PSRAM_BASE + offset);
}

static bool rs_psram_chip_valid(uint8_t chip) {
    return chip < (uint8_t)RS_PSRAM_CHIP_COUNT;
}

static bool rs_psram_command_valid(rs_psram_command_t command) {
    return (uint32_t)command <= (uint32_t)RS_PSRAM_COMMAND_READ_ID;
}

static bool rs_psram_config_valid(const rs_psram_config_t *config) {
    return (config != NULL) && (config->chip_enable != 0U) &&
           ((config->chip_enable & UINT8_C(0xF0)) == 0U) &&
           (config->timing.half_period_cycles != 0U) && (config->timing.cs_max_low_cycles != 0U) &&
           (config->timing.access_timeout_cycles > config->timing.cs_max_low_cycles) &&
           (config->timing.actual_sclk_hz != 0U) &&
           (config->timing.actual_sclk_hz <= RS_PSRAM_MAX_SCLK_HZ);
}

static rs_status_t rs_psram_wait_interrupt(uint32_t interrupt, rs_timeout_t timeout) {
    rs_status_t status;
    uint32_t interrupt_state;

    status =
        rs_wait_mask(rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET), interrupt, interrupt, timeout);
    if (status != RS_OK) {
        return status;
    }
    interrupt_state = *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET);
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = interrupt_state & RS_PSRAM_INTERRUPT_ALL;
    if ((interrupt_state & (RS_PSRAM_INTERRUPT_ERROR | RS_PSRAM_INTERRUPT_TIMEOUT)) != 0U) {
        return (interrupt_state & RS_PSRAM_INTERRUPT_TIMEOUT) != 0U ? RS_ETIMEOUT : RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_psram_configure(const rs_psram_config_t *config) {
    uint32_t status;
    uint32_t control;
    uint32_t clock_config;

    if (!rs_psram_config_valid(config)) {
        return RS_EINVAL;
    }
    status = *rs_psram_register(RS_PSRAM_STATUS_OFFSET);
    if ((status & RS_PSRAM_STATUS_BUSY_MASK) != 0U) {
        return RS_EIO;
    }

    *rs_psram_register(RS_PSRAM_CTRL_OFFSET) = 0U;
    *rs_psram_register(RS_PSRAM_CHIP_ENABLE_OFFSET) = config->chip_enable;
    clock_config = config->timing.half_period_cycles;
    if (config->timing.above_84mhz) {
        clock_config |= RS_PSRAM_CLK_ABOVE_84MHZ_MASK;
    }
    *rs_psram_register(RS_PSRAM_CLK_CONFIG_OFFSET) = clock_config;
    *rs_psram_register(RS_PSRAM_POWERUP_CYCLES_OFFSET) = config->timing.powerup_cycles;
    *rs_psram_register(RS_PSRAM_CS_SETUP_CYCLES_OFFSET) = config->timing.cs_setup_cycles;
    *rs_psram_register(RS_PSRAM_CS_HIGH_CYCLES_OFFSET) = config->timing.cs_high_cycles;
    *rs_psram_register(RS_PSRAM_CS_HOLD_CYCLES_OFFSET) = config->timing.cs_hold_cycles;
    *rs_psram_register(RS_PSRAM_CS_MAX_LOW_CYCLES_OFFSET) = config->timing.cs_max_low_cycles;
    *rs_psram_register(RS_PSRAM_ACCESS_TIMEOUT_CYCLES_OFFSET) =
        config->timing.access_timeout_cycles;
    *rs_psram_register(RS_PSRAM_CHIP_ERROR_OFFSET) = UINT32_C(0xF);
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = RS_PSRAM_INTERRUPT_ALL;

    control = RS_PSRAM_CTRL_ENABLE_MASK;
    if (config->memory_enable) {
        control |= RS_PSRAM_CTRL_MEMORY_ENABLE_MASK;
    }
    if (config->auto_initialize) {
        control |= RS_PSRAM_CTRL_AUTO_INIT_MASK;
    }
    if (config->wrap32) {
        control |= RS_PSRAM_CTRL_WRAP32_MASK;
    }
    *rs_psram_register(RS_PSRAM_CTRL_OFFSET) = control;
    return RS_OK;
}

rs_status_t rs_psram_initialize(rs_timeout_t timeout) {
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = RS_PSRAM_INTERRUPT_ALL;
    *rs_psram_register(RS_PSRAM_COMMAND_OFFSET) = RS_PSRAM_COMMAND_INIT_MASK;
    return rs_psram_wait_interrupt(RS_PSRAM_INTERRUPT_INIT_DONE, timeout);
}

rs_status_t rs_psram_recover(uint8_t chip, rs_timeout_t timeout) {
    if (!rs_psram_chip_valid(chip)) {
        return RS_EINVAL;
    }
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = RS_PSRAM_INTERRUPT_ALL;
    *rs_psram_register(RS_PSRAM_COMMAND_OFFSET) =
        RS_PSRAM_COMMAND_RECOVER_MASK | ((uint32_t)chip << RS_PSRAM_COMMAND_CHIP_SHIFT);
    return rs_psram_wait_interrupt(RS_PSRAM_INTERRUPT_INIT_DONE, timeout);
}

rs_status_t rs_psram_abort(void) {
    *rs_psram_register(RS_PSRAM_COMMAND_OFFSET) = RS_PSRAM_COMMAND_ABORT_MASK;
    return RS_OK;
}

rs_status_t rs_psram_get_status(rs_psram_status_t *status) {
    uint32_t controller_status;
    uint32_t chip_mode;
    uint32_t last_error;

    if (status == NULL) {
        return RS_EINVAL;
    }
    controller_status = *rs_psram_register(RS_PSRAM_STATUS_OFFSET);
    chip_mode = *rs_psram_register(RS_PSRAM_CHIP_MODE_OFFSET);
    last_error = *rs_psram_register(RS_PSRAM_LAST_ERROR_OFFSET);
    status->chip_present = (uint8_t)*rs_psram_register(RS_PSRAM_CHIP_PRESENT_OFFSET);
    status->chip_ready = (uint8_t)*rs_psram_register(RS_PSRAM_CHIP_READY_OFFSET);
    status->chip_qpi = (uint8_t)chip_mode;
    status->chip_wrap32 = (uint8_t)(chip_mode >> 4U);
    status->chip_error = (uint8_t)*rs_psram_register(RS_PSRAM_CHIP_ERROR_OFFSET);
    status->last_error = (rs_psram_error_t)(last_error & UINT32_C(0xF));
    status->last_error_chip = (uint8_t)((last_error >> 6U) & UINT32_C(0x3));
    status->last_error_address = *rs_psram_register(RS_PSRAM_LAST_ERROR_ADDR_OFFSET);
    status->init_busy = (controller_status & RS_PSRAM_STATUS_INIT_BUSY_MASK) != 0U;
    status->axi_busy = (controller_status & RS_PSRAM_STATUS_AXI_BUSY_MASK) != 0U;
    status->indirect_busy = (controller_status & RS_PSRAM_STATUS_INDIRECT_BUSY_MASK) != 0U;
    status->phy_busy = (controller_status & RS_PSRAM_STATUS_PHY_BUSY_MASK) != 0U;
    status->quiesced = (controller_status & RS_PSRAM_STATUS_QUIESCED_MASK) != 0U;
    status->ready = (controller_status & RS_PSRAM_STATUS_READY_MASK) != 0U;
    return RS_OK;
}

rs_status_t rs_psram_read_id(uint8_t chip, uint64_t *identifier) {
    uint32_t offset;
    uint64_t low;
    uint64_t high;

    if (!rs_psram_chip_valid(chip) || (identifier == NULL)) {
        return RS_EINVAL;
    }
    offset = RS_PSRAM_CHIP_ID_BASE_OFFSET + ((uint32_t)chip * UINT32_C(8));
    low = *rs_psram_register(offset);
    high = *rs_psram_register(offset + UINT32_C(4)) & UINT32_C(0xFFFF);
    *identifier = low | (high << 32U);
    return RS_OK;
}

rs_status_t rs_psram_indirect(const rs_psram_indirect_t *command, uint64_t *read_data,
                              rs_timeout_t timeout) {
    uint32_t control;
    rs_status_t status;

    if ((command == NULL) || !rs_psram_command_valid(command->command) ||
        !rs_psram_chip_valid(command->chip) || (command->length == 0U) || (command->length > 8U) ||
        (command->address >= RS_PSRAM_CHIP_SIZE)) {
        return RS_EINVAL;
    }
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = RS_PSRAM_INTERRUPT_ALL;
    *rs_psram_register(RS_PSRAM_INDIRECT_ADDR_OFFSET) = command->address;
    *rs_psram_register(RS_PSRAM_INDIRECT_WDATA_LO_OFFSET) = (uint32_t)command->write_data;
    *rs_psram_register(RS_PSRAM_INDIRECT_WDATA_HI_OFFSET) = (uint32_t)(command->write_data >> 32U);
    control = (uint32_t)command->command |
              ((uint32_t)command->chip << RS_PSRAM_INDIRECT_CHIP_SHIFT) |
              ((uint32_t)(command->length - 1U) << RS_PSRAM_INDIRECT_LENGTH_SHIFT) |
              RS_PSRAM_INDIRECT_START_MASK;
    *rs_psram_register(RS_PSRAM_INDIRECT_CTRL_OFFSET) = control;
    status = rs_psram_wait_interrupt(RS_PSRAM_INTERRUPT_INDIRECT_DONE, timeout);
    if (status != RS_OK) {
        return status;
    }
    if (read_data != NULL) {
        *read_data = (uint64_t)*rs_psram_register(RS_PSRAM_INDIRECT_RDATA_LO_OFFSET) |
                     ((uint64_t)*rs_psram_register(RS_PSRAM_INDIRECT_RDATA_HI_OFFSET) << 32U);
    }
    return RS_OK;
}

rs_status_t rs_psram_set_wrap(uint8_t chip, bool wrap32, rs_timeout_t timeout) {
    rs_psram_status_t status;
    rs_psram_indirect_t command = {
        .command = RS_PSRAM_COMMAND_TOGGLE_WRAP,
        .chip = chip,
        .length = 1U,
        .address = 0U,
        .write_data = 0U,
    };

    if (!rs_psram_chip_valid(chip) || (rs_psram_get_status(&status) != RS_OK)) {
        return RS_EINVAL;
    }
    if ((((status.chip_wrap32 >> chip) & UINT8_C(1)) != 0U) == wrap32) {
        return RS_OK;
    }
    return rs_psram_indirect(&command, NULL, timeout);
}

rs_status_t rs_psram_interrupt_enable(uint32_t mask) {
    if ((mask & ~RS_PSRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_psram_register(RS_PSRAM_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_psram_interrupt_clear(uint32_t mask) {
    if ((mask & ~RS_PSRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_psram_register(RS_PSRAM_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_psram_interrupt_test(uint32_t mask) {
    if ((mask & ~RS_PSRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_psram_register(RS_PSRAM_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

uint32_t xorshift32(uint32_t *state) {
    uint32_t value;

    if (state == NULL) {
        return 0U;
    }
    value = *state;
    value ^= value << 13U;
    value ^= value >> 17U;
    value ^= value << 5U;
    *state = value;
    return value;
}

rs_status_t rs_psram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                              rs_psram_test_failure_t *failure) {
    volatile uint32_t *memory;
    uint32_t words;
    uint32_t state;

    if ((address < RS_SOC_PSRAM_BASE) || (address > RS_SOC_PSRAM_END) ||
        ((address & (sizeof(uint32_t) - 1U)) != 0U) || (size < sizeof(uint32_t)) ||
        (size > (RS_SOC_PSRAM_END - (uint32_t)address + 1U)) || (word_limit == 0U)) {
        return RS_EINVAL;
    }
    memory = (volatile uint32_t *)address;
    words = size / sizeof(uint32_t);
    if (words > word_limit) {
        words = word_limit;
    }
    state = UINT32_C(0x13579BDF);
    for (uint32_t index = 0U; index < words; ++index) {
        memory[index] = xorshift32(&state);
    }
    state = UINT32_C(0x13579BDF);
    for (uint32_t index = 0U; index < words; ++index) {
        uint32_t expected = xorshift32(&state);
        uint32_t actual = memory[index];
        if (actual != expected) {
            if (failure != NULL) {
                failure->address = (uint32_t)address + (index * sizeof(uint32_t));
                failure->expected = expected;
                failure->actual = actual;
            }
            return RS_EIO;
        }
    }
    return RS_OK;
}

void ip_psram_boot(void) {
    rs_psram_status_t status;
    rs_psram_config_t config;
    uint32_t source_clock_hz;

    printf("[PSRAM] ESP-PSRAM64H: 4 x 8 MiB, QPI SDR\n");
    if ((rs_psram_get_status(&status) == RS_OK) && status.ready) {
        printf("[PSRAM] ready mask: %x\n", status.chip_ready);
    } else if ((rs_clock_get_active_hz(&source_clock_hz) != RS_OK) ||
               (rs_psram_timing_from_hz(source_clock_hz, source_clock_hz / 2U, &config.timing) !=
                RS_OK)) {
        printf("[PSRAM] timing calculation failed\n");
        return;
    } else {
        config.chip_enable = UINT8_C(0x0F);
        config.wrap32 = false;
        config.auto_initialize = false;
        config.memory_enable = true;
        if ((rs_psram_configure(&config) != RS_OK) ||
            (rs_psram_initialize(RS_TIMEOUT_DEFAULT) != RS_OK) ||
            (rs_psram_get_status(&status) != RS_OK)) {
            printf("[PSRAM] initialization failed\n");
            return;
        }
        printf("[PSRAM] ready mask: %x\n", status.chip_ready);
    }

    for (uint8_t chip = 0U; chip < (uint8_t)RS_PSRAM_CHIP_COUNT; ++chip) {
        uint64_t identifier;
        if (rs_psram_read_id(chip, &identifier) == RS_OK) {
            printf("[PSRAM] chip %d ID: %x%08x\n", chip, (uint32_t)(identifier >> 32U),
                   (uint32_t)identifier);
        }
    }
}

void ip_psram_selftest(uint32_t address, uint32_t size) {
    rs_psram_test_failure_t failure;
    rs_status_t status;

    status = rs_psram_selftest((uintptr_t)address, size, 8192U, &failure);
    if (status == RS_OK) {
        printf("[PSRAM] self test passed\n");
    } else if (status == RS_EIO) {
        printf("[PSRAM] self test failed at %x: expected %x, actual %x\n", failure.address,
               failure.expected, failure.actual);
    } else {
        printf("[PSRAM] self test configuration invalid\n");
    }
}
