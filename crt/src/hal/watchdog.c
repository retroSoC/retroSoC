#include <retrosoc/core/soc.h>
#include <retrosoc/hal/watchdog.h>
#include <retrosoc/lib/printf.h>

#include <wdg.h>
#include <wdg_regs.h>

#define RS_WDG_COMMAND_TIMEOUT UINT32_C(1024)

void ip_wdg_test(int argc, char **argv) {
    static const wdg_config_t config = {
        .prescale_divider = 1U,
        .timeout_ticks = 1024U,
        .window_min_ticks = 0U,
        .early_warning_ticks = 128U,
        .window_enable = false,
        .early_warning_enable = true,
        .debug_freeze_enable = true,
    };
    wdg_snapshot_t snapshot = {0};
    wdg_status_t status;

    (void)argc;
    (void)argv;

    printf("[APB IP] wdg V2 test\n");
    status = wdg_configure((uintptr_t)RS_SOC_APB_WDG_BASE, &config);
    if (status != WDG_STATUS_OK) {
        printf("watchdog configure failed: %d\n", (int)status);
        return;
    }
    status = wdg_interrupt_test((uintptr_t)RS_SOC_APB_WDG_BASE, WDG_INTR_WARNING_MASK);
    if (status == WDG_STATUS_OK) {
        status = wdg_snapshot((uintptr_t)RS_SOC_APB_WDG_BASE, &snapshot, RS_WDG_COMMAND_TIMEOUT);
    }
    if ((status != WDG_STATUS_OK) || ((snapshot.interrupt_state & WDG_INTR_WARNING_MASK) == 0U)) {
        printf("watchdog interrupt self-test failed: %d\n", (int)status);
        return;
    }
    status = wdg_interrupt_clear((uintptr_t)RS_SOC_APB_WDG_BASE, WDG_INTR_WARNING_MASK);
    if (status != WDG_STATUS_OK) {
        printf("watchdog interrupt clear failed: %d\n", (int)status);
        return;
    }
    printf("watchdog V2 ID/config/interrupt test passed\n");
}
