#include <stddef.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/generated/irq_metadata.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/hal/onchip_sram.h>
#include <retrosoc/hal/pwm.h>
#include <retrosoc/hal/rtc.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/watchdog.h>
#include <retrosoc/lib/printf.h>

#include "mcu_acceptance.h"

static _Alignas(64) uint32_t rs_mcu_source[80];
static _Alignas(64) uint32_t rs_mcu_destination[80];
static volatile uint32_t rs_mcu_irq_count;
static volatile uint32_t rs_mcu_exception_count;
static volatile bool rs_mcu_handler_failed;

static void rs_mcu_finish(bool pass, uint8_t code) {
    printf("Tiny acceptance %s code=%u\n", pass ? "passed" : "failed", code);
    rs_sysctrl_write_test_status(pass, code);
    /* The terminal status must retain the first accepted full-word write. */
    rs_sysctrl_write_test_status(!pass, UINT8_C(255));
    for (;;) {
    }
}

static void rs_mcu_exception(uintptr_t mcause, uintptr_t stack_pointer) {
    volatile uint32_t *const frame = (volatile uint32_t *)stack_pointer;

    if ((mcause != UINT32_C(2)) && (mcause != UINT32_C(5))) {
        rs_mcu_handler_failed = true;
    }
    ++rs_mcu_exception_count;
    /* system_irq.S saves MEPC in slot 11 of the RV32 trap frame. Both test
     * instructions are explicitly 32 bits; normal exceptions do not use this handler. */
    frame[11] += UINT32_C(4);
}

static void rs_mcu_timer_irq(uintptr_t mcause, uintptr_t stack_pointer) {
    (void)mcause;
    (void)stack_pointer;
    ++rs_mcu_irq_count;
    if (rs_timer_interrupt_clear(RS_TIMER_0, RS_TIMER_INTERRUPT_ALL) != RS_OK) {
        rs_mcu_handler_failed = true;
    }
}

static bool rs_mcu_dma(void) {
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_mcu_source,
        .destination = (uintptr_t)rs_mcu_destination,
        .byte_count = UINT32_C(259),
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .priority = 0U,
        .burst_beats = 16U,
    };

    for (uint32_t index = 0U; index < 80U; ++index) {
        rs_mcu_source[index] = UINT32_C(0xa519c300) ^ index;
        rs_mcu_destination[index] = UINT32_C(0xcccccccc);
    }
    if ((rs_dma_configure(4U, &config) != RS_EINVAL) ||
        (rs_dma_configure(RS_DMA_CHANNEL_BULK, &config) != RS_OK) ||
        (rs_dma_start(RS_DMA_CHANNEL_BULK) != RS_OK) ||
        (rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    for (uint32_t index = 0U; index < 64U; ++index) {
        if (rs_mcu_source[index] != rs_mcu_destination[index]) {
            return false;
        }
    }
    if (rs_mcu_destination[64] !=
        ((rs_mcu_source[64] & UINT32_C(0x00ffffff)) | UINT32_C(0xcc000000))) {
        return false;
    }
    config.kind = RS_DMA_KIND_MM_TO_STREAM;
    config.request = RS_DMA_REQUEST_I2S_TX;
    return rs_dma_config_validate(0U, &config) != RS_OK;
}

static bool rs_mcu_interrupts(void) {
    uint32_t timeout = UINT32_C(20000);

    if ((rs_irq_enable_external(RS_SOC_EXT_IRQ_TIMER0, rs_mcu_timer_irq) != RS_OK) ||
        (rs_timer_interrupt_enable(RS_TIMER_0, RS_TIMER_INTERRUPT_TIMEOUT) != RS_OK) ||
        (rs_timer_interrupt_test(RS_TIMER_0, RS_TIMER_INTERRUPT_TIMEOUT) != RS_OK)) {
        return false;
    }
    __RV_CSR_SET(CSR_MSTATUS, MSTATUS_MIE);
    while ((rs_mcu_irq_count == 0U) && (timeout != 0U)) {
        --timeout;
    }
    __RV_CSR_CLEAR(CSR_MSTATUS, MSTATUS_MIE);
    return (rs_mcu_irq_count == 1U) && !rs_mcu_handler_failed &&
           (rs_irq_disable_external(RS_SOC_EXT_IRQ_TIMER0) == RS_OK);
}

static bool rs_mcu_io(void) {
    const rs_gpio_config_t output = {
        .mode = RS_GPIO_MODE_OUTPUT,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    const rs_uart_config_t loopback = {
        .source_clock_hz = RS_CPU_CLOCK_HZ,
        .baud_rate = UART_BPS,
        .data_bits = 8U,
        .stop_bits = 1U,
        .parity = RS_UART_PARITY_NONE,
        .rx_watermark = 1U,
        .rx_timeout_bits = 16U,
        .tx_enable = true,
        .rx_enable = true,
        .loopback_enable = true,
    };
    const uint32_t transmit[4] = {UINT32_C(0x54), UINT32_C(0x49), UINT32_C(0x4e), UINT32_C(0x59)};
    uint32_t receive[4] = {0U};
    rs_uart_timing_t timing;
    bool high;
    uint32_t timeout = UINT32_C(10000);
    uint8_t payload = UINT8_C(0x55);
    const rs_i2c_transfer_t transfer = {
        .address = UINT16_C(0x50),
        .tx_data = &payload,
        .tx_length = 1U,
    };
    rs_i2c_status_t status;

    if ((rs_gpio_configure(15U, &output) != RS_OK) || (rs_gpio_write(15U, true) != RS_OK) ||
        (rs_gpio_read(15U, &high) != RS_OK) || !high || (rs_gpio_write(15U, false) != RS_OK) ||
        (rs_gpio_read(15U, &high) != RS_OK) || high) {
        return false;
    }
    if ((rs_uart_configure(&loopback, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_uart_write_dma(transmit, 4U, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_uart_read_dma(receive, 4U, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    for (uint32_t index = 0U; index < 4U; ++index) {
        if (transmit[index] != receive[index]) {
            return false;
        }
    }
    if ((rs_uart_init(RS_CPU_CLOCK_HZ, UART_BPS) != RS_OK) ||
        (rs_uart_timing_calculate(RS_CPU_CLOCK_HZ, UART_BPS, &timing) != RS_OK)) {
        return false;
    }
    /* UART1 uses the same register ABI; the current shared high-level UART
     * API selects UART0. Exercise UART1 PIO and its internal loopback here. */
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x00)) = timing.baud_integer;
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x04)) = timing.baud_fraction;
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x08)) = UINT32_C(3);
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x0c)) = UINT32_C(7);
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x10)) = UINT32_C(0x5a);
    while (((RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x18)) & UINT32_C(0x40)) != 0U) &&
           (timeout != 0U)) {
        --timeout;
    }
    if ((timeout == 0U) || ((RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, UINT32_C(0x14)) &
                             UINT32_C(0xff)) != UINT32_C(0x5a))) {
        return false;
    }
    /* There is no slave on the pulled-up acceptance board: a real address
     * transaction must terminate as NACK rather than stick waiting on the bus. */
    for (uint32_t bus = 0U; bus < 2U; ++bus) {
        const rs_i2c_bus_t instance = (bus == 0U) ? RS_I2C_BUS_0 : RS_I2C_BUS_1;
        if ((rs_i2c_init(instance, RS_CPU_CLOCK_HZ, UINT32_C(100000)) != RS_OK) ||
            (rs_i2c_transfer(instance, &transfer, RS_TIMEOUT_DEFAULT) != RS_EIO) ||
            (rs_i2c_get_status(instance, &status) != RS_OK) ||
            ((status.errors & RS_I2C_ERROR_ADDR_NACK) == 0U)) {
            return false;
        }
    }
    return true;
}

static bool rs_mcu_rtc(void) {
    const rs_rtc_config_t config = {
        .second_cycles = UINT32_C(4096),
        .calibration_ppm = 0,
        .interrupt_enable = 0U,
        .wake_enable = 0U,
        .enable = true,
    };
    const rs_rtc_time_t value = {.seconds = UINT64_C(1234), .subsecond = 0U};
    rs_rtc_time_t observed;

    return (rs_rtc_probe() == RS_OK) && (rs_rtc_configure(&config, RS_TIMEOUT_DEFAULT) == RS_OK) &&
           (rs_rtc_set_time(&value, RS_TIMEOUT_DEFAULT) == RS_OK) &&
           (rs_rtc_get_time(&observed, RS_TIMEOUT_DEFAULT) == RS_OK) &&
           (observed.seconds >= value.seconds);
}

int main(void) {
    rs_archinfo_t info;
    rs_onchip_sram_info_t memory;
    rs_sysctrl_fault_status_t fault;
    rs_watchdog_status_t watchdog;
    uint64_t before;
    uint64_t after;
    const rs_watchdog_config_t watchdog_config = {
        .prescale_divider = 1U,
        .timeout_ticks = UINT32_C(20000),
        .window_min_ticks = 0U,
        .early_warning_ticks = 0U,
        .window_enable = false,
        .early_warning_enable = false,
        .debug_freeze_enable = true,
    };

    if (rs_uart_init(RS_CPU_CLOCK_HZ, UART_BPS) != RS_OK) {
        rs_mcu_finish(false, 1U);
    }
    printf("Hello retroSoC! Tiny MCU\n");
    if (rs_watchdog_get_status(&watchdog, RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_mcu_finish(false, 2U);
    }
    if (watchdog.reset_count != 0U) {
        rs_mcu_finish(true, 0U);
    }
    if ((rs_archinfo_read(&info) != RS_OK) || (rs_archinfo_validate_build(&info) != RS_OK) ||
        (info.soc_id != RS_SOC_ID) || (info.topology != UINT32_C(0x20200001)) ||
        (rs_onchip_sram_probe(&memory) != RS_OK) || (memory.memory_bytes != UINT32_C(131072)) ||
        (memory.data_bytes != 4U) || (memory.bank_count != 32U)) {
        rs_mcu_finish(false, 3U);
    }
    if ((rs_mcu_compressed_probe() != 42U) || ((__RV_CSR_READ(CSR_MISA) & UINT32_C(1)) != 0U) ||
        (rs_irq_register_exception(2U, rs_mcu_exception) != RS_OK) ||
        (rs_irq_register_exception(5U, rs_mcu_exception) != RS_OK)) {
        rs_mcu_finish(false, 4U);
    }
    rs_mcu_atomic_probe(rs_mcu_source);
    rs_mcu_unmapped_probe();
    if ((rs_mcu_exception_count != 2U) || rs_mcu_handler_failed ||
        (rs_sysctrl_get_fault_status(&fault) != RS_OK) || !fault.pending ||
        (fault.address != UINT32_C(0x38000000)) || (rs_sysctrl_clear_fault() != RS_OK)) {
        rs_mcu_finish(false, 5U);
    }
    if (!rs_mcu_dma()) {
        rs_mcu_finish(false, 6U);
    }
    if ((rs_clint_get_time(&before) != RS_OK) || (rs_clint_get_time(&after) != RS_OK) ||
        (after <= before) || !rs_mcu_interrupts()) {
        rs_mcu_finish(false, 7U);
    }
    if (!rs_mcu_rtc() || (rs_pwm_probe() != RS_OK) ||
        (rs_sysctrl_set_hp_release(true) != RS_ENOTSUP)) {
        rs_mcu_finish(false, 8U);
    }
    if (!rs_mcu_io()) {
        rs_mcu_finish(false, 10U);
    }
    printf("Tiny CPU/DMA/IRQ/RTC/I/O passed; exercising watchdog reset\n");
    if ((rs_watchdog_configure(&watchdog_config) != RS_OK) ||
        (rs_watchdog_start(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        rs_mcu_finish(false, 9U);
    }
    for (;;) {
    }
}
