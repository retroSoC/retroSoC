#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/spi.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

static void rs_spi_p3_store_fault(uintptr_t mcause, uintptr_t stack_pointer) {
    volatile uint32_t *const frame = (volatile uint32_t *)stack_pointer;
    uintptr_t mtval;
    __asm__ volatile("csrr %0, mtval" : "=r"(mtval));
    printf("SPI_P3_TRAP mcause=%lx mepc=%lx mtval=%lx\n", (unsigned long)mcause,
           (unsigned long)frame[11], (unsigned long)mtval);
    for (;;) {
    }
}

int main(void) {
    rs_spi_config_t config = {
        .divider = 1U,
        .cs_setup = 1U,
        .cs_hold = 1U,
        .cs_inactive = 1U,
        .miso_enable = true,
    };
    rs_spi_status_t status;
    uint32_t ip_id = 0U, version = 0U, capability = 0U;
    uint8_t code = 0U;
    const rs_timeout_t p3_timeout = 10U;
    const rs_gpio_config_t alt0 = {
        .mode = RS_GPIO_MODE_ALT0,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    const rs_gpio_config_t alt1 = {
        .mode = RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };

    (void)rs_irq_register_exception(7U, rs_spi_p3_store_fault);

    if ((rs_spi_probe(&ip_id, &version, &capability) != RS_OK) || (ip_id != RS_SPI_ABI_ID_VALUE) ||
        (version != RS_SPI_ABI_VERSION_VALUE) || ((capability & UINT32_C(0x3)) != UINT32_C(0x3)) ||
        (rs_gpio_configure(27U, &alt0) != RS_OK) || (rs_gpio_configure(28U, &alt1) != RS_OK) ||
        (rs_gpio_configure(30U, &alt1) != RS_OK) || (rs_gpio_configure(31U, &alt1) != RS_OK) ||
        (rs_spi_configure(&config) != RS_OK) || (rs_spi_acquire(p3_timeout) != RS_OK) ||
        (rs_spi_get_status(&status) != RS_OK) ||
        ((status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY)) == 0U) ||
        (rs_spi_release(p3_timeout) != RS_OK)) {
        code = 1U;
    }
    if ((code == 0U) && rs_tiny_rcu_apply_gate(RS_TINY_RCU_TARGET_SPI0, p3_timeout) != RS_OK) {
        code = 2U;
    }
    if ((code == 0U) && rs_tiny_rcu_apply_gate(0U, p3_timeout) != RS_OK) {
        code = 3U;
    }
    rs_sysctrl_write_test_status(code == 0U, code);
    (void)rs_uart_init(24000000U, 921600U);
    printf("SPI_P3_RESULT id=%08x version=%08x capability=%08x code=%u\n", ip_id, version,
           capability, code);
    for (;;) {
    }
}
