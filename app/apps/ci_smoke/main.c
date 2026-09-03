#include <archinfo_regs.h>
#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/apu.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/crypto.h>
#include <retrosoc/hal/extension.h>
#include <retrosoc/hal/fabric_monitor.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/onchip_sram.h>
#include <retrosoc/hal/rng.h>
#include <retrosoc/hal/rtc.h>
#include <retrosoc/hal/sdram.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/usb2.h>
#include <retrosoc/hal/user_ip.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

static bool rs_ci_smoke_archinfo_v2(void) {
    rs_archinfo_t info;
    uint32_t device_id[4];

    return (rs_archinfo_read(&info) == RS_OK) && (rs_archinfo_validate_build(&info) == RS_OK) &&
           (rs_archinfo_read_device_id(device_id) == RS_ENOTSUP) && (rs_rtc_probe() == RS_OK);
}

static bool rs_ci_smoke_apu(void) {
    rs_apu_info_t info;

    return (rs_apu_probe(&info) == RS_OK) && (info.capability0 == RS_APU_CAPABILITY0_IMPLEMENTED) &&
           (info.capability1 == RS_APU_CAPABILITY1_IMPLEMENTED) &&
           (info.abi_digest == RS_APU_DIGEST_IMPLEMENTED);
}

static bool rs_ci_smoke_onchip_sram(void) {
    rs_onchip_sram_info_t info;
    rs_onchip_sram_perf_t performance;

    if ((rs_onchip_sram_probe(&info) != RS_OK) ||
        (rs_onchip_sram_read_performance(&performance) != RS_OK) ||
        (info.present != (RS_SOC_HAS_SRAM != 0U))) {
        return false;
    }
    if (info.present) {
        return (info.memory_bytes == RS_SOC_SRAM_SIZE) &&
               (info.bank_count == (RS_SOC_SRAM_SIZE / RS_ONCHIP_SRAM_BANK_BYTES_VALUE));
    }
    return (info.memory_bytes == 0U) && (info.bank_count == 0U);
}

static bool rs_ci_smoke_onchip_sram_access(void) {
#if RS_SOC_HAS_SRAM
    volatile uint8_t *const bytes = (volatile uint8_t *)(uintptr_t)RS_SOC_SRAM_BASE;
    volatile uint16_t *const halfs = (volatile uint16_t *)(uintptr_t)RS_SOC_SRAM_BASE;
    volatile uint32_t *const words = (volatile uint32_t *)(uintptr_t)RS_SOC_SRAM_BASE;
    volatile uint32_t *const last =
        (volatile uint32_t *)(uintptr_t)(RS_SOC_SRAM_BASE + RS_SOC_SRAM_SIZE - 4U);

    words[0] = UINT32_C(0x11223344);
    if (words[0] != UINT32_C(0x11223344)) {
        return false;
    }
    bytes[1] = UINT8_C(0xA5);
    if (words[0] != UINT32_C(0x1122A544)) {
        return false;
    }
    halfs[1] = UINT16_C(0xBEEF);
    if (words[0] != UINT32_C(0xBEEFA544)) {
        return false;
    }
    *last = UINT32_C(0xCAFEF00D);
    return *last == UINT32_C(0xCAFEF00D);
#else
    return true;
#endif
}

static bool rs_ci_smoke_fabric_monitor_start(void) {
    return (rs_fabric_monitor_clear() == RS_OK) &&
           (rs_fabric_monitor_configure(true, false) == RS_OK);
}

static bool rs_ci_smoke_fabric_monitor_check(void) {
    const rs_fabric_target_t active_memory_target =
        (RS_SOC_HAS_SRAM != 0U) ? RS_FABRIC_TARGET_SRAM : RS_FABRIC_TARGET_SDRAM;
    rs_fabric_monitor_status_t status;
    rs_fabric_master_stats_t master;
    rs_fabric_target_stats_t target;
    rs_fabric_fault_t fault;
    uint32_t flush_count;

    if ((rs_fabric_monitor_snapshot() != RS_OK) ||
        (rs_fabric_monitor_get_status(&status) != RS_OK) ||
        (rs_fabric_monitor_read_master(RS_FABRIC_MASTER_LP, &master) != RS_OK) ||
        (rs_fabric_monitor_read_target(active_memory_target, &target) != RS_OK) ||
        (rs_fabric_monitor_read_fault(&fault) != RS_OK) ||
        (rs_fabric_monitor_get_flush_count(&flush_count) != RS_OK)) {
        return false;
    }
    return !status.recovery && !status.flush_busy && !fault.valid && (flush_count == 0U) &&
           (master.read_requests != 0U) && (master.write_requests != 0U) &&
           (master.read_beats != 0U) && (master.write_beats != 0U) &&
           (target.read_requests != 0U) && (target.write_requests != 0U) &&
           (target.read_beats != 0U) && (target.write_beats != 0U);
}

static bool rs_ci_smoke_extensions(void) {
    const rs_extension_acl_t acl = {
        .read_base = RS_SOC_SDRAM_BASE,
        .read_limit = RS_SOC_SDRAM_END,
        .write_base = RS_SOC_SDRAM_BASE,
        .write_limit = RS_SOC_SDRAM_END,
        .timeout_cycles = UINT32_C(1024),
    };
    rs_extension_capabilities_t ext_l;
    rs_extension_capabilities_t ext_h;
    rs_extension_status_t status;

    if ((RS_SOC_USER_CORE_COUNT != 0U) || (RS_SOC_USER_IP_COUNT != 0U) ||
        (RS_SOC_EXTENSION_COUNT != 2U) || (rs_user_ip_select(0U) != RS_ENOTSUP) ||
        (rs_extension_probe(RS_EXTENSION_SLOT_L, &ext_l) != RS_OK) ||
        (rs_extension_probe(RS_EXTENSION_SLOT_H, &ext_h) != RS_OK) ||
        (ext_l.identification != RS_EXTENSION_IDENTIFICATION_EXT_L) || ext_l.data_master ||
        ext_l.stream || ext_l.local_sram || (ext_l.interrupt_count != 1U) ||
        (ext_h.identification != RS_EXTENSION_IDENTIFICATION_EXT_H) || !ext_h.data_master ||
        ext_h.stream || ext_h.local_sram || (ext_h.interrupt_count != 1U) ||
        (rs_extension_configure_acl(RS_EXTENSION_SLOT_L, &acl) != RS_ENOTSUP) ||
        (rs_extension_configure_acl(RS_EXTENSION_SLOT_H, &acl) != RS_OK) ||
        (rs_extension_set_lifecycle(RS_EXTENSION_SLOT_H, true, true, false) != RS_OK) ||
        (rs_extension_get_status(RS_EXTENSION_SLOT_H, &status) != RS_OK) || !status.present ||
        !status.idle || !status.quiesced || !status.in_reset || status.fault ||
        (rs_extension_set_lifecycle(RS_EXTENSION_SLOT_H, false, false, false) != RS_OK)) {
        return false;
    }
    return rs_extension_get_status(RS_EXTENSION_SLOT_H, &status) == RS_OK && status.present &&
           status.idle && !status.quiesced && !status.in_reset && !status.fault;
}

static bool rs_ci_smoke_rng_v2(void) {
    const rs_rng_config_t config = {
        .fifo_watermark = 1U,
        .interrupt_enable = 0U,
        .lock_config = true,
    };
    rs_rng_snapshot_t snapshot;
    uint32_t first;
    uint32_t second;
    uint32_t entropy;

    if ((rs_rng_init(&config) != RS_OK) ||
        (rs_rng_read_diagnostic(&first, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_rng_read_diagnostic(&second, RS_TIMEOUT_DEFAULT) != RS_OK) || (first == second) ||
        (rs_rng_get_status(&snapshot) != RS_OK) || snapshot.source_qualified ||
        snapshot.fatal_error) {
        return false;
    }

    return rs_rng_read_entropy(&entropy, RS_TIMEOUT_DEFAULT) == RS_ENOTSUP;
}

static bool rs_ci_smoke_clint_standard_map(void) {
    uint64_t first;
    uint64_t current;
    uint64_t compare;
    bool pending;

    if (rs_clint_get_time(&first) != RS_OK) {
        return false;
    }
    current = first;
    for (rs_timeout_t timeout = 512U; (timeout != 0U) && (current == first); --timeout) {
        if (rs_clint_get_time(&current) != RS_OK) {
            return false;
        }
    }
    if ((current <= first) || (rs_clint_set_compare(0U, current + UINT64_C(1000)) != RS_OK) ||
        (rs_clint_get_compare(0U, &compare) != RS_OK) || (compare != (current + UINT64_C(1000)))) {
        return false;
    }
    if ((rs_clint_set_software_interrupt(0U, true) != RS_OK) ||
        (rs_clint_get_software_interrupt(0U, &pending) != RS_OK) || !pending ||
        (rs_clint_set_software_interrupt(0U, false) != RS_OK) ||
        (rs_clint_get_software_interrupt(0U, &pending) != RS_OK) || pending) {
        return false;
    }
    return rs_clint_set_compare(0U, UINT64_MAX) == RS_OK;
}

static bool rs_ci_smoke_timer_one_shot(void) {
    const rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_ONE_SHOT,
        .direction = RS_TIMER_DIRECTION_DOWN,
        .prescale = 0U,
        .load = 8U,
        .compare0 = 4U,
        .compare1 = 0U,
        .interrupt_enable = RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0,
        .freeze_in_debug = true,
        .compare0_enable = true,
        .compare1_enable = false,
    };
    rs_timer_status_t status;

    if ((rs_timer_configure(RS_TIMER_0, &config) != RS_OK) ||
        (rs_timer_start(RS_TIMER_0) != RS_OK)) {
        return false;
    }
    for (rs_timeout_t timeout = 1000U; timeout != 0U; --timeout) {
        if (rs_timer_get_status(RS_TIMER_0, &status) != RS_OK) {
            return false;
        }
        if (!status.active) {
            return (status.value == 0U) &&
                   ((status.interrupt_state &
                     (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0)) ==
                    (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0));
        }
    }
    return false;
}

static bool rs_ci_smoke_timer_periodic(void) {
    const rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_PERIODIC,
        .direction = RS_TIMER_DIRECTION_UP,
        .prescale = 0U,
        .load = 7U,
        .compare0 = 0U,
        .compare1 = 3U,
        .interrupt_enable = RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1,
        .freeze_in_debug = true,
        .compare0_enable = false,
        .compare1_enable = true,
    };
    rs_timer_status_t status;
    bool passed = false;

    if ((rs_timer_configure(RS_TIMER_1, &config) != RS_OK) ||
        (rs_timer_start(RS_TIMER_1) != RS_OK)) {
        return false;
    }
    for (rs_timeout_t timeout = 1000U; timeout != 0U; --timeout) {
        if (rs_timer_get_status(RS_TIMER_1, &status) != RS_OK) {
            break;
        }
        if ((status.interrupt_state & (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1)) ==
            (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1)) {
            passed = true;
            break;
        }
    }
    if (rs_timer_stop(RS_TIMER_1) != RS_OK) {
        return false;
    }
    return passed;
}

static bool rs_ci_smoke_gpio_v2(void) {
    const rs_gpio_config_t config = {
        .mode = RS_GPIO_MODE_OUTPUT,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
        .open_drain = false,
        .input_cmos = false,
        .filter_enable = false,
        .interrupt_enable = false,
    };
    rs_gpio_capabilities_t capabilities;

    if ((rs_gpio_get_capabilities(&capabilities) != RS_OK) ||
        (capabilities.version != UINT32_C(0x00020000)) ||
        ((capabilities.features & UINT32_C(0xFF)) != RS_GPIO_PIN_COUNT) ||
        ((capabilities.features & RS_GPIO_CAP_ATOMIC_OUT) == 0U) ||
        (rs_gpio_configure(31U, &config) != RS_OK) || (rs_gpio_write(31U, true) != RS_OK) ||
        (rs_gpio_toggle(31U) != RS_OK)) {
        return false;
    }
    return rs_gpio_write(31U, false) == RS_OK;
}

#define RS_CI_SMOKE_SDRAM_SPAN UINT32_C(16)

static bool rs_ci_smoke_sdram_wait_ready(void) {
    rs_sdram_status_t status;

    for (rs_timeout_t timeout = RS_TIMEOUT_DEFAULT; timeout != 0U; --timeout) {
        if (rs_sdram_get_status(&status) != RS_OK) {
            return false;
        }
        if (status.error) {
            return false;
        }
        if (status.ready && !status.init_busy) {
            return true;
        }
    }
    return false;
}

static bool rs_ci_smoke_sdram_access(void) {
    const uintptr_t scratch = (uintptr_t)(RS_SOC_SDRAM_END - RS_CI_SMOKE_SDRAM_SPAN + UINT32_C(1));
    volatile uint8_t *const bytes = (volatile uint8_t *)scratch;
    volatile uint16_t *const halfs = (volatile uint16_t *)scratch;
    volatile uint32_t *const words = (volatile uint32_t *)scratch;
    uint32_t index;

    if (!rs_ci_smoke_sdram_wait_ready()) {
        return false;
    }

    for (index = 0U; index < RS_CI_SMOKE_SDRAM_SPAN; ++index) {
        bytes[index] = (uint8_t)(index + 1U);
    }
    for (index = 0U; index < RS_CI_SMOKE_SDRAM_SPAN; ++index) {
        if (bytes[index] != (uint8_t)(index + 1U)) {
            return false;
        }
    }

    for (index = 0U; index < (RS_CI_SMOKE_SDRAM_SPAN / 2U); ++index) {
        halfs[index] = (uint16_t)(index + 1U);
    }
    for (index = 0U; index < (RS_CI_SMOKE_SDRAM_SPAN / 2U); ++index) {
        if (halfs[index] != (uint16_t)(index + 1U)) {
            return false;
        }
    }

    for (index = 0U; index < (RS_CI_SMOKE_SDRAM_SPAN / 4U); ++index) {
        words[index] = index + 1U;
    }
    for (index = 0U; index < (RS_CI_SMOKE_SDRAM_SPAN / 4U); ++index) {
        if (words[index] != (index + 1U)) {
            return false;
        }
    }
    return true;
}

static bool rs_ci_smoke_uart_v3(void) {
    const rs_uart_config_t config = {
        .source_clock_hz = CPU_FREQ * UINT32_C(1000000),
        .baud_rate = UART_BPS,
        .data_bits = 8U,
        .stop_bits = 1U,
        .parity = RS_UART_PARITY_NONE,
        .tx_watermark = 16U,
        .rx_watermark = 1U,
        .rx_timeout_bits = 32U,
        .tx_enable = true,
        .rx_enable = true,
        .loopback_enable = true,
        .auto_cts_enable = false,
        .auto_rts_enable = false,
        .rts_assert_level = 32U,
        .rts_deassert_level = 48U,
    };
    const uint8_t transmitted = UINT8_C(0xA5);
    rs_uart_rx_data_t received;

    if ((RS_SOC_REG32(RS_SOC_APB4_UART0_BASE, UINT32_C(0xF8)) != UINT32_C(0x00030000)) ||
        (RS_SOC_REG32(RS_SOC_APB4_UART0_BASE, UINT32_C(0xFC)) != UINT32_C(0x03FF4040)) ||
        (rs_uart_configure(&config, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_uart_write(&transmitted, 1U, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_uart_read(&received, 1U, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (received.data != transmitted) || (received.errors != 0U)) {
        return false;
    }
    return rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) == RS_OK;
}

int main(void) {
    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 6U);
    }

    if (!rs_ci_smoke_uart_v3()) {
        rs_test_finish(RS_TEST_FAILED, 7U);
    }

    if (!rs_ci_smoke_archinfo_v2()) {
        rs_test_finish(RS_TEST_FAILED, 1U);
    }
    printf("ci_smoke: archinfo passed\n");
    if (!rs_ci_smoke_apu()) {
        rs_test_finish(RS_TEST_FAILED, 14U);
    }
    printf("ci_smoke: APU-P2 discovery passed\n");
    if (!rs_ci_smoke_fabric_monitor_start()) {
        rs_test_finish(RS_TEST_FAILED, 13U);
    }
    if (!rs_ci_smoke_onchip_sram() || !rs_ci_smoke_onchip_sram_access()) {
        rs_test_finish(RS_TEST_FAILED, 12U);
    }
    printf("ci_smoke: on-chip SRAM passed\n");
    if (!rs_ci_smoke_fabric_monitor_check()) {
        rs_test_finish(RS_TEST_FAILED, 13U);
    }
    printf("ci_smoke: fabric monitor passed\n");
    if (!rs_ci_smoke_extensions()) {
        rs_test_finish(RS_TEST_FAILED, 11U);
    }
    printf("ci_smoke: extensions passed\n");
    if (!rs_ci_smoke_rng_v2()) {
        rs_test_finish(RS_TEST_FAILED, 8U);
    }
    printf("ci_smoke: RNG V2 passed\n");
    if (!rs_ci_smoke_clint_standard_map()) {
        rs_test_finish(RS_TEST_FAILED, 2U);
    }
    printf("ci_smoke: CLINT passed\n");
    if (!rs_ci_smoke_timer_one_shot()) {
        rs_test_finish(RS_TEST_FAILED, 3U);
    }
    printf("ci_smoke: timer0 passed\n");
    if (!rs_ci_smoke_timer_periodic()) {
        rs_test_finish(RS_TEST_FAILED, 4U);
    }
    printf("ci_smoke: timer1 passed\n");
    if (!rs_ci_smoke_gpio_v2()) {
        rs_test_finish(RS_TEST_FAILED, 5U);
    }
    printf("ci_smoke: GPIO passed\n");
    if (!rs_ci_smoke_sdram_access()) {
        rs_test_finish(RS_TEST_FAILED, 9U);
    }
    printf("ci_smoke: SDRAM passed\n");
    if (rs_crypto_selftest(RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 10U);
    }
    printf("ci_smoke: crypto passed\n");
    if (rs_usb2_controller_selftest() != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 12U);
    }
    printf("ci_smoke: USB2 passed\n");

    printf("ci_smoke: all peripheral tests passed\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
