#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/board/st7789vi.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/sdio.h>
#include <retrosoc/hal/spi.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#include "p10_frame.h"
#include "p9_frame.h"
#include "p9_startup.h"

#define RS_P4_TIMEOUT       UINT32_C(2000000)
#define RS_P4_WORKSPACE_LEN UINT32_C(16)
#define RS_P4_DMA_WORDS     UINT32_C(256)
#define RS_P4_FRAME_ADDRESS UINT32_C(0x54010000)
#define RS_P4_FRAME_PIXELS  UINT32_C(76800)
#define RS_P4_FRAME_BYTES   UINT32_C(153600)
#define RS_P4_FRAME_WORDS   (RS_P4_FRAME_BYTES / sizeof(uint32_t))
#define RS_P4_SD_CHUNKS     UINT32_C(150)
#define RS_P4_GUARD         UINT32_C(0x5A36C9E7)

#ifdef RS_ST7789VI_QUICK
#define RS_P4_FULL_X1 UINT16_C(39)
#define RS_P4_FULL_Y1 UINT16_C(23)
#else
#define RS_P4_FULL_X1 UINT16_C(319)
#define RS_P4_FULL_Y1 UINT16_C(239)
#endif

typedef struct {
    uint32_t before[16];
    uint32_t words[RS_P4_DMA_WORDS];
    uint32_t after[16];
} rs_p4_sd_buffer_t;

static uint32_t rs_p4_workspace[RS_P4_WORKSPACE_LEN];
static _Alignas(64) uint32_t rs_p4_dma_workspace[RS_P4_DMA_WORDS];
static _Alignas(64) rs_p4_sd_buffer_t rs_p4_sd_transmit;
static _Alignas(64) rs_p4_sd_buffer_t rs_p4_sd_receive;

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

static uint64_t rs_p4_cycles(void) {
    uint32_t high;
    uint32_t low;
    uint32_t again;
    do {
        high = __RV_CSR_READ(CSR_CYCLEH);
        low = __RV_CSR_READ(CSR_CYCLE);
        again = __RV_CSR_READ(CSR_CYCLEH);
    } while (high != again);
    return ((uint64_t)high << 32U) | low;
}

static uint64_t rs_p4_instructions(void) {
    uint32_t high;
    uint32_t low;
    uint32_t again;
    do {
        high = __RV_CSR_READ(CSR_INSTRETH);
        low = __RV_CSR_READ(CSR_INSTRET);
        again = __RV_CSR_READ(CSR_INSTRETH);
    } while (high != again);
    return ((uint64_t)high << 32U) | low;
}

static uint32_t rs_p4_fnv_word(uint32_t fnv, uint32_t word) {
    for (uint32_t lane = 0U; lane < 2U; ++lane) {
        const uint32_t pixel = (word >> (lane * 16U)) & UINT32_C(0xFFFF);
        fnv = (fnv ^ ((pixel >> 8U) & UINT32_C(0xFF))) * UINT32_C(16777619);
        fnv = (fnv ^ (pixel & UINT32_C(0xFF))) * UINT32_C(16777619);
    }
    return fnv;
}

static bool rs_p4_frame_guards(void) {
    const volatile uint32_t *const frame =
        (const volatile uint32_t *)(uintptr_t)RS_P4_FRAME_ADDRESS;
    return (*(const volatile uint32_t *)(uintptr_t)(RS_P4_FRAME_ADDRESS - 4U) == RS_P4_GUARD) &&
           (frame[RS_P4_FRAME_WORDS] == RS_P4_GUARD);
}

static bool rs_p4_sd_guards(void) {
    for (uint32_t index = 0U; index < 16U; ++index) {
        if ((rs_p4_sd_transmit.before[index] != RS_P4_GUARD) ||
            (rs_p4_sd_transmit.after[index] != RS_P4_GUARD) ||
            (rs_p4_sd_receive.before[index] != RS_P4_GUARD) ||
            (rs_p4_sd_receive.after[index] != RS_P4_GUARD)) {
            return false;
        }
    }
    return true;
}

static bool rs_p4_configure_pins(uint32_t first, uint32_t last, rs_gpio_mode_t mode) {
    const rs_gpio_config_t config = {
        .mode = mode,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    for (uint32_t pin = first; pin <= last; ++pin) {
        if (rs_gpio_configure(pin, &config) != RS_OK) {
            return false;
        }
    }
    return true;
}

static rs_status_t rs_p4_b_setup(rs_tiny_rcu_snapshot_t *clock, rs_xpi_psram_t *psram,
                                 rs_sd_memory_info_t *card) {
    if ((clock == NULL) || (psram == NULL) || (card == NULL) ||
        (rs_tiny_rcu_get_snapshot(clock) != RS_OK) || (clock->sys_hz != UINT32_C(24000000)) ||
        (clock->mem_hz != UINT32_C(24000000)) || (clock->pclk_hz != UINT32_C(24000000)) ||
        !rs_p9_psram_pin_ready(rs_gpio_configure) ||
        !rs_p4_configure_pins(12U, 23U, RS_GPIO_MODE_ALT1) ||
        !rs_p4_configure_pins(0U, 5U, RS_GPIO_MODE_ALT0) ||
        (rs_tiny_rcu_set_clkout(1U, 1U) != RS_OK) ||
        (rs_xpi_psram_initialize(clock->mem_hz, RS_TIMEOUT_DEFAULT, psram) != RS_OK) ||
        (rs_xpi_psram_validate_dma(psram, RS_P4_FRAME_ADDRESS, RS_P4_FRAME_BYTES, 4U) != RS_OK) ||
        (rs_sd_memory_initialize(RS_SDIO_INSTANCE_0, clock->pclk_hz, card, RS_TIMEOUT_DEFAULT) !=
         RS_OK) ||
        (card->capacity_blocks < 316U) || (card->actual_clock_hz != UINT32_C(12000000))) {
        return RS_EIO;
    }
    *(volatile uint32_t *)(uintptr_t)(RS_P4_FRAME_ADDRESS - 4U) = RS_P4_GUARD;
    ((volatile uint32_t *)(uintptr_t)RS_P4_FRAME_ADDRESS)[RS_P4_FRAME_WORDS] = RS_P4_GUARD;
    for (uint32_t index = 0U; index < 16U; ++index) {
        rs_p4_sd_transmit.before[index] = RS_P4_GUARD;
        rs_p4_sd_transmit.after[index] = RS_P4_GUARD;
        rs_p4_sd_receive.before[index] = RS_P4_GUARD;
        rs_p4_sd_receive.after[index] = RS_P4_GUARD;
    }
    return RS_OK;
}

static rs_status_t rs_p4_capture(uint32_t *dma_bytes, uint32_t *camera_active,
                                 uint32_t *dma2_busy) {
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

    if ((dma_bytes == NULL) || (camera_active == NULL) || (dma2_busy == NULL) ||
        (rs_dvp_configure(&config) != RS_OK) ||
        (rs_dvp_capture_dma(RS_P4_FRAME_ADDRESS, RS_P4_FRAME_WORDS, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_dvp_get_status(&dvp) != RS_OK) ||
        (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma) != RS_OK) ||
        (rs_xpi_error_get(&xpi) != RS_OK) || xpi.valid || (dvp.error_status != 0U) || dvp.active ||
        (dvp.pixel_count != RS_P4_FRAME_PIXELS) || (dvp.word_count != RS_P4_FRAME_WORDS) ||
        !dma.done || dma.busy || dma.error || (dma.bytes_done != RS_P4_FRAME_BYTES) ||
        (dma.remaining != 0U) || !rs_p4_frame_guards()) {
        return RS_EIO;
    }
    *dma_bytes = dma.bytes_done;
    if ((rs_dvp_abort() != RS_OK) || (rs_tiny_rcu_set_clkout(0U, 0U) != RS_OK) ||
        (rs_dvp_get_status(&dvp) != RS_OK) ||
        (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma) != RS_OK)) {
        return RS_EIO;
    }
    *camera_active = dvp.active ? 1U : 0U;
    *dma2_busy = dma.busy ? 1U : 0U;
    return ((*camera_active == 0U) && (*dma2_busy == 0U)) ? RS_OK : RS_EIO;
}

static rs_status_t rs_p4_verify(uint32_t *fnv_out) {
    const volatile uint32_t *const frame =
        (const volatile uint32_t *)(uintptr_t)RS_P4_FRAME_ADDRESS;
    rs_xpi_error_t xpi;
    uint32_t fnv = UINT32_C(2166136261);

    if (fnv_out == NULL) {
        return RS_EINVAL;
    }
    for (uint32_t index = 0U; index < RS_P4_FRAME_WORDS; ++index) {
        const uint32_t expected = rs_p9_frame_word(index / 160U, index % 160U, false);
        if (frame[index] != expected) {
            return RS_EIO;
        }
        fnv = rs_p4_fnv_word(fnv, frame[index]);
    }
    if ((rs_xpi_error_get(&xpi) != RS_OK) || xpi.valid || !rs_p4_frame_guards()) {
        return RS_EIO;
    }
    *fnv_out = fnv;
    return RS_OK;
}

static rs_status_t rs_p4_run_display(uint32_t *workspace, rs_dma_session_t *session,
                                     const char *source, uint32_t sys_hz, uint32_t bus_window) {
    const rs_st7789vi_window_t full = {0U, 0U, 319U, 239U};
    const volatile uint32_t *const frame =
        (const volatile uint32_t *)(uintptr_t)RS_P4_FRAME_ADDRESS;
    rs_st7789vi_dma_measurement_t measurement;
    rs_status_t status;
    uint64_t cycle_start;
    uint64_t instruction_start;
    uint64_t frame_cycles;
    uint64_t instructions;
    uint64_t frame_time_ns;
    uint64_t utilization;
    uint32_t sck_hz;

    if ((source == NULL) || (sys_hz == 0U) ||
        (rs_sysctrl_set_perf_control(true, true, false) != RS_OK)) {
        return RS_EIO;
    }
    cycle_start = rs_p4_cycles();
    instruction_start = rs_p4_instructions();
    status = rs_st7789vi_display_buffer(&full, frame, RS_P4_FRAME_BYTES, workspace,
                                        (workspace == NULL) ? 0U : RS_P4_DMA_WORDS, session,
                                        &measurement, RS_P4_TIMEOUT);
    frame_cycles = rs_p4_cycles() - cycle_start;
    instructions = rs_p4_instructions() - instruction_start;
    if (rs_sysctrl_set_perf_control(false, false, true) != RS_OK) {
        status = RS_EIO;
    }
    if (status != RS_OK) {
        rs_spi_status_t spi_status;
        rs_dma_status_t dma_status;
        rs_dma_error_t dma_error;
        (void)rs_spi_get_status(&spi_status);
        (void)rs_dma_get_status(session->channel, &dma_status);
        (void)rs_dma_get_error(session->channel, &dma_error);
        printf("SPI_P4_DMA_ERROR source=%s spi_status=%08x fault=%08x frames=%lu tx_words=%lu "
               "spi_dma=%08x levels=%08x busy=%u done=%u aborted=%u error=%u bytes=%lu "
               "remaining=%lu code=%lu response=%lu address=%08lx read=%u\n",
               source, spi_status.status, spi_status.fault, (unsigned long)spi_status.frames_done,
               (unsigned long)spi_status.tx_words, (unsigned long)spi_status.dma_status,
               (unsigned long)spi_status.levels, dma_status.busy, dma_status.done,
               dma_status.aborted, dma_status.error, (unsigned long)dma_status.bytes_done,
               (unsigned long)dma_status.remaining, (unsigned long)dma_error.code,
               (unsigned long)dma_error.response_code, (unsigned long)dma_error.address,
               dma_error.read);
        return status;
    }
    if ((frame_cycles == 0U) || (measurement.clock_hz == 0U) || (measurement.divider == 0U) ||
        (measurement.frames != RS_P4_FRAME_PIXELS) ||
        (measurement.payload_bytes != RS_P4_FRAME_BYTES) ||
        (measurement.transport_words != RS_P4_FRAME_WORDS) ||
        (measurement.chunks != ((workspace == NULL) ? 1U : RS_P4_SD_CHUNKS)) ||
        (measurement.tx_fifo_final != 0U) || (measurement.tx_fifo_max > 8U) ||
        (measurement.tx_fifo_min > measurement.tx_fifo_max) ||
        (measurement.longest_tx_wait_cycles > measurement.tx_stall_cycles)) {
        return RS_EIO;
    }
    sck_hz = measurement.clock_hz / (2U * measurement.divider);
    frame_time_ns = (frame_cycles * UINT64_C(1000000000)) / sys_hz;
    utilization = ((uint64_t)measurement.payload_bytes * UINT64_C(16) * measurement.divider *
                   UINT64_C(1000000)) /
                  frame_cycles;
    if ((sck_hz == 0U) || (utilization > UINT64_C(1000000))) {
        return RS_EIO;
    }
    printf("SPI_P4_V22 source=%s bus_window=%u pclk_hz=%lu divider=%lu sck_hz=%lu "
           "pixels=%lu payload_bytes=%lu transport_words=%lu chunks=%lu frame_cycles=%llu "
           "cpu_cycles=%llu instructions=%llu frame_time_ns=%llu utilization_ppm=%llu\n",
           source, bus_window, (unsigned long)measurement.clock_hz,
           (unsigned long)measurement.divider, (unsigned long)sck_hz,
           (unsigned long)measurement.frames, (unsigned long)measurement.payload_bytes,
           (unsigned long)measurement.transport_words, (unsigned long)measurement.chunks,
           (unsigned long long)frame_cycles, (unsigned long long)frame_cycles,
           (unsigned long long)instructions, (unsigned long long)frame_time_ns,
           (unsigned long long)utilization);
    printf("SPI_P4_V22_STALL source=%s tx_stall=%lu rx_stall=%lu longest_tx_wait=%lu "
           "longest_rx_wait=%lu dma_stall=%llu fifo_min=%lu fifo_max=%lu fifo_final=%lu\n",
           source, (unsigned long)measurement.tx_stall_cycles,
           (unsigned long)measurement.rx_stall_cycles,
           (unsigned long)measurement.longest_tx_wait_cycles,
           (unsigned long)measurement.longest_rx_wait_cycles,
           (unsigned long long)measurement.dma_stall_cycles, (unsigned long)measurement.tx_fifo_min,
           (unsigned long)measurement.tx_fifo_max, (unsigned long)measurement.tx_fifo_final);
    return RS_OK;
}

static uint8_t rs_p4_save(const rs_sd_memory_info_t *card, uint32_t *fnv_out) {
    const volatile uint32_t *const frame =
        (const volatile uint32_t *)(uintptr_t)RS_P4_FRAME_ADDRESS;
    uint32_t fnv = UINT32_C(2166136261);

    if ((card == NULL) || (fnv_out == NULL)) {
        return 15U;
    }
    for (uint32_t chunk = 0U; chunk < RS_P4_SD_CHUNKS; ++chunk) {
        uint32_t offset;
        uint32_t block;
        if (rs_p10_chunk(RS_P4_FRAME_BYTES, chunk, card->capacity_blocks, &offset, &block) !=
            RS_OK) {
            return 15U;
        }
        for (uint32_t word = 0U; word < RS_P4_DMA_WORDS; ++word) {
            rs_p4_sd_transmit.words[word] = frame[offset + word];
            rs_p4_sd_receive.words[word] = UINT32_C(0xDEADBEEF);
        }
        if (rs_sd_memory_write_blocks(RS_SDIO_INSTANCE_0, card, block, 2U, rs_p4_sd_transmit.words,
                                      RS_TIMEOUT_DEFAULT) != RS_OK) {
            return 15U;
        }
        if (rs_sd_memory_read_blocks(RS_SDIO_INSTANCE_0, card, block, 2U, rs_p4_sd_receive.words,
                                     RS_TIMEOUT_DEFAULT) != RS_OK) {
            return 16U;
        }
        for (uint32_t word = 0U; word < RS_P4_DMA_WORDS; ++word) {
            const uint32_t index = offset + word;
            const uint32_t expected = rs_p9_frame_word(index / 160U, index % 160U, false);
            if ((rs_p4_sd_receive.words[word] != frame[index]) ||
                (rs_p4_sd_receive.words[word] != expected)) {
                return 16U;
            }
            fnv = rs_p4_fnv_word(fnv, rs_p4_sd_receive.words[word]);
        }
        if (!rs_p4_frame_guards() || !rs_p4_sd_guards()) {
            return 16U;
        }
    }
    *fnv_out = fnv;
    return 0U;
}

static rs_status_t rs_p4_dma_abort_case(rs_dma_session_t *session) {
    const rs_st7789vi_window_t full = {0U, 0U, 319U, 239U};
    rs_spi_dma_job_t job = {
        .session = session,
        .buffer = (uintptr_t)RS_P4_FRAME_ADDRESS,
        .capacity_bytes = RS_P4_FRAME_BYTES,
        .direction = RS_SPI_DIRECTION_TX_ONLY,
    };
    rs_spi_status_t spi_status;
    rs_dma_status_t dma_status;
    rs_status_t status = rs_st7789vi_start_buffer(&full, &job, RS_P4_TIMEOUT);
    rs_timeout_t timeout = RS_P4_TIMEOUT;

    if (status != RS_OK) {
        return status;
    }
    for (;;) {
        if (timeout-- == 0U) {
            return RS_ETIMEOUT;
        }
        if (rs_spi_get_status(&spi_status) != RS_OK) {
            return RS_EIO;
        }
        if (spi_status.fault != 0U) {
            return RS_EIO;
        }
        if (spi_status.tx_words >= 64U) {
            break;
        }
        if ((rs_dma_get_status(session->channel, &dma_status) != RS_OK) || dma_status.done ||
            dma_status.error || dma_status.aborted) {
            return RS_EIO;
        }
    }
    status = rs_spi_abort_dma(&job, NULL, RS_P4_TIMEOUT);
    if ((status != RS_OK) || (rs_dma_get_status(session->channel, &dma_status) != RS_OK) ||
        dma_status.busy || !dma_status.aborted || (rs_spi_recover(RS_P4_TIMEOUT) != RS_OK) ||
        (rs_spi_release(RS_P4_TIMEOUT) != RS_OK) || (rs_p4_setup_display_pins() != RS_OK) ||
        (rs_spi_acquire(RS_P4_TIMEOUT) != RS_OK) || (rs_spi_get_status(&spi_status) != RS_OK) ||
        ((spi_status.status & ((UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY) |
                               (UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN))) !=
         ((UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY) |
          (UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN))) ||
        (spi_status.dma_status != 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

static uint8_t rs_p4_run_b(void) {
    rs_tiny_rcu_snapshot_t clock;
    rs_xpi_psram_t psram;
    rs_sd_memory_info_t card;
    rs_dma_session_t session;
    rs_sdio_status_t storage;
    rs_xpi_error_t xpi;
    uint32_t capture_fnv = 0U;
    uint32_t saved_fnv = 0U;
    uint32_t dma_bytes = 0U;
    uint32_t camera_active = 1U;
    uint32_t dma2_busy = 1U;
    uint8_t code;

    if (rs_p4_b_setup(&clock, &psram, &card) != RS_OK) {
        return 9U;
    }
    if (rs_p4_capture(&dma_bytes, &camera_active, &dma2_busy) != RS_OK) {
        return 10U;
    }
    if (rs_p4_verify(&capture_fnv) != RS_OK) {
        return 11U;
    }
    printf("SPI_P4_CAPTURE pixels=%u bytes=%u words=%u dma_bytes=%lu fnv1a=0x%08lx guards=1 "
           "camera_active=%lu dma2_busy=%lu\n",
           RS_P4_FRAME_PIXELS, RS_P4_FRAME_BYTES, RS_P4_FRAME_WORDS, (unsigned long)dma_bytes,
           (unsigned long)capture_fnv, (unsigned long)camera_active, (unsigned long)dma2_busy);
    if ((rs_p4_setup_display_pins() != RS_OK) || (rs_spi_acquire(RS_P4_TIMEOUT) != RS_OK) ||
        (rs_dma_session_acquire(&session, RS_DMA_CHANNEL_BULK) != RS_OK)) {
        return 12U;
    }
    if (rs_p4_run_display(NULL, &session, "psram", clock.sys_hz, 1U) != RS_OK) {
        return 13U;
    }
    if (rs_p4_run_display(rs_p4_dma_workspace, &session, "sram", clock.sys_hz, 2U) != RS_OK) {
        return 14U;
    }
    code = rs_p4_save(&card, &saved_fnv);
    if (code != 0U) {
        return code;
    }
    if (saved_fnv != capture_fnv) {
        return 16U;
    }
    printf("SPI_P4_SD first_lba=16 last_lba=315 blocks=300 chunks=%u bytes=%u readback=1 "
           "fnv1a=0x%08lx\n",
           RS_P4_SD_CHUNKS, RS_P4_FRAME_BYTES, (unsigned long)saved_fnv);
    if (rs_p4_dma_abort_case(&session) != RS_OK) {
        return 17U;
    }
    if ((rs_dma_session_release(&session) != RS_OK) || (rs_spi_release(RS_P4_TIMEOUT) != RS_OK) ||
        (rs_sdio_status_get(RS_SDIO_INSTANCE_0, &storage) != RS_OK) ||
        (storage.error_status != 0U) || storage.busy || (rs_xpi_error_get(&xpi) != RS_OK) ||
        xpi.valid || !rs_p4_frame_guards() || !rs_p4_sd_guards()) {
        return 18U;
    }
    return 0U;
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
    if (code == 0U) {
        if ((rs_spi_get_status(&status) != RS_OK) || (status.divider == 0U)) {
            code = 8U;
        } else {
            printf("SPI_P4_MEASURE sck_hz=%lu payload_bytes=%lu transport_words=%lu tx_stall=%lu\n",
                   (unsigned long)(status.clock_hz / (2U * status.divider)),
                   (unsigned long)status.payload_bytes, (unsigned long)status.transport_words,
                   (unsigned long)status.tx_stall_cycles);
        }
    }
    if ((code == 0U) && (rs_spi_release(RS_P4_TIMEOUT) != RS_OK)) {
        code = 8U;
    }
    if (code == 0U) {
        code = rs_p4_run_b();
    }
    rs_sysctrl_write_test_status(code == 0U, code);
    (void)rs_uart_init(24000000U, 921600U);
    printf("SPI_P4_RESULT id=%08x version=%08x capability=%08x code=%u\n", ip_id, version,
           capability, code);
    for (;;) {
    }
}
