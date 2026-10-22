#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/timer.h>
#include <pwm_regs.h>

/* Current Tiny includes DVP (target 14) and SPI (RCU target 16); the other
 * expansion targets stay absent. */
#define RS_P7_EXPECTED_TARGET_CAPABILITY UINT32_C(0x00017FFF)

/* Short P7 firmware: execute in real main SRAM and use real SYSCTRL/APB
 * crossings. The full peripheral firmware remains a separate regression. */
static volatile uint32_t rs_p7_words[128];
static _Alignas(64) uint32_t rs_p7_source[1024];
static _Alignas(64) uint32_t rs_p7_destination[1024];
static volatile uint32_t rs_p7_retained __attribute__((section(".noinit.rs_p7")));

static bool rs_p7_peripheral_rate(uint32_t pclk_hz) {
    const rs_timer_config_t config = {.mode = RS_TIMER_MODE_FREE_RUNNING,
                                      .direction = RS_TIMER_DIRECTION_UP};
    const volatile uint32_t *pwm_rate =
        (const volatile uint32_t *)(RS_SOC_APB4_PWM_BASE + PWM_CLOCK_HZ_OFFSET);
    uint32_t first, last;
    uint64_t start, end;
    uint64_t expected;
    rs_timeout_t budget = RS_TIMEOUT_DEFAULT;
    if (*pwm_rate != pclk_hz || rs_timer_configure(RS_TIMER_0, &config) != RS_OK ||
        rs_timer_start(RS_TIMER_0) != RS_OK || rs_clint_get_time(&start) != RS_OK ||
        rs_timer_get_value(RS_TIMER_0, &first) != RS_OK) {
        return false;
    }
    do {
        if (rs_clint_get_time(&end) != RS_OK || budget-- == 0U) {
            return false;
        }
    } while (end - start < 200U);
    if (rs_timer_get_value(RS_TIMER_0, &last) != RS_OK || rs_timer_stop(RS_TIMER_0) != RS_OK) {
        return false;
    }
    expected = (end - start) * (pclk_hz / 1000000U);
    /* Independent CLINT reference; allow the bounded APB/software read skew.
     * A wrong /2 or /4 domain cannot fit this +/-25% interval. */
    return (uint64_t)(last - first) > expected * 3U / 4U &&
           (uint64_t)(last - first) < expected * 5U / 4U;
}

static bool rs_p7_sleep(void) {
    rs_dma_session_t session;
    rs_dma_config_t config = {.kind = RS_DMA_KIND_MM_TO_MM,
                              .request = RS_DMA_REQUEST_SOFTWARE,
                              .source = (uintptr_t)rs_p7_source,
                              .destination = (uintptr_t)rs_p7_destination,
                              .byte_count = sizeof(rs_p7_source),
                              .width = RS_DMA_WIDTH_32,
                              .source_increment = true,
                              .destination_increment = true,
                              .burst_beats = 16U};
    uint64_t now;
    uint32_t index;
    __disable_irq();
    for (index = 0U; index < 1024U; index++) {
        rs_p7_source[index] = index ^ UINT32_C(0x13572468);
        rs_p7_destination[index] = 0U;
    }
    if (rs_tiny_rcu_apply_gate(1U, RS_TIMEOUT_DEFAULT) != RS_OK ||
        rs_dma_session_acquire(&session, RS_DMA_CHANNEL_BULK) != RS_OK ||
        rs_dma_session_configure(&session, &config) != RS_OK || rs_clint_get_time(&now) != RS_OK ||
        rs_clint_set_compare(0U, now + 3000U) != RS_OK || rs_dma_session_start(&session) != RS_OK) {
        return false;
    }
    __RV_CSR_SET(CSR_MIE, MIE_MTIE);
    __WFI();
    __RV_CSR_CLEAR(CSR_MIE, MIE_MTIE);
    if (rs_clint_set_compare(0U, UINT64_MAX) != RS_OK ||
        rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK ||
        rs_dma_session_release(&session) != RS_OK ||
        rs_tiny_rcu_apply_gate(0U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        return false;
    }
    for (index = 0U; index < 1024U; index++) {
        if (rs_p7_destination[index] != rs_p7_source[index]) {
            return false;
        }
    }
    return true;
}

static bool rs_p7_profile(rs_tiny_rcu_profile_t profile, uint32_t sys_hz, uint32_t mem_hz,
                          uint32_t pclk_hz) {
    rs_tiny_rcu_snapshot_t snapshot;
    uint32_t index;
    uint64_t before, after;

    if (rs_clint_get_time(&before) != RS_OK ||
        rs_tiny_rcu_request_profile(profile, RS_TIMEOUT_DEFAULT) != RS_OK ||
        rs_clint_get_time(&after) != RS_OK || after <= before) {
        return false;
    }
    if (rs_tiny_rcu_get_snapshot(&snapshot) != RS_OK || snapshot.current_profile != profile ||
        snapshot.sys_hz != sys_hz || snapshot.mem_hz != mem_hz || snapshot.pclk_hz != pclk_hz) {
        return false;
    }
    for (index = 0U; index < 128U; index++) {
        if (rs_p7_words[index] != (UINT32_C(0xABCDEF00) ^ index)) {
            return false;
        }
    }
    return rs_p7_peripheral_rate(pclk_hz);
}

int main(void) {
    rs_tiny_rcu_snapshot_t snapshot;
    uint32_t index;
    uint8_t code = 0U;

    if (rs_tiny_rcu_get_snapshot(&snapshot) == RS_OK && (snapshot.reset_cause & 2U) != 0U) {
        code = (rs_p7_retained == UINT32_C(0x7037CAFE) && snapshot.current_profile == 0U &&
                snapshot.sys_hz == 24000000U && snapshot.gate_status == 0U)
                   ? 0U
                   : 11U;
        rs_sysctrl_write_test_status(code == 0U, code);
        for (;;) {
        }
    }

    for (index = 0U; index < 128U; index++) {
        rs_p7_words[index] = UINT32_C(0xABCDEF00) ^ index;
    }
    if (rs_tiny_rcu_get_snapshot(&snapshot) != RS_OK || snapshot.sys_hz != 24000000U ||
        snapshot.target_capability != RS_P7_EXPECTED_TARGET_CAPABILITY) {
        code = 1U;
    } else if ((snapshot.capability & UINT32_C(0xC)) == UINT32_C(0xC)) {
        if (!rs_p7_profile(RS_TINY_RCU_PROFILE_PLL192, 192000000U, 96000000U, 48000000U)) {
            code = 2U;
        } else if (!rs_p7_profile(RS_TINY_RCU_PROFILE_PLL240, 240000000U, 120000000U, 60000000U)) {
            code = 3U;
        }
    } else if (!rs_p7_profile(RS_TINY_RCU_PROFILE_XIN, snapshot.xin_hz, snapshot.xin_hz,
                              snapshot.xin_hz > 60000000U ? snapshot.xin_hz / 2U
                                                          : snapshot.xin_hz)) {
        code = 4U;
    } else {
        /* No-PLL compatibility has no PLL profile bit. */
    }
    if (code == 0U && !rs_p7_profile(RS_TINY_RCU_PROFILE_SAFE24, 24000000U, 24000000U, 24000000U)) {
        code = 5U;
    }
    if (code == 0U && rs_tiny_rcu_apply_gate(UINT32_C(1) << 4U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        code = 6U;
    }
    if (code == 0U && rs_tiny_rcu_apply_gate(0U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        code = 7U;
    }
    if (code == 0U && rs_tiny_rcu_apply_reset(UINT32_C(1) << 4U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        code = 8U;
    }
    if (code == 0U && !rs_p7_sleep()) {
        code = 9U;
    }
    if (code == 0U) {
        rs_p7_retained = UINT32_C(0x7037CAFE);
        (void)rs_tiny_rcu_system_reset(RS_TIMEOUT_DEFAULT);
        code = 10U;
    }
    rs_sysctrl_write_test_status(code == 0U, code);
    for (;;) {
    }
}
