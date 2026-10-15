#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#define RS_P8_WORDS   UINT32_C(256)
#define RS_P8_ADDRESS UINT32_C(0x54000c00)
static _Alignas(64) uint32_t rs_p8_source[RS_P8_WORDS];
static _Alignas(64) uint32_t rs_p8_readback[RS_P8_WORDS];
static volatile uint32_t rs_p8_cpu_progress;

typedef struct {
    uint32_t sys_hz, mem_hz;
    uint32_t isolated_cycles, contended_cycles, progress;
} rs_p8_measurement_t;
static rs_p8_measurement_t rs_p8_results[3];

static bool rs_p8_dma(rs_dma_session_t *session, uintptr_t source, uintptr_t destination,
                      bool contend, uint32_t *cycles) {
    const rs_dma_config_t config = {.kind = RS_DMA_KIND_MM_TO_MM,
                                    .request = RS_DMA_REQUEST_SOFTWARE,
                                    .source = source,
                                    .destination = destination,
                                    .byte_count = sizeof(rs_p8_source),
                                    .width = RS_DMA_WIDTH_32,
                                    .source_increment = true,
                                    .destination_increment = true,
                                    .burst_beats = RS_XPI_PSRAM_BURST_BEATS};
    rs_dma_status_t state = {0};
    rs_timeout_t timeout = RS_TIMEOUT_DEFAULT;
    uint64_t start;
    if (rs_dma_session_configure(session, &config) != RS_OK ||
        rs_sysctrl_set_perf_control(true, true, false) != RS_OK) {
        return false;
    }
    __FENCE(rw, rw);
    start = __get_rv_cycle();
    if (rs_dma_session_start(session) != RS_OK) {
        return false;
    }
    do {
        if (contend) {
            /* Defined competing SRAM work, with no race on the DMA buffers. */
            rs_p8_cpu_progress++;
        }
        if (timeout-- == 0U || rs_dma_get_status(session->channel, &state) != RS_OK) {
            return false;
        }
    } while (state.busy);
    *cycles = (uint32_t)(__get_rv_cycle() - start);
    __FENCE(rw, rw);
    if (rs_sysctrl_set_perf_control(false, false, false) != RS_OK) {
        return false;
    }
    return state.done && !state.error && !state.aborted &&
           state.bytes_done == sizeof(rs_p8_source) && state.remaining == 0U;
}

static bool rs_p8_profile(rs_tiny_rcu_profile_t profile, rs_p8_measurement_t *measurement) {
    rs_tiny_rcu_snapshot_t clocks;
    rs_xpi_psram_t device;
    rs_dma_session_t session;
    volatile uint32_t *const memory = (volatile uint32_t *)(uintptr_t)RS_P8_ADDRESS;
    volatile uint32_t *const first = (volatile uint32_t *)(uintptr_t)RS_XPI_PSRAM_BASE;
    volatile uint32_t *const last = (volatile uint32_t *)(uintptr_t)UINT32_C(0x547ffffc);
    bool pass = true;
    uint32_t unused_cycles;
    if (rs_tiny_rcu_request_profile(profile, RS_TIMEOUT_DEFAULT) != RS_OK ||
        rs_tiny_rcu_get_snapshot(&clocks) != RS_OK ||
        rs_xpi_psram_initialize(clocks.mem_hz, RS_TIMEOUT_DEFAULT, &device) != RS_OK ||
        rs_xpi_psram_validate_dma(&device, RS_P8_ADDRESS, sizeof(rs_p8_source), 4U) != RS_OK) {
        return false;
    }
    measurement->sys_hz = clocks.sys_hz;
    measurement->mem_hz = clocks.mem_hz;
    *first = 0U;
    *(volatile uint8_t *)(uintptr_t)(RS_XPI_PSRAM_BASE + 1U) = UINT8_C(0xa5);
    *(volatile uint16_t *)(uintptr_t)(RS_XPI_PSRAM_BASE + 2U) = UINT16_C(0xbeef);
    *last = UINT32_C(0x2468ace0);
    if (*first != UINT32_C(0xbeefa500) || *last != UINT32_C(0x2468ace0)) {
        return false;
    }
    if (rs_dma_session_acquire(&session, RS_DMA_CHANNEL_BULK) != RS_OK) {
        return false;
    }
    for (uint32_t round = 0U; round < 2U && pass; round++) {
        for (uint32_t i = 0U; i < RS_P8_WORDS; i++) {
            rs_p8_source[i] = UINT32_C(0x13579bdf) ^ (i * UINT32_C(0x01010101)) ^ round;
            rs_p8_readback[i] = 0U;
        }
        *(volatile uint32_t *)(uintptr_t)(RS_P8_ADDRESS - 4U) = UINT32_C(0x55aa55aa);
        memory[RS_P8_WORDS] = UINT32_C(0xaa55aa55);
        rs_p8_cpu_progress = 0U;
        pass =
            rs_p8_dma(&session, (uintptr_t)rs_p8_source, RS_P8_ADDRESS, round != 0U,
                      round == 0U ? &measurement->isolated_cycles : &measurement->contended_cycles);
        measurement->progress = rs_p8_cpu_progress;
        for (uint32_t i = 0U; i < RS_P8_WORDS && pass; i++) {
            pass = memory[i] == rs_p8_source[i];
        }
        if (pass) {
            pass = rs_p8_dma(&session, RS_P8_ADDRESS, (uintptr_t)rs_p8_readback, false,
                             &unused_cycles);
        }
        for (uint32_t i = 0U; i < RS_P8_WORDS && pass; i++) {
            pass = rs_p8_readback[i] == rs_p8_source[i];
        }
        pass = pass &&
               (*(volatile uint32_t *)(uintptr_t)(RS_P8_ADDRESS - 4U) == UINT32_C(0x55aa55aa)) &&
               (memory[RS_P8_WORDS] == UINT32_C(0xaa55aa55));
    }
    if (!pass && rs_dma_abort_wait(session.channel, RS_TIMEOUT_DEFAULT) != RS_OK) {
        return false; /* Static buffers remain owned; terminal failure follows. */
    }
    return rs_dma_session_release(&session) == RS_OK && pass && measurement->progress != 0U;
}

int main(void) {
    const rs_gpio_config_t pin = {.mode = RS_GPIO_MODE_ALT0,
                                  .pull = RS_GPIO_PULL_NONE,
                                  .trigger = RS_GPIO_TRIGGER_NONE,
                                  .output_high = true};
    rs_tiny_rcu_snapshot_t clocks;
    rs_xpi_psram_t device;
    rs_status_t status;
    const uint32_t nor_word = *(volatile const uint32_t *)(uintptr_t)UINT32_C(0x50000000);
    uint32_t count = 0U;
    uint8_t code = 0U;
    __disable_irq();
    if (rs_gpio_configure(29U, &pin) != RS_OK || rs_tiny_rcu_get_snapshot(&clocks) != RS_OK) {
        code = 1U;
    } else {
        status = rs_xpi_psram_initialize(clocks.mem_hz, RS_TIMEOUT_DEFAULT, &device);
        if (status == RS_ENOTSUP && !device.initialized && device.capacity_bytes == 0U) {
            (void)rs_uart_init(24000000U, 921600U);
            printf("P8_ABSENT bounded optional-device rejection\n");
            code =
                (*(volatile const uint32_t *)(uintptr_t)UINT32_C(0x50000000) == nor_word) ? 0U : 2U;
        } else if (status != RS_OK) {
            code = 3U;
        } else {
            if (!rs_p8_profile(RS_TINY_RCU_PROFILE_SAFE24, &rs_p8_results[count++])) {
                code = 4U;
            }
            if (code == 0U && (clocks.capability & 12U) == 12U) {
                if (!rs_p8_profile(RS_TINY_RCU_PROFILE_PLL192, &rs_p8_results[count++]) ||
                    !rs_p8_profile(RS_TINY_RCU_PROFILE_PLL240, &rs_p8_results[count++])) {
                    code = 5U;
                }
            } else if (code == 0U && clocks.xin_hz != 24000000U) {
                if (!rs_p8_profile(RS_TINY_RCU_PROFILE_XIN, &rs_p8_results[count++])) {
                    code = 6U;
                }
            }
            if (code == 0U && rs_tiny_rcu_request_profile(RS_TINY_RCU_PROFILE_SAFE24,
                                                          RS_TIMEOUT_DEFAULT) != RS_OK) {
                code = 7U;
            }
            if (code == 0U &&
                *(volatile const uint32_t *)(uintptr_t)UINT32_C(0x50000000) != nor_word) {
                code = 8U;
            }
        }
    }
    (void)rs_uart_init(24000000U, 921600U);
    for (uint32_t i = 0U; i < count; i++) {
        printf("P8_TRANSPORT sys_hz=%u mem_hz=%u bytes=1024 burst=4 isolated_cycles=%u "
               "contended_cycles=%u progress=%u\n",
               rs_p8_results[i].sys_hz, rs_p8_results[i].mem_hz, rs_p8_results[i].isolated_cycles,
               rs_p8_results[i].contended_cycles, rs_p8_results[i].progress);
    }
    printf("P8_RESULT code=%u profiles=%u\n", code, count);
    rs_sysctrl_write_test_status(code == 0U, code);
    for (;;) {
    }
}
