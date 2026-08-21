#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/sysctrl.h>

#define RS_SYSCTRL_CORESEL_OFFSET                  RS_SOC_SYSCTRL_CORESEL_OFFSET
#define RS_SYSCTRL_IPSEL_OFFSET                    RS_SOC_SYSCTRL_IPSEL_OFFSET
#define RS_SYSCTRL_PLL_CFG_OFFSET                  RS_SOC_SYSCTRL_PLL_CFG_OFFSET
#define RS_SYSCTRL_PLL_CMD_OFFSET                  RS_SOC_SYSCTRL_PLL_CMD_OFFSET
#define RS_SYSCTRL_FAULT_STATUS_OFFSET             RS_SOC_SYSCTRL_FAULT_STATUS_OFFSET
#define RS_SYSCTRL_FAULT_ADDR_OFFSET               RS_SOC_SYSCTRL_FAULT_ADDR_OFFSET
#define RS_SYSCTRL_FAULT_COUNT_OFFSET              RS_SOC_SYSCTRL_FAULT_COUNT_OFFSET
#define RS_SYSCTRL_PLL_STATUS_OFFSET               RS_SOC_SYSCTRL_PLL_STATUS_OFFSET
#define RS_SYSCTRL_USER_CORE_RESET_OFFSET          RS_SOC_SYSCTRL_USER_CORE_RESET_OFFSET
#define RS_SYSCTRL_USER_CORE_STATUS_OFFSET         RS_SOC_SYSCTRL_USER_CORE_STATUS_OFFSET
#define RS_SYSCTRL_FAULT_MASTER_OFFSET             RS_SOC_SYSCTRL_FAULT_MASTER_OFFSET
#define RS_SYSCTRL_FAULT_DETAIL_OFFSET             RS_SOC_SYSCTRL_FAULT_DETAIL_OFFSET
#define RS_SYSCTRL_PERF_CTRL_OFFSET                RS_SOC_SYSCTRL_PERF_CTRL_OFFSET
#define RS_SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET        RS_SOC_SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET        RS_SOC_SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_USER_WAIT_LO_OFFSET        RS_SOC_SYSCTRL_PERF_USER_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_USER_WAIT_HI_OFFSET        RS_SOC_SYSCTRL_PERF_USER_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_DMA_WAIT_LO_OFFSET         RS_SOC_SYSCTRL_PERF_DMA_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_DMA_WAIT_HI_OFFSET         RS_SOC_SYSCTRL_PERF_DMA_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_SDIO0_WAIT_LO_OFFSET       RS_SOC_SYSCTRL_PERF_SDIO0_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_SDIO0_WAIT_HI_OFFSET       RS_SOC_SYSCTRL_PERF_SDIO0_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_SDIO1_WAIT_LO_OFFSET       RS_SOC_SYSCTRL_PERF_SDIO1_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_SDIO1_WAIT_HI_OFFSET       RS_SOC_SYSCTRL_PERF_SDIO1_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_APB4_PERIPH_WAIT_LO_OFFSET RS_SOC_SYSCTRL_PERF_APB4_PERIPH_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_APB4_PERIPH_WAIT_HI_OFFSET RS_SOC_SYSCTRL_PERF_APB4_PERIPH_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT_LO_OFFSET RS_SOC_SYSCTRL_PERF_APB4_SYSTEM_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT_HI_OFFSET RS_SOC_SYSCTRL_PERF_APB4_SYSTEM_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET       RS_SOC_SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET       RS_SOC_SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET       RS_SOC_SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET       RS_SOC_SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET
#define RS_SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET       RS_SOC_SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET
#define RS_SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET       RS_SOC_SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET
#define RS_SYSCTRL_TEST_STATUS_OFFSET              RS_SOC_SYSCTRL_TEST_STATUS_OFFSET
#define RS_SYSCTRL_RTC_WAKE_STATUS_OFFSET          RS_SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET

#define RS_SYSCTRL_PLL_CMD_APPLY                   UINT32_C(0x00000001)
#define RS_SYSCTRL_PLL_CMD_CLEAR_ERROR             UINT32_C(0x00000002)
#define RS_SYSCTRL_FAULT_PENDING                   UINT32_C(0x00000001)
#define RS_SYSCTRL_PERF_ENABLE                     UINT32_C(0x00000001)
#define RS_SYSCTRL_PERF_CLEAR                      UINT32_C(0x00000002)
#define RS_SYSCTRL_PERF_SNAPSHOT                   UINT32_C(0x00000004)
#define RS_SYSCTRL_PERF_CONTROL_MASK               UINT32_C(0x00000007)
#define RS_SYSCTRL_TEST_STATUS_VALID               UINT32_C(0x80000000)
#define RS_SYSCTRL_TEST_STATUS_PASS                UINT32_C(0x00000001)
#define RS_SYSCTRL_TEST_STATUS_CODE_SHIFT          8U
#define RS_SYSCTRL_USER_CORE_SEL_MASK              UINT32_C(0x0000001F)
#define RS_SYSCTRL_USER_CORE_BUS_ENABLED           UINT32_C(0x00000100)
#define RS_SYSCTRL_USER_CORE_BUS_IDLE              UINT32_C(0x00000200)
#define RS_SYSCTRL_USER_CORE_DRAINING              UINT32_C(0x00000400)
#define RS_SYSCTRL_USER_CORE_CONFIG_ERROR          UINT32_C(0x00000800)
#define RS_SYSCTRL_PLL_SELECTION_MASK              UINT32_C(0x00000007)
#define RS_SYSCTRL_PLL_ACTIVE_VALID                UINT32_C(0x00000008)
#define RS_SYSCTRL_PLL_BUSY                        UINT32_C(0x00000010)
#define RS_SYSCTRL_PLL_ERROR                       UINT32_C(0x00000020)
#define RS_SYSCTRL_PLL_ERROR_SHIFT                 6U
#define RS_SYSCTRL_PLL_SAFE_CLOCK                  UINT32_C(0x00000100)
#define RS_SYSCTRL_PLL_LOCKED                      UINT32_C(0x00000200)
#define RS_SYSCTRL_PLL_CAPABLE                     UINT32_C(0x00000400)
#define RS_SYSCTRL_RTC_WAKE_LIVE                   UINT32_C(0x00000001)
#define RS_SYSCTRL_RTC_WAKE_SEEN                   UINT32_C(0x00000002)

static volatile uint32_t *rs_sysctrl_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_APB4_SYSCTRL_BASE + (uintptr_t)offset);
}

static rs_status_t rs_sysctrl_perf_offsets(rs_sysctrl_perf_counter_t counter, uint32_t *low_offset,
                                           uint32_t *high_offset) {
    if ((low_offset == NULL) || (high_offset == NULL)) {
        return RS_EINVAL;
    }

    switch (counter) {
    case RS_SYSCTRL_PERF_MGMT_WAIT:
        *low_offset = RS_SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_USER_WAIT:
        *low_offset = RS_SYSCTRL_PERF_USER_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_USER_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_DMA_WAIT:
        *low_offset = RS_SYSCTRL_PERF_DMA_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_DMA_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_SDIO0_WAIT:
        *low_offset = RS_SYSCTRL_PERF_SDIO0_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_SDIO0_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_SDIO1_WAIT:
        *low_offset = RS_SYSCTRL_PERF_SDIO1_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_SDIO1_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_APB4_PERIPH_WAIT:
        *low_offset = RS_SYSCTRL_PERF_APB4_PERIPH_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_APB4_PERIPH_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT:
        *low_offset = RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_SDRAM_WAIT:
        *low_offset = RS_SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_PSRAM_WAIT:
        *low_offset = RS_SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET;
        break;
    case RS_SYSCTRL_PERF_FLASH_WAIT:
        *low_offset = RS_SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET;
        *high_offset = RS_SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_sysctrl_get_core_select(uint8_t *core_id) {
    if (core_id == NULL) {
        return RS_EINVAL;
    }
    *core_id = (uint8_t)*rs_sysctrl_register(RS_SYSCTRL_CORESEL_OFFSET);
    return RS_OK;
}

rs_status_t rs_sysctrl_set_core_select(uint8_t core_id) {
    if ((uint32_t)core_id >= RS_SOC_USER_CORE_COUNT) {
        return RS_EINVAL;
    }
    *rs_sysctrl_register(RS_SYSCTRL_CORESEL_OFFSET) = (uint32_t)core_id;
    return RS_OK;
}

rs_status_t rs_sysctrl_get_ip_select(uint8_t *ip_id) {
    if (ip_id == NULL) {
        return RS_EINVAL;
    }
    *ip_id = (uint8_t)*rs_sysctrl_register(RS_SYSCTRL_IPSEL_OFFSET);
    return RS_OK;
}

rs_status_t rs_sysctrl_set_ip_select(uint8_t ip_id) {
    if ((uint32_t)ip_id > RS_SOC_USER_IP_COUNT) {
        return RS_EINVAL;
    }
    *rs_sysctrl_register(RS_SYSCTRL_IPSEL_OFFSET) = (uint32_t)ip_id;
    return RS_OK;
}

rs_status_t rs_sysctrl_get_user_core_status(rs_sysctrl_user_core_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = *rs_sysctrl_register(RS_SYSCTRL_USER_CORE_STATUS_OFFSET);
    status->reset_mask = *rs_sysctrl_register(RS_SYSCTRL_USER_CORE_RESET_OFFSET);
    status->selected_core = (uint8_t)(value & RS_SYSCTRL_USER_CORE_SEL_MASK);
    status->bus_enabled = (value & RS_SYSCTRL_USER_CORE_BUS_ENABLED) != 0U;
    status->bus_idle = (value & RS_SYSCTRL_USER_CORE_BUS_IDLE) != 0U;
    status->draining = (value & RS_SYSCTRL_USER_CORE_DRAINING) != 0U;
    status->config_error = (value & RS_SYSCTRL_USER_CORE_CONFIG_ERROR) != 0U;
    return RS_OK;
}

rs_status_t rs_sysctrl_set_user_core_reset(uint32_t reset_mask) {
    *rs_sysctrl_register(RS_SYSCTRL_USER_CORE_RESET_OFFSET) = reset_mask;
    return RS_OK;
}

rs_status_t rs_sysctrl_clear_user_core_config_error(void) {
    *rs_sysctrl_register(RS_SYSCTRL_USER_CORE_STATUS_OFFSET) = RS_SYSCTRL_USER_CORE_CONFIG_ERROR;
    return RS_OK;
}

rs_status_t rs_sysctrl_get_pll_config(uint8_t *selection) {
    if (selection == NULL) {
        return RS_EINVAL;
    }
    *selection =
        (uint8_t)(*rs_sysctrl_register(RS_SYSCTRL_PLL_CFG_OFFSET) & RS_SYSCTRL_PLL_SELECTION_MASK);
    return RS_OK;
}

rs_status_t rs_sysctrl_set_pll_config(uint8_t selection) {
    if (((uint32_t)selection & ~RS_SYSCTRL_PLL_SELECTION_MASK) != 0U) {
        return RS_EINVAL;
    }
    *rs_sysctrl_register(RS_SYSCTRL_PLL_CFG_OFFSET) = (uint32_t)selection;
    return RS_OK;
}

rs_status_t rs_sysctrl_apply_pll_config(void) {
    *rs_sysctrl_register(RS_SYSCTRL_PLL_CMD_OFFSET) = RS_SYSCTRL_PLL_CMD_APPLY;
    return RS_OK;
}

rs_status_t rs_sysctrl_clear_pll_error(void) {
    *rs_sysctrl_register(RS_SYSCTRL_PLL_CMD_OFFSET) = RS_SYSCTRL_PLL_CMD_CLEAR_ERROR;
    return RS_OK;
}

rs_status_t rs_sysctrl_get_pll_status(rs_sysctrl_pll_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = *rs_sysctrl_register(RS_SYSCTRL_PLL_STATUS_OFFSET);
    status->active_selection = value & RS_SYSCTRL_PLL_SELECTION_MASK;
    status->error_reason = (uint8_t)((value >> RS_SYSCTRL_PLL_ERROR_SHIFT) & UINT32_C(0x3));
    status->active_valid = (value & RS_SYSCTRL_PLL_ACTIVE_VALID) != 0U;
    status->busy = (value & RS_SYSCTRL_PLL_BUSY) != 0U;
    status->error = (value & RS_SYSCTRL_PLL_ERROR) != 0U;
    status->safe_clock = (value & RS_SYSCTRL_PLL_SAFE_CLOCK) != 0U;
    status->pll_locked = (value & RS_SYSCTRL_PLL_LOCKED) != 0U;
    status->capable = (value & RS_SYSCTRL_PLL_CAPABLE) != 0U;
    return RS_OK;
}

rs_status_t rs_sysctrl_get_fault_status(rs_sysctrl_fault_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = *rs_sysctrl_register(RS_SYSCTRL_FAULT_STATUS_OFFSET);
    status->address = *rs_sysctrl_register(RS_SYSCTRL_FAULT_ADDR_OFFSET);
    status->count = *rs_sysctrl_register(RS_SYSCTRL_FAULT_COUNT_OFFSET);
    status->master = (uint8_t)*rs_sysctrl_register(RS_SYSCTRL_FAULT_MASTER_OFFSET);
    status->detail = (uint8_t)*rs_sysctrl_register(RS_SYSCTRL_FAULT_DETAIL_OFFSET);
    status->pending = (value & RS_SYSCTRL_FAULT_PENDING) != 0U;
    status->write = (value & UINT32_C(0x00000002)) != 0U;
    status->reason = (uint8_t)((value >> 2U) & UINT32_C(0x7));
    return RS_OK;
}

rs_status_t rs_sysctrl_clear_fault(void) {
    *rs_sysctrl_register(RS_SYSCTRL_FAULT_STATUS_OFFSET) = RS_SYSCTRL_FAULT_PENDING;
    return RS_OK;
}

rs_status_t rs_sysctrl_set_perf_control(bool enable, bool clear, bool snapshot) {
    uint32_t control = 0U;

    if (enable) {
        control |= RS_SYSCTRL_PERF_ENABLE;
    }
    if (clear) {
        control |= RS_SYSCTRL_PERF_CLEAR;
    }
    if (snapshot) {
        control |= RS_SYSCTRL_PERF_SNAPSHOT;
    }
    *rs_sysctrl_register(RS_SYSCTRL_PERF_CTRL_OFFSET) = control & RS_SYSCTRL_PERF_CONTROL_MASK;
    return RS_OK;
}

rs_status_t rs_sysctrl_read_perf_counter(rs_sysctrl_perf_counter_t counter, uint64_t *value) {
    uint32_t low_offset;
    uint32_t high_offset;

    if (value == NULL) {
        return RS_EINVAL;
    }
    if (rs_sysctrl_perf_offsets(counter, &low_offset, &high_offset) != RS_OK) {
        return RS_EINVAL;
    }
    *value = ((uint64_t)*rs_sysctrl_register(high_offset) << 32U) |
             (uint64_t)*rs_sysctrl_register(low_offset);
    return RS_OK;
}

void rs_sysctrl_write_test_status(bool pass, uint8_t code) {
    uint32_t value =
        RS_SYSCTRL_TEST_STATUS_VALID | ((uint32_t)code << RS_SYSCTRL_TEST_STATUS_CODE_SHIFT);

    if (pass) {
        value |= RS_SYSCTRL_TEST_STATUS_PASS;
    }
    *rs_sysctrl_register(RS_SYSCTRL_TEST_STATUS_OFFSET) = value;
}

rs_status_t rs_sysctrl_get_test_status(bool *done, bool *pass, uint8_t *code) {
    uint32_t value;

    if ((done == NULL) || (pass == NULL) || (code == NULL)) {
        return RS_EINVAL;
    }
    value = *rs_sysctrl_register(RS_SYSCTRL_TEST_STATUS_OFFSET);
    *done = (value & RS_SYSCTRL_TEST_STATUS_VALID) != 0U;
    *pass = (value & RS_SYSCTRL_TEST_STATUS_PASS) != 0U;
    *code = (uint8_t)(value >> RS_SYSCTRL_TEST_STATUS_CODE_SHIFT);
    return RS_OK;
}

rs_status_t rs_sysctrl_get_rtc_wake_status(bool *live, bool *seen) {
    uint32_t value;

    if ((live == NULL) || (seen == NULL)) {
        return RS_EINVAL;
    }
    value = *rs_sysctrl_register(RS_SYSCTRL_RTC_WAKE_STATUS_OFFSET);
    *live = (value & RS_SYSCTRL_RTC_WAKE_LIVE) != 0U;
    *seen = (value & RS_SYSCTRL_RTC_WAKE_SEEN) != 0U;
    return RS_OK;
}

rs_status_t rs_sysctrl_clear_rtc_wake(void) {
    *rs_sysctrl_register(RS_SYSCTRL_RTC_WAKE_STATUS_OFFSET) = RS_SYSCTRL_RTC_WAKE_SEEN;
    return RS_OK;
}
