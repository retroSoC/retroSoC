#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/sdio.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#include "p9_frame.h"
#include "p9_startup.h"
#include "p10_frame.h"

#define RS_P10_FRAME_ADDRESS UINT32_C(0x54010000)
#define RS_P10_BYTES         UINT32_C(153600)
#define RS_P10_WORDS         (RS_P10_BYTES / 4U)
#define RS_P10_GUARD         UINT32_C(0x5A36C9E7)

typedef struct {
    uint32_t before[16];
    uint32_t words[256];
    uint32_t after[16];
} rs_p10_buffer_t;

typedef struct {
    uint64_t cycles;
    uint64_t instructions;
    uint32_t bytes;
    uint32_t calls;
} rs_p10_window_t;

static _Alignas(64) rs_p10_buffer_t rs_p10_transmit;
static _Alignas(64) rs_p10_buffer_t rs_p10_receive;
static rs_p10_statistics_t rs_p10_statistics = {.checksum = UINT32_C(2166136261)};
static rs_p10_window_t rs_p10_windows[5];
static uint64_t rs_p10_cycle_start;
static uint64_t rs_p10_instruction_start;

static uint64_t rs_p10_cycles(void) {
    uint32_t high, low, again;
    do {
        high = __RV_CSR_READ(CSR_CYCLEH);
        low = __RV_CSR_READ(CSR_CYCLE);
        again = __RV_CSR_READ(CSR_CYCLEH);
    } while (high != again);
    return ((uint64_t)high << 32U) | low;
}

static uint64_t rs_p10_instructions(void) {
    uint32_t high, low, again;
    do {
        high = __RV_CSR_READ(CSR_INSTRETH);
        low = __RV_CSR_READ(CSR_INSTRET);
        again = __RV_CSR_READ(CSR_INSTRETH);
    } while (high != again);
    return ((uint64_t)high << 32U) | low;
}

static bool rs_p10_begin(void) {
    if (rs_sysctrl_set_perf_control(true, true, false) != RS_OK) {
        return false;
    }
    rs_p10_cycle_start = rs_p10_cycles();
    rs_p10_instruction_start = rs_p10_instructions();
    return true;
}

static bool rs_p10_end(uint32_t phase, uint32_t bytes) {
    const uint64_t instructions = rs_p10_instructions() - rs_p10_instruction_start;
    const uint64_t cycles = rs_p10_cycles() - rs_p10_cycle_start;
    if (phase >= 5U || rs_sysctrl_set_perf_control(false, false, true) != RS_OK) {
        return false;
    }
    rs_p10_windows[phase].cycles += cycles;
    rs_p10_windows[phase].instructions += instructions;
    rs_p10_windows[phase].bytes += bytes;
    rs_p10_windows[phase].calls++;
    return true;
}

static bool rs_p10_guards(void) {
    const volatile uint32_t *const frame = (const volatile uint32_t *)RS_P10_FRAME_ADDRESS;
    if (*(const volatile uint32_t *)(RS_P10_FRAME_ADDRESS - 4U) != RS_P10_GUARD ||
        frame[RS_P10_WORDS] != RS_P10_GUARD) {
        return false;
    }
    for (uint32_t index = 0U; index < 16U; ++index) {
        if (rs_p10_transmit.before[index] != RS_P10_GUARD ||
            rs_p10_transmit.after[index] != RS_P10_GUARD ||
            rs_p10_receive.before[index] != RS_P10_GUARD ||
            rs_p10_receive.after[index] != RS_P10_GUARD) {
            return false;
        }
    }
    return true;
}

static bool rs_p10_pins(uint32_t first, uint32_t last, rs_gpio_mode_t mode) {
    const rs_gpio_config_t config = {
        .mode = mode,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
    };
    for (uint32_t pin = first; pin <= last; ++pin) {
        if (rs_gpio_configure(pin, &config) != RS_OK) {
            return false;
        }
    }
    return true;
}

static uint8_t rs_p10_capture(void) {
    const rs_dvp_config_t config = {
        .format = RS_DVP_FORMAT_RGB565,
        .frame_width = 320U,
        .frame_height = 240U,
        .crop_width = 320U,
        .crop_height = 240U,
        .snapshot = true,
        .stream_enable = true,
    };
    rs_dvp_status_t dvp;
    rs_dma_status_t dma;
    rs_xpi_error_t xpi;
    if (rs_dvp_configure(&config) != RS_OK || !rs_p10_begin()) {
        return 3U;
    }
    const rs_status_t result =
        rs_dvp_capture_dma(RS_P10_FRAME_ADDRESS, RS_P10_WORDS, RS_TIMEOUT_DEFAULT);
    if (!rs_p10_end(0U, RS_P10_BYTES) || result != RS_OK || rs_dvp_get_status(&dvp) != RS_OK ||
        rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma) != RS_OK || rs_xpi_error_get(&xpi) != RS_OK ||
        xpi.valid || dvp.error_status != 0U || dvp.active || dvp.pixel_count != 76800U ||
        dvp.word_count != RS_P10_WORDS || !dma.done || dma.busy || dma.error ||
        dma.bytes_done != RS_P10_BYTES || !rs_p10_guards()) {
        return 3U;
    }
    /* No further camera frame or DMA work is admitted during processing/save. */
    return rs_dvp_abort() == RS_OK ? 0U : 3U;
}

static uint8_t rs_p10_process(void) {
    const volatile uint32_t *const frame = (const volatile uint32_t *)RS_P10_FRAME_ADDRESS;
    if (!rs_p10_begin()) {
        return 4U;
    }
    for (uint32_t index = 0U; index < RS_P10_WORDS; ++index) {
        const uint32_t word = frame[index];
        if (word != rs_p9_frame_word(index / 160U, index % 160U, false) ||
            rs_p10_accumulate(&rs_p10_statistics, word) != RS_OK) {
            (void)rs_p10_end(1U, index * 4U);
            return 4U;
        }
    }
    return rs_p10_end(1U, RS_P10_BYTES) && rs_p10_guards() ? 0U : 4U;
}

static uint8_t rs_p10_save(const rs_sd_memory_info_t *card) {
    const volatile uint32_t *const frame = (const volatile uint32_t *)RS_P10_FRAME_ADDRESS;
    for (uint32_t chunk = 0U; chunk < 150U; ++chunk) {
        uint32_t offset, block;
        if (rs_p10_chunk(RS_P10_BYTES, chunk, card->capacity_blocks, &offset, &block) != RS_OK ||
            !rs_p10_begin()) {
            return 5U;
        }
        for (uint32_t word = 0U; word < 256U; ++word) {
            rs_p10_transmit.words[word] = frame[offset + word];
            rs_p10_receive.words[word] = UINT32_C(0xDEADBEEF);
        }
        if (!rs_p10_end(2U, 1024U) || !rs_p10_begin()) {
            return 5U;
        }
        rs_status_t result = rs_sd_memory_write_blocks(RS_SDIO_INSTANCE_0, card, block, 2U,
                                                       rs_p10_transmit.words, RS_TIMEOUT_DEFAULT);
        if (!rs_p10_end(3U, 1024U) || result != RS_OK || !rs_p10_begin()) {
            return 5U;
        }
        result = rs_sd_memory_read_blocks(RS_SDIO_INSTANCE_0, card, block, 2U, rs_p10_receive.words,
                                          RS_TIMEOUT_DEFAULT);
        bool matches = result == RS_OK;
        for (uint32_t word = 0U; word < 256U; ++word) {
            const uint32_t index = offset + word;
            if (rs_p10_receive.words[word] != rs_p9_frame_word(index / 160U, index % 160U, false)) {
                matches = false;
            }
        }
        if (!rs_p10_end(4U, 1024U) || !matches || !rs_p10_guards()) {
            return 6U;
        }
        if (chunk % 32U == 0U) {
            printf("P10_PROGRESS chunks=%u\n", chunk + 1U);
        }
    }
    return 0U;
}

int main(void) {
    rs_tiny_rcu_snapshot_t clock;
    rs_xpi_psram_t psram;
    rs_sd_memory_info_t card;
    uint8_t code = 0U;
    __disable_irq();
    if (rs_tiny_rcu_get_snapshot(&clock) != RS_OK || !rs_p9_console_ready(&clock, rs_uart_init)) {
        rs_sysctrl_write_test_status(false, 1U);
        for (;;) {
        }
    }
    if (clock.sys_hz != 24000000U || clock.mem_hz != 24000000U || clock.pclk_hz != 24000000U ||
        !rs_p9_psram_pin_ready(rs_gpio_configure) || !rs_p10_pins(12U, 23U, RS_GPIO_MODE_ALT1) ||
        !rs_p10_pins(0U, 5U, RS_GPIO_MODE_ALT0) || rs_tiny_rcu_set_clkout(1U, 1U) != RS_OK ||
        rs_xpi_psram_initialize(clock.mem_hz, RS_TIMEOUT_DEFAULT, &psram) != RS_OK ||
        rs_xpi_psram_validate_dma(&psram, RS_P10_FRAME_ADDRESS, RS_P10_BYTES, 4U) != RS_OK ||
        rs_sd_memory_initialize(RS_SDIO_INSTANCE_0, clock.pclk_hz, &card, RS_TIMEOUT_DEFAULT) !=
            RS_OK ||
        card.capacity_blocks < 316U || card.actual_clock_hz != 12000000U) {
        code = 2U;
    } else {
        *(volatile uint32_t *)(RS_P10_FRAME_ADDRESS - 4U) = RS_P10_GUARD;
        ((volatile uint32_t *)RS_P10_FRAME_ADDRESS)[RS_P10_WORDS] = RS_P10_GUARD;
        for (uint32_t index = 0U; index < 16U; ++index) {
            rs_p10_transmit.before[index] = RS_P10_GUARD;
            rs_p10_transmit.after[index] = RS_P10_GUARD;
            rs_p10_receive.before[index] = RS_P10_GUARD;
            rs_p10_receive.after[index] = RS_P10_GUARD;
        }
        printf("P10_STAGE capture\n");
        code = rs_p10_capture();
        if (code == 0U) {
            printf("P10_STAGE process\n");
            code = rs_p10_process();
        }
        if (code == 0U) {
            printf("P10_STAGE save\n");
            code = rs_p10_save(&card);
        }
        if (code == 0U) {
            rs_xpi_error_t error;
            rs_sdio_status_t storage;
            if (rs_xpi_error_get(&error) != RS_OK || error.valid ||
                rs_sdio_status_get(RS_SDIO_INSTANCE_0, &storage) != RS_OK ||
                storage.error_status != 0U || storage.busy || !rs_p10_guards()) {
                code = 7U;
            }
        }
    }
    (void)rs_sysctrl_set_perf_control(false, false, true);
    for (uint32_t phase = 0U; phase < 5U; ++phase) {
        printf("P10_PHASE id=%u calls=%u bytes=%u cycles=%llu instructions=%llu\n", phase,
               rs_p10_windows[phase].calls, rs_p10_windows[phase].bytes,
               (unsigned long long)rs_p10_windows[phase].cycles,
               (unsigned long long)rs_p10_windows[phase].instructions);
    }
    for (uint32_t bin = 0U; bin < 32U; ++bin) {
        printf("P10_HIST bin=%u pixels=%u\n", bin, rs_p10_statistics.red[bin]);
    }
    printf("P10_RESULT code=%u pixels=%u bytes=%u sectors=%u checksum=%u\n", code,
           rs_p10_statistics.pixels, code == 0U ? RS_P10_BYTES : 0U, code == 0U ? 300U : 0U,
           rs_p10_statistics.checksum);
    (void)rs_tiny_rcu_set_clkout(0U, 0U);
    rs_sysctrl_write_test_status(code == 0U, code);
    for (;;) {
    }
}
