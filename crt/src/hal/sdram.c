#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/sdram.h>

#define RS_SDRAM_CLKDIV_OFFSET              UINT32_C(0x000)
#define RS_SDRAM_CTRL_OFFSET                UINT32_C(0x004)
#define RS_SDRAM_COMMAND_OFFSET             UINT32_C(0x008)
#define RS_SDRAM_STATUS_OFFSET              UINT32_C(0x00C)
#define RS_SDRAM_MODE_OFFSET                UINT32_C(0x010)
#define RS_SDRAM_TIMING0_OFFSET             UINT32_C(0x014)
#define RS_SDRAM_TIMING1_OFFSET             UINT32_C(0x018)
#define RS_SDRAM_TIMING2_OFFSET             UINT32_C(0x01C)
#define RS_SDRAM_REFRESH_OFFSET             UINT32_C(0x020)
#define RS_SDRAM_POWERUP_OFFSET             UINT32_C(0x024)
#define RS_SDRAM_LAST_ERROR_OFFSET          UINT32_C(0x028)
#define RS_SDRAM_LAST_ERROR_ADDR_OFFSET     UINT32_C(0x02C)
#define RS_SDRAM_INTR_STATE_OFFSET          UINT32_C(0x080)
#define RS_SDRAM_INTR_ENABLE_OFFSET         UINT32_C(0x084)
#define RS_SDRAM_INTR_STATUS_OFFSET         UINT32_C(0x088)
#define RS_SDRAM_INTR_TEST_OFFSET           UINT32_C(0x08C)
#define RS_SDRAM_PERF_CTRL_OFFSET           UINT32_C(0x090)
#define RS_SDRAM_PERF_READ_BYTES_OFFSET     UINT32_C(0x094)
#define RS_SDRAM_PERF_WRITE_BYTES_OFFSET    UINT32_C(0x098)
#define RS_SDRAM_PERF_ROW_HIT_OFFSET        UINT32_C(0x09C)
#define RS_SDRAM_PERF_ROW_MISS_OFFSET       UINT32_C(0x0A0)
#define RS_SDRAM_PERF_REFRESH_STALL_OFFSET  UINT32_C(0x0A4)
#define RS_SDRAM_PERF_BANK_CONFLICT_OFFSET  UINT32_C(0x0A8)
#define RS_SDRAM_IP_VERSION_OFFSET          UINT32_C(0x0F8)
#define RS_SDRAM_CAPABILITY_OFFSET          UINT32_C(0x0FC)

#define RS_SDRAM_CTRL_ENABLE_MASK           UINT32_C(0x00000001)
#define RS_SDRAM_CTRL_MEMORY_ENABLE_MASK    UINT32_C(0x00000002)
#define RS_SDRAM_CTRL_AUTO_INIT_MASK        UINT32_C(0x00000004)
#define RS_SDRAM_CTRL_OPEN_PAGE_MASK        UINT32_C(0x00000008)
#define RS_SDRAM_COMMAND_INIT_MASK          UINT32_C(0x00000001)
#define RS_SDRAM_COMMAND_REINIT_MASK        UINT32_C(0x00000002)
#define RS_SDRAM_COMMAND_PRECHARGE_ALL_MASK UINT32_C(0x00000004)
#define RS_SDRAM_COMMAND_REFRESH_MASK       UINT32_C(0x00000008)
#define RS_SDRAM_STATUS_INIT_BUSY_MASK      UINT32_C(0x00000001)
#define RS_SDRAM_STATUS_AXI_BUSY_MASK       UINT32_C(0x00000002)
#define RS_SDRAM_STATUS_PHY_BUSY_MASK       UINT32_C(0x00000004)
#define RS_SDRAM_STATUS_READY_MASK          UINT32_C(0x00000008)
#define RS_SDRAM_STATUS_ERROR_MASK          UINT32_C(0x00000010)
#define RS_SDRAM_STATUS_BUSY_MASK           UINT32_C(0x00000007)
#define RS_SDRAM_MODE_WR_BURST_MASK         UINT32_C(0x00000010)
#define RS_SDRAM_MODE_BL_SHIFT              2U

static volatile uint32_t *rs_sdram_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_SDRAM_BASE + offset);
}

static bool rs_sdram_timing_valid(const rs_sdram_timing_t *timing) {
    return (timing != NULL) && (timing->trp_cycles != 0U) && (timing->trcd_cycles != 0U) &&
           (timing->tras_cycles != 0U) && (timing->trc_cycles != 0U) &&
           (timing->twr_cycles != 0U) && (timing->trfc_cycles != 0U) &&
           (timing->trrd_cycles != 0U) && (timing->twtr_cycles != 0U) &&
           (timing->trtp_cycles != 0U) && (timing->tmrd_cycles != 0U) &&
           (timing->txsr_cycles != 0U) && (timing->trefi_cycles != 0U) &&
           (timing->powerup_cycles != 0U);
}

static bool rs_sdram_config_valid(const rs_sdram_config_t *config) {
    return (config != NULL) && rs_sdram_timing_valid(&config->timing) && (config->clkdiv <= 3U) &&
           ((config->cas_latency == RS_SDRAM_CAS_2) || (config->cas_latency == RS_SDRAM_CAS_3)) &&
           ((config->burst_length == RS_SDRAM_BURST_2) ||
            (config->burst_length == RS_SDRAM_BURST_8)) &&
           (config->refresh_credit_max > 0U) && (config->refresh_credit_max <= 15U);
}

static rs_status_t rs_sdram_wait_interrupt(uint32_t interrupt, rs_timeout_t timeout) {
    uint32_t interrupt_state;
    rs_status_t status;

    status =
        rs_wait_mask(rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET), interrupt, interrupt, timeout);
    if (status != RS_OK) {
        return status;
    }
    interrupt_state = *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET);
    *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET) = interrupt_state & RS_SDRAM_INTERRUPT_ALL;
    if ((interrupt_state & RS_SDRAM_INTERRUPT_ERROR) != 0U) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_sdram_configure(const rs_sdram_config_t *config) {
    uint32_t status;
    uint32_t control;
    uint32_t mode;
    uint32_t burst_code;

    if (!rs_sdram_config_valid(config)) {
        return RS_EINVAL;
    }
    status = *rs_sdram_register(RS_SDRAM_STATUS_OFFSET);
    if ((status & RS_SDRAM_STATUS_BUSY_MASK) != 0U) {
        return RS_EIO;
    }

    *rs_sdram_register(RS_SDRAM_CTRL_OFFSET) = 0U;
    *rs_sdram_register(RS_SDRAM_CLKDIV_OFFSET) = config->clkdiv;
    *rs_sdram_register(RS_SDRAM_TIMING0_OFFSET) = ((uint32_t)config->timing.trp_cycles) |
                                                  ((uint32_t)config->timing.trcd_cycles << 8U) |
                                                  ((uint32_t)config->timing.tras_cycles << 16U) |
                                                  ((uint32_t)config->timing.trc_cycles << 24U);
    *rs_sdram_register(RS_SDRAM_TIMING1_OFFSET) = ((uint32_t)config->timing.twr_cycles) |
                                                  ((uint32_t)config->timing.trfc_cycles << 8U) |
                                                  ((uint32_t)config->timing.trrd_cycles << 16U) |
                                                  ((uint32_t)config->timing.twtr_cycles << 24U);
    *rs_sdram_register(RS_SDRAM_TIMING2_OFFSET) = ((uint32_t)config->timing.trtp_cycles) |
                                                  ((uint32_t)config->timing.tmrd_cycles << 8U) |
                                                  ((uint32_t)config->timing.txsr_cycles << 16U);
    *rs_sdram_register(RS_SDRAM_REFRESH_OFFSET) =
        ((uint32_t)config->timing.trefi_cycles) | ((uint32_t)config->refresh_credit_max << 16U);
    *rs_sdram_register(RS_SDRAM_POWERUP_OFFSET) = config->timing.powerup_cycles;
    burst_code = (config->burst_length == RS_SDRAM_BURST_8) ? UINT32_C(1) : UINT32_C(0);
    mode = (uint32_t)config->cas_latency | (burst_code << RS_SDRAM_MODE_BL_SHIFT);
    if (config->write_burst) {
        mode |= RS_SDRAM_MODE_WR_BURST_MASK;
    }
    *rs_sdram_register(RS_SDRAM_MODE_OFFSET) = mode;
    *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET) = RS_SDRAM_INTERRUPT_ALL;

    control = RS_SDRAM_CTRL_ENABLE_MASK;
    if (config->memory_enable) {
        control |= RS_SDRAM_CTRL_MEMORY_ENABLE_MASK;
    }
    if (config->auto_initialize) {
        control |= RS_SDRAM_CTRL_AUTO_INIT_MASK;
    }
    if (config->open_page) {
        control |= RS_SDRAM_CTRL_OPEN_PAGE_MASK;
    }
    *rs_sdram_register(RS_SDRAM_CTRL_OFFSET) = control;
    return RS_OK;
}

rs_status_t rs_sdram_initialize(rs_timeout_t timeout) {
    *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET) = RS_SDRAM_INTERRUPT_ALL;
    *rs_sdram_register(RS_SDRAM_COMMAND_OFFSET) = RS_SDRAM_COMMAND_INIT_MASK;
    return rs_sdram_wait_interrupt(RS_SDRAM_INTERRUPT_INIT_DONE, timeout);
}

rs_status_t rs_sdram_reinitialize(rs_timeout_t timeout) {
    *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET) = RS_SDRAM_INTERRUPT_ALL;
    *rs_sdram_register(RS_SDRAM_COMMAND_OFFSET) = RS_SDRAM_COMMAND_REINIT_MASK;
    return rs_sdram_wait_interrupt(RS_SDRAM_INTERRUPT_INIT_DONE, timeout);
}

rs_status_t rs_sdram_precharge_all(void) {
    *rs_sdram_register(RS_SDRAM_COMMAND_OFFSET) = RS_SDRAM_COMMAND_PRECHARGE_ALL_MASK;
    return RS_OK;
}

rs_status_t rs_sdram_refresh(void) {
    *rs_sdram_register(RS_SDRAM_COMMAND_OFFSET) = RS_SDRAM_COMMAND_REFRESH_MASK;
    return RS_OK;
}

rs_status_t rs_sdram_get_status(rs_sdram_status_t *status) {
    uint32_t controller_status;

    if (status == NULL) {
        return RS_EINVAL;
    }
    controller_status = *rs_sdram_register(RS_SDRAM_STATUS_OFFSET);
    status->last_error =
        (rs_sdram_error_t)(*rs_sdram_register(RS_SDRAM_LAST_ERROR_OFFSET) & UINT32_C(0xF));
    status->last_error_address = *rs_sdram_register(RS_SDRAM_LAST_ERROR_ADDR_OFFSET);
    status->init_busy = (controller_status & RS_SDRAM_STATUS_INIT_BUSY_MASK) != 0U;
    status->axi_busy = (controller_status & RS_SDRAM_STATUS_AXI_BUSY_MASK) != 0U;
    status->phy_busy = (controller_status & RS_SDRAM_STATUS_PHY_BUSY_MASK) != 0U;
    status->ready = (controller_status & RS_SDRAM_STATUS_READY_MASK) != 0U;
    status->error = (controller_status & RS_SDRAM_STATUS_ERROR_MASK) != 0U;
    return RS_OK;
}

rs_status_t rs_sdram_interrupt_enable(uint32_t mask) {
    if ((mask & ~RS_SDRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_sdram_register(RS_SDRAM_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_sdram_interrupt_clear(uint32_t mask) {
    if ((mask & ~RS_SDRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_sdram_register(RS_SDRAM_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_sdram_interrupt_test(uint32_t mask) {
    if ((mask & ~RS_SDRAM_INTERRUPT_ALL) != 0U) {
        return RS_EINVAL;
    }
    *rs_sdram_register(RS_SDRAM_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_sdram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                              rs_sdram_test_failure_t *failure) {
    volatile uint32_t *memory;
    uint32_t words;
    uint32_t pattern;

    if ((address < RS_SOC_SDRAM_BASE) || (address > RS_SOC_SDRAM_END) ||
        ((address & (sizeof(uint32_t) - 1U)) != 0U) || (size < sizeof(uint32_t)) ||
        (size > (RS_SOC_SDRAM_END - (uint32_t)address + 1U)) || (word_limit == 0U)) {
        return RS_EINVAL;
    }
    memory = (volatile uint32_t *)address;
    words = size / sizeof(uint32_t);
    if (words > word_limit) {
        words = word_limit;
    }
    pattern = UINT32_C(0xA5A55A5A);
    for (uint32_t index = 0U; index < words; ++index) {
        memory[index] = pattern + index;
    }
    for (uint32_t index = 0U; index < words; ++index) {
        uint32_t expected = pattern + index;
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
