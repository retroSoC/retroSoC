#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/board/st7789vi.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/spi.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

#define RS_P4_TIMEOUT       UINT32_C(2000000)
#define RS_P4_WORKSPACE_LEN UINT32_C(16)

#ifdef RS_ST7789VI_QUICK
#define RS_P4_FULL_X1 UINT16_C(39)
#define RS_P4_FULL_Y1 UINT16_C(23)
#else
#define RS_P4_FULL_X1 UINT16_C(319)
#define RS_P4_FULL_Y1 UINT16_C(239)
#endif

static uint32_t rs_p4_workspace[RS_P4_WORKSPACE_LEN];

static const rs_gpio_config_t rs_p4_alt0 = {
    .mode = RS_GPIO_MODE_ALT0,
    .pull = RS_GPIO_PULL_NONE,
    .trigger = RS_GPIO_TRIGGER_NONE,
    .output_high = false,
};
static const rs_gpio_config_t rs_p4_alt1 = {
    .mode = RS_GPIO_MODE_ALT1,
    .pull = RS_GPIO_PULL_NONE,
    .trigger = RS_GPIO_TRIGGER_NONE,
    .output_high = false,
};
static const rs_gpio_config_t rs_p4_dc_out = {
    .mode = RS_GPIO_MODE_OUTPUT,
    .pull = RS_GPIO_PULL_NONE,
    .trigger = RS_GPIO_TRIGGER_NONE,
    .output_high = true,
};

static rs_status_t rs_p4_setup_display_pins(void) {
    if ((rs_gpio_configure(27U, &rs_p4_alt0) != RS_OK) ||
        (rs_gpio_configure(28U, &rs_p4_alt1) != RS_OK) ||
        (rs_gpio_configure(31U, &rs_p4_alt1) != RS_OK) ||
        (rs_gpio_configure(30U, &rs_p4_dc_out) != RS_OK)) {
        return RS_EIO;
    }
    return RS_OK;
}

static void rs_p4_store_fault(uintptr_t mcause, uintptr_t stack_pointer) {
    volatile uint32_t *const frame = (volatile uint32_t *)stack_pointer;
    uintptr_t mtval;
    rs_spi_status_t status;
    __asm__ volatile("csrr %0, mtval" : "=r"(mtval));
    if (rs_spi_get_status(&status) != RS_OK) {
        status.fault = 0U;
        status.pins_ready = 0U;
        status.status = 0U;
    }
    printf("SPI_P4_TRAP pins=%08x fault=%08x mcause=%lx mepc=%lx mtval=%lx status=%08x\n",
           (unsigned long)status.pins_ready, (unsigned long)status.fault, (unsigned long)mcause,
           (unsigned long)frame[11], (unsigned long)mtval, (unsigned long)status.status);
    for (;;) {
    }
}

static void rs_p4_counters(uint32_t *cycles, uint32_t *instructions) {
    __asm__ volatile("csrr %0, cycle" : "=r"(*cycles));
    __asm__ volatile("csrr %0, instret" : "=r"(*instructions));
}

static rs_status_t rs_p4_abort_case(rs_timeout_t timeout) {
    const rs_st7789vi_window_t window = {0U, 0U, RS_P4_FULL_X1, RS_P4_FULL_Y1};
    uint32_t pushed = 0U;
    uint32_t index;
    rs_status_t status;

    status = rs_st7789vi_begin_pixels(&window, timeout);
    if (status != RS_OK) {
        return status;
    }
    while (pushed < 257U) {
        for (index = 0U; index < RS_P4_WORKSPACE_LEN; index++) {
            rs_p4_workspace[index] = UINT32_C(0x07E007E0);
        }
        status = rs_spi_transfer_cpu(rs_p4_workspace, NULL, RS_P4_WORKSPACE_LEN, timeout);
        if (status != RS_OK) {
            return status;
        }
        pushed += RS_P4_WORKSPACE_LEN;
    }
    status = rs_spi_abort(timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_recover(timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_release(timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_p4_setup_display_pins();
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_acquire(timeout);
    if (status != RS_OK) {
        return status;
    }
    return rs_st7789vi_fill_window(&(rs_st7789vi_window_t){100U, 100U, 116U, 108U},
                                   RS_ST7789VI_STAGE_FINAL, rs_p4_workspace, RS_P4_WORKSPACE_LEN,
                                   timeout);
}

int main(void) {
    rs_spi_config_t config = {
        .clock_hz = UINT32_C(24000000),
        .divider = 1U,
        .cs_setup = 1U,
        .cs_hold = 1U,
        .cs_inactive = 1U,
        .cpol = false,
        .cpha = false,
        .lsb_first = false,
        .miso_enable = false,
        .display_dc = true,
    };
    const rs_st7789vi_window_t full = {0U, 0U, RS_P4_FULL_X1, RS_P4_FULL_Y1};
    const rs_st7789vi_window_t odd_a = {13U, 17U, 45U, 29U};
    const rs_st7789vi_window_t odd_b = {319U, 0U, 319U, 239U};
    const rs_st7789vi_window_t odd_c = {200U, 239U, 260U, 239U};
    const rs_st7789vi_window_t rotated = {5U, 7U, 45U, 29U};
    rs_spi_status_t status;
    uint32_t ip_id = 0U, version = 0U, capability = 0U;
    uint32_t cycles_begin;
    uint32_t instructions_begin;
    uint32_t cycles_end;
    uint32_t instructions_end;
    uint8_t code = 0U;

    (void)rs_irq_register_exception(7U, rs_p4_store_fault);
    (void)rs_uart_init(24000000U, 921600U);

    if ((rs_spi_probe(&ip_id, &version, &capability) != RS_OK) || (ip_id != RS_SPI_ABI_ID_VALUE) ||
        (version != RS_SPI_ABI_VERSION_VALUE) ||
        ((capability & UINT32_C(0x43)) != UINT32_C(0x43)) ||
        (rs_p4_setup_display_pins() != RS_OK) || (rs_spi_configure(&config) != RS_OK) ||
        (rs_spi_acquire(RS_P4_TIMEOUT) != RS_OK) || (rs_spi_get_status(&status) != RS_OK) ||
        ((status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY)) == 0U)) {
        code = 1U;
    }
    if (rs_spi_get_status(&status) == RS_OK) {
        printf("SPI_P4_READY status=%08x pins=%08x fault=%08x\n", (unsigned long)status.status,
               (unsigned long)status.pins_ready, (unsigned long)status.fault);
    }
    if ((code == 0U) && (rs_st7789vi_init(RS_ST7789VI_ROTATION_NORMAL) != RS_OK)) {
        code = 2U;
    }

    rs_p4_counters(&cycles_begin, &instructions_begin);
    if ((code == 0U) && (rs_st7789vi_fill_window(&full, RS_ST7789VI_STAGE_BARS, rs_p4_workspace,
                                                 RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK)) {
        code = 3U;
    }
    rs_p4_counters(&cycles_end, &instructions_end);
    printf("SPI_P4_STAGE id=1 pixels=%lu cycles=%lu instructions=%lu\n",
           (unsigned long)(((uint32_t)RS_P4_FULL_X1 + 1U) * ((uint32_t)RS_P4_FULL_Y1 + 1U)),
           (unsigned long)(cycles_end - cycles_begin),
           (unsigned long)(instructions_end - instructions_begin));

    rs_p4_counters(&cycles_begin, &instructions_begin);
    if ((code == 0U) && (rs_st7789vi_fill_window(&full, RS_ST7789VI_STAGE_GRADIENT, rs_p4_workspace,
                                                 RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK)) {
        code = 4U;
    }
    rs_p4_counters(&cycles_end, &instructions_end);
    printf("SPI_P4_STAGE id=2 pixels=%lu cycles=%lu instructions=%lu\n",
           (unsigned long)(((uint32_t)RS_P4_FULL_X1 + 1U) * ((uint32_t)RS_P4_FULL_Y1 + 1U)),
           (unsigned long)(cycles_end - cycles_begin),
           (unsigned long)(instructions_end - instructions_begin));

    if ((code == 0U) && ((rs_st7789vi_fill_window(&odd_a, RS_ST7789VI_STAGE_ODD_A, rs_p4_workspace,
                                                  RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK) ||
                         (rs_st7789vi_fill_window(&odd_b, RS_ST7789VI_STAGE_ODD_B, rs_p4_workspace,
                                                  RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK) ||
                         (rs_st7789vi_fill_window(&odd_c, RS_ST7789VI_STAGE_ODD_C, rs_p4_workspace,
                                                  RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK))) {
        code = 5U;
    }
    if ((code == 0U) &&
        ((rs_st7789vi_set_rotation(RS_ST7789VI_ROTATION_VARIANT) != RS_OK) ||
         (rs_st7789vi_fill_window(&rotated, RS_ST7789VI_STAGE_ROTATION, rs_p4_workspace,
                                  RS_P4_WORKSPACE_LEN, RS_P4_TIMEOUT) != RS_OK) ||
         (rs_st7789vi_set_rotation(RS_ST7789VI_ROTATION_NORMAL) != RS_OK))) {
        code = 6U;
    }
    if ((code == 0U) && (rs_p4_abort_case(RS_P4_TIMEOUT) != RS_OK)) {
        code = 7U;
    }
    if ((code == 0U) && (rs_spi_release(RS_P4_TIMEOUT) != RS_OK)) {
        code = 8U;
    }
    if ((code == 0U) && (rs_spi_get_status(&status) == RS_OK)) {
        printf("SPI_P4_MEASURE sck_hz=%lu payload_bytes=%lu transport_words=%lu tx_stall=%lu\n",
               (unsigned long)(config.clock_hz / (2U * config.divider)),
               (unsigned long)status.payload_bytes, (unsigned long)status.transport_words,
               (unsigned long)status.levels);
    }
    rs_sysctrl_write_test_status(code == 0U, code);
    (void)rs_uart_init(24000000U, 921600U);
    printf("SPI_P4_RESULT id=%08x version=%08x capability=%08x code=%u\n", ip_id, version,
           capability, code);
    for (;;) {
    }
}
