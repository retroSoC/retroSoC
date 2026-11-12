#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/board/st7789vi.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/ppalite.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/sdio.h>
#include <retrosoc/hal/spi.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#include "p9_frame.h"
#include "p9_startup.h"

#define RS_PPA_GUARD       UINT32_C(0xC001D00D)
#define RS_PPA_RAW_ADDR    UINT32_C(0x54060000)
#define RS_PPA_GRAY_ADDR   UINT32_C(0x54010000)
#define RS_PPA_RGB_ADDR    UINT32_C(0x54020000)
#define RS_PPA_ODD_ADDR    UINT32_C(0x54030000)
#define RS_PPA_FULL_ADDR   UINT32_C(0x54040000)
#define RS_PPA_PADDED_ADDR UINT32_C(0x54050000)
#define RS_PPA_SD_CHUNKS   UINT32_C(19)
#define RS_PPA_SHORT_LIMIT UINT32_C(2000)

typedef struct {
    uint32_t before[1];
    uint32_t data[2];
    uint32_t after[1];
} rs_ppa_small_buffer_t;

typedef struct {
    uint32_t before[16];
    uint32_t words[256];
    uint32_t after[16];
} rs_ppa_sd_buffer_t;

typedef struct {
    uint64_t arm_cycles;
    uint64_t start_cycles;
    uint64_t wait_cycles;
} rs_ppa_capture_timing_t;

static _Alignas(64) rs_ppa_small_buffer_t rs_ppa_small;
static _Alignas(64) rs_ppa_sd_buffer_t rs_ppa_sd_tx;
static _Alignas(64) rs_ppa_sd_buffer_t rs_ppa_sd_rx;
static rs_dma_session_t rs_ppa_display_session;
static uint32_t rs_ppa_last_job;
static uint32_t rs_ppa_last_source;
static uint32_t rs_ppa_valid_frames;
static uint32_t rs_ppa_recovered;
static uint64_t rs_ppa_cycle_start;
static uint64_t rs_ppa_instruction_start;

static uint64_t rs_ppa_cycles(void) {
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

static uint64_t rs_ppa_instructions(void) {
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

static bool rs_ppa_measure_begin(void) {
    if (rs_sysctrl_set_perf_control(true, true, false) != RS_OK) {
        return false;
    }
    rs_ppa_cycle_start = rs_ppa_cycles();
    rs_ppa_instruction_start = rs_ppa_instructions();
    return true;
}

static bool rs_ppa_measure_end(uint32_t id, uint32_t bytes) {
    const uint64_t cycles = rs_ppa_cycles() - rs_ppa_cycle_start;
    const uint64_t instructions = rs_ppa_instructions() - rs_ppa_instruction_start;
    if ((cycles == 0U) || (instructions == 0U) ||
        rs_sysctrl_set_perf_control(false, false, true) != RS_OK) {
        return false;
    }
    printf("PPALITE_P4_MEASURE id=%u bytes=%lu cycles=%llu instructions=%llu\n", id,
           (unsigned long)bytes, (unsigned long long)cycles, (unsigned long long)instructions);
    return true;
}

static bool rs_ppa_delay(uint32_t microseconds) {
    uint64_t start;
    uint64_t now;
    rs_timeout_t timeout = RS_TIMEOUT_DEFAULT;
    if (rs_clint_get_time(&start) != RS_OK) {
        return false;
    }
    do {
        if ((timeout-- == 0U) || (rs_clint_get_time(&now) != RS_OK)) {
            return false;
        }
    } while ((now - start) < microseconds);
    return true;
}

static bool rs_ppa_pins(uint32_t first, uint32_t last, rs_gpio_mode_t mode) {
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

static bool rs_ppa_display_pins(void) {
    const rs_gpio_config_t dc = {
        .mode = RS_GPIO_MODE_OUTPUT,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = true,
    };
    return rs_ppa_pins(27U, 27U, RS_GPIO_MODE_ALT0) && rs_ppa_pins(28U, 28U, RS_GPIO_MODE_ALT1) &&
           rs_ppa_pins(31U, 31U, RS_GPIO_MODE_ALT1) && (rs_gpio_configure(30U, &dc) == RS_OK);
}

static rs_ppalite_config_t rs_ppa_small_config(void) {
    const rs_ppalite_config_t config = {
        .input_format = RS_PPALITE_INPUT_YUYV,
        .source = {.format = RS_DVP_FORMAT_YUV422,
                   .frame_width = 320U,
                   .frame_height = 240U,
                   .crop_x = 2U,
                   .crop_y = 1U,
                   .crop_width = 5U,
                   .crop_height = 3U,
                   .crop_enable = true,
                   .snapshot = true,
                   .stream_enable = true},
        .step_x = 2U,
        .step_y = 2U,
        .output_gray8 = true,
    };
    return config;
}

static rs_ppalite_config_t rs_ppa_qvga_config(bool gray8) {
    const rs_ppalite_config_t config = {
        .input_format = RS_PPALITE_INPUT_YUYV,
        .source = {.format = RS_DVP_FORMAT_YUV422,
                   .frame_width = 320U,
                   .frame_height = 240U,
                   .crop_width = 320U,
                   .crop_height = 240U,
                   .snapshot = true,
                   .stream_enable = true},
        .step_x = 2U,
        .step_y = 2U,
        .output_gray8 = gray8,
    };
    return config;
}

static rs_ppalite_config_t rs_ppa_odd_config(void) {
    rs_ppalite_config_t config = rs_ppa_qvga_config(false);
    config.source.crop_x = 1U;
    config.source.crop_width = 319U;
    config.source.crop_height = 239U;
    config.source.crop_enable = true;
    config.phase_x = 1U;
    config.output_byte_swap = true;
    return config;
}

static rs_ppalite_config_t rs_ppa_full_gray_config(void) {
    rs_ppalite_config_t config = rs_ppa_qvga_config(true);
    config.step_x = 1U;
    config.step_y = 1U;
    return config;
}

static rs_ppalite_config_t rs_ppa_padded_gray_config(void) {
    rs_ppalite_config_t config = rs_ppa_qvga_config(true);
    config.source.crop_x = 1U;
    config.source.crop_width = 319U;
    config.source.crop_height = 239U;
    config.source.crop_enable = true;
    config.phase_x = 1U;
    return config;
}

static uint8_t rs_ppa_source_y(const rs_ppalite_config_t *config, uint32_t x, uint32_t y) {
    const uint32_t source_x = (config->source.crop_enable ? config->source.crop_x : 0U) + x;
    const uint32_t source_y = (config->source.crop_enable ? config->source.crop_y : 0U) + y;
    const uint32_t index = 2U * source_x;
    return (uint8_t)((index + (3U * source_y)) & UINT32_C(0xFF));
}

static uint16_t rs_ppa_gray_rgb565(uint8_t y) {
    return (uint16_t)(((uint16_t)(y >> 3U) << 11U) | ((uint16_t)(y >> 2U) << 5U) | (y >> 3U));
}

static rs_status_t rs_ppa_capture(const rs_ppalite_config_t *config, uintptr_t destination,
                                  uint32_t capacity, rs_ppalite_frame_t *frame,
                                  rs_ppa_capture_timing_t *timing,
                                  rs_ppalite_measurements_t *core) {
    rs_ppalite_session_t session = {0};
    const uint64_t begin = rs_ppa_cycles();
    uint64_t armed;
    uint64_t started;
    uint64_t completed;
    rs_status_t result =
        rs_ppalite_capture_begin(&session, config, destination, capacity, RS_TIMEOUT_DEFAULT);
    armed = rs_ppa_cycles();
    if (result == RS_OK) {
        result = rs_ppalite_capture_start(&session, RS_TIMEOUT_DEFAULT);
    }
    started = rs_ppa_cycles();
    if (result == RS_OK) {
        result = rs_ppalite_capture_wait(&session, frame, RS_TIMEOUT_DEFAULT);
    }
    completed = rs_ppa_cycles();
    if (result == RS_OK) {
        timing->arm_cycles = armed - begin;
        timing->start_cycles = started - armed;
        timing->wait_cycles = completed - started;
        result = rs_ppalite_get_measurements(core);
    }
    if (result == RS_OK) {
        result = rs_ppalite_release(&session, RS_TIMEOUT_DEFAULT);
    }
    if ((result != RS_OK) && session.acquired) {
        (void)rs_ppalite_abort(&session, RS_TIMEOUT_DEFAULT);
        (void)rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
        frame->valid = false;
    }
    return result;
}

static bool rs_ppa_verify(const rs_ppalite_config_t *config, const rs_ppalite_frame_t *frame) {
    rs_ppalite_layout_t layout;
    rs_dvp_status_t source;
    rs_xpi_error_t xpi;
    const volatile uint8_t *bytes;
    uint32_t expected_config;
    uint32_t active_width;
    uint32_t active_height;

    if ((frame == NULL) || !frame->valid || (frame->error_status != 0U) ||
        (rs_ppalite_layout(config, frame->base, frame->capacity_bytes, &layout) != RS_OK) ||
        (frame->width != layout.width) || (frame->height != layout.height) ||
        (frame->row_bytes != layout.row_bytes) || (frame->stride_bytes != layout.stride_bytes) ||
        (frame->valid_bytes != layout.valid_bytes) ||
        (frame->transport_bytes != layout.transport_bytes) ||
        (frame->job_sequence <= rs_ppa_last_job) ||
        (frame->source_sequence <= rs_ppa_last_source)) {
        return false;
    }
    expected_config =
        (uint32_t)config->input_format | (config->output_gray8 ? UINT32_C(0x10) : 0U) |
        (config->rgb_swap ? UINT32_C(0x20) : 0U) | (config->output_byte_swap ? UINT32_C(0x40) : 0U);
    if ((frame->result_config != expected_config) ||
        (frame->output_byte_swap != config->output_byte_swap)) {
        return false;
    }
    bytes = (const volatile uint8_t *)frame->base;
    for (uint32_t row = 0U; row < (uint32_t)frame->height; ++row) {
        for (uint32_t column = 0U; column < frame->stride_bytes; ++column) {
            uint8_t expected = 0U;
            if (column < frame->row_bytes) {
                const uint32_t y = config->phase_y + (row * config->step_y);
                if (config->output_gray8) {
                    const uint32_t x = config->phase_x + (column * config->step_x);
                    expected = rs_ppa_source_y(config, x, y);
                } else {
                    const uint32_t x = config->phase_x + ((column / 2U) * config->step_x);
                    const uint16_t gray = rs_ppa_gray_rgb565(rs_ppa_source_y(config, x, y));
                    const bool high = (column & 1U) != 0U;
                    expected =
                        (high != config->output_byte_swap) ? (uint8_t)(gray >> 8U) : (uint8_t)gray;
                }
            }
            if (bytes[(row * frame->stride_bytes) + column] != expected) {
                printf("PPALITE_P4_PIXEL_MISMATCH row=%lu column=%lu\n", (unsigned long)row,
                       (unsigned long)column);
                return false;
            }
        }
    }
    active_width =
        config->source.crop_enable ? config->source.crop_width : config->source.frame_width;
    active_height =
        config->source.crop_enable ? config->source.crop_height : config->source.frame_height;
    if ((rs_dvp_get_status(&source) != RS_OK) || (source.error_status != 0U) ||
        (source.word_count != (((active_width + 1U) / 2U) * active_height)) ||
        (source.pixel_count != (active_width * active_height)) ||
        (rs_xpi_error_get(&xpi) != RS_OK) || xpi.valid) {
        return false;
    }
    rs_ppa_last_job = frame->job_sequence;
    rs_ppa_last_source = frame->source_sequence;
    rs_ppa_valid_frames++;
    return true;
}

static void rs_ppa_external_guard_set(uintptr_t destination, uint32_t words) {
    volatile uint32_t *frame = (volatile uint32_t *)destination;
    *(volatile uint32_t *)(destination - sizeof(uint32_t)) = RS_PPA_GUARD;
    frame[words] = RS_PPA_GUARD;
}

static bool rs_ppa_external_guards(uintptr_t destination, uint32_t words) {
    const volatile uint32_t *frame = (const volatile uint32_t *)destination;
    return (*(const volatile uint32_t *)(destination - sizeof(uint32_t)) == RS_PPA_GUARD) &&
           (frame[words] == RS_PPA_GUARD);
}

static bool rs_ppa_run_capture(uint32_t id, const rs_ppalite_config_t *config,
                               uintptr_t destination, uint32_t capacity,
                               rs_ppalite_frame_t *result_frame) {
    rs_ppalite_frame_t frame = {0};
    rs_ppa_capture_timing_t timing = {0};
    rs_ppalite_measurements_t core = {0};
    rs_ppalite_layout_t layout;
    uint32_t active_width;
    uint32_t active_height;
    bool pass = rs_ppa_measure_begin();
    rs_ppa_external_guard_set(destination, capacity / sizeof(uint32_t));
    if (pass) {
        pass = rs_ppa_capture(config, destination, capacity, &frame, &timing, &core) == RS_OK;
    }
    if (pass) {
        pass = rs_ppa_verify(config, &frame) &&
               rs_ppa_external_guards(destination, capacity / sizeof(uint32_t));
    }
    active_width =
        config->source.crop_enable ? config->source.crop_width : config->source.frame_width;
    active_height =
        config->source.crop_enable ? config->source.crop_height : config->source.frame_height;
    if (pass &&
        ((rs_ppalite_layout(config, destination, capacity, &layout) != RS_OK) ||
         (core.input_words != (((active_width + 1U) / 2U) * active_height)) ||
         (core.input_pixels != (active_width * active_height)) ||
         (core.input_lines != active_height) || (core.output_words != layout.expected_words) ||
         (core.output_lines != layout.height) || ((core.fifo_levels >> 12U) > 8U))) {
        pass = false;
    }
    if (!rs_ppa_measure_end(id, pass ? frame.transport_bytes : 0U)) {
        pass = false;
    }
    printf("PPALITE_P4_CAPTURE id=%u pass=%u width=%u height=%u row=%lu stride=%lu valid=%lu "
           "transport=%lu job=%lu source=%lu\n",
           id, pass ? 1U : 0U, frame.width, frame.height, (unsigned long)frame.row_bytes,
           (unsigned long)frame.stride_bytes, (unsigned long)frame.valid_bytes,
           (unsigned long)frame.transport_bytes, (unsigned long)frame.job_sequence,
           (unsigned long)frame.source_sequence);
    printf("PPALITE_P4_CORE id=%u input_words=%lu input_pixels=%lu input_lines=%lu "
           "output_words=%lu output_lines=%lu input_stall=%lu output_stall=%lu high_water=%lu\n",
           id, (unsigned long)core.input_words, (unsigned long)core.input_pixels,
           (unsigned long)core.input_lines, (unsigned long)core.output_words,
           (unsigned long)core.output_lines, (unsigned long)core.input_stall_cycles,
           (unsigned long)core.output_stall_cycles, (unsigned long)(core.fifo_levels >> 12U));
    printf("PPALITE_P4_TIMING id=%u arm=%llu start=%llu wait=%llu rows=%u\n", id,
           (unsigned long long)timing.arm_cycles, (unsigned long long)timing.start_cycles,
           (unsigned long long)timing.wait_cycles, frame.height);
    if (pass && (result_frame != NULL)) {
        *result_frame = frame;
    }
    return pass;
}

static bool rs_ppa_raw_reference(void) {
    const rs_dvp_config_t config = {
        .format = RS_DVP_FORMAT_RGB565,
        .frame_width = 320U,
        .frame_height = 240U,
        .crop_width = 320U,
        .crop_height = 240U,
        .snapshot = true,
        .stream_enable = true,
    };
    volatile uint32_t *const frame = (volatile uint32_t *)RS_PPA_RAW_ADDR;
    rs_dvp_status_t source;
    rs_dma_status_t dma = {0};
    rs_xpi_error_t xpi;
    bool pass = rs_ppa_measure_begin();

    rs_ppa_external_guard_set(RS_PPA_RAW_ADDR, 38400U);
    if (pass) {
        pass = (rs_ppalite_select_route(RS_PPALITE_ROUTE_RAW, RS_TIMEOUT_DEFAULT) == RS_OK) &&
               (rs_dvp_configure(&config) == RS_OK) &&
               (rs_dvp_capture_dma(RS_PPA_RAW_ADDR, 38400U, RS_TIMEOUT_DEFAULT) == RS_OK);
    }
    if (pass) {
        pass = (rs_dvp_get_status(&source) == RS_OK) && (source.error_status == 0U) &&
               (source.word_count == 38400U) && (source.pixel_count == 76800U) &&
               (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma) == RS_OK) && dma.done && !dma.busy &&
               !dma.error && (dma.bytes_done == 153600U) && (dma.remaining == 0U) &&
               (rs_xpi_error_get(&xpi) == RS_OK) && !xpi.valid;
    }
    if (pass) {
        for (uint32_t index = 0U; index < 38400U; ++index) {
            if (frame[index] != rs_p9_frame_word(index / 160U, index % 160U, false)) {
                pass = false;
                break;
            }
        }
        pass = pass && rs_ppa_external_guards(RS_PPA_RAW_ADDR, 38400U);
    }
    if (!rs_ppa_measure_end(13U, pass ? 153600U : 0U)) {
        pass = false;
    }
    printf("PPALITE_P4_RAW pass=%u pixels=76800 bytes=153600 words=38400 dma_bytes=%lu\n",
           pass ? 1U : 0U, (unsigned long)dma.bytes_done);
    return pass;
}

static bool rs_ppa_recovery_case(void) {
    const rs_ppalite_config_t config = rs_ppa_small_config();
    rs_ppalite_session_t session = {0};
    rs_ppalite_frame_t frame = {0};
    rs_ppalite_status_t status;
    rs_status_t wait_result;
    rs_status_t abort_result;
    rs_status_t stopped_result;
    rs_status_t resumed_result;
    bool owned = false;
    bool pass = rs_ppa_measure_begin();

    rs_ppa_small.before[0] = RS_PPA_GUARD;
    rs_ppa_small.after[0] = RS_PPA_GUARD;
    if (pass) {
        pass = rs_ppalite_capture_begin(&session, &config, (uintptr_t)rs_ppa_small.data,
                                        sizeof(rs_ppa_small.data), RS_TIMEOUT_DEFAULT) == RS_OK;
    }
    if (pass) {
        pass = rs_ppalite_capture_start(&session, RS_TIMEOUT_DEFAULT) == RS_OK;
    }
    if (!pass) {
        if (session.acquired) {
            (void)rs_ppalite_abort(&session, RS_TIMEOUT_DEFAULT);
            (void)rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
        }
        (void)rs_ppa_measure_end(2U, 0U);
        return false;
    }
    printf("P9_CTRL stop_low\n");
    (void)rs_ppa_delay(32U);
    wait_result = rs_ppalite_capture_wait(&session, &frame, RS_PPA_SHORT_LIMIT);
    abort_result = rs_ppalite_abort(&session, RS_TIMEOUT_DEFAULT);
    stopped_result = rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
    owned = (rs_ppalite_get_status(&status) == RS_OK) && status.owned && session.acquired;
    printf("P9_CTRL resume\n");
    (void)rs_ppa_delay(100U);
    resumed_result = rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
    pass = (wait_result == RS_ETIMEOUT) && (abort_result == RS_OK) &&
           (stopped_result == RS_ETIMEOUT) && (resumed_result == RS_OK) && owned &&
           !session.acquired && !frame.valid && (rs_ppa_small.before[0] == RS_PPA_GUARD) &&
           (rs_ppa_small.after[0] == RS_PPA_GUARD);
    if (session.acquired) {
        (void)rs_ppalite_abort(&session, RS_TIMEOUT_DEFAULT);
        (void)rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
        pass = false;
    }
    if (pass) {
        rs_ppa_recovered = 1U;
    }
    if (!rs_ppa_measure_end(2U, 0U)) {
        pass = false;
    }
    printf("PPALITE_P4_RECOVERY pass=%u wait=%d abort=%d stopped=%d resumed=%d owned=%u valid=%u\n",
           pass ? 1U : 0U, wait_result, abort_result, stopped_result, resumed_result,
           owned ? 1U : 0U, frame.valid ? 1U : 0U);
    return pass;
}

static bool rs_ppa_sd_guards(void) {
    for (uint32_t index = 0U; index < 16U; ++index) {
        if ((rs_ppa_sd_tx.before[index] != RS_PPA_GUARD) ||
            (rs_ppa_sd_tx.after[index] != RS_PPA_GUARD) ||
            (rs_ppa_sd_rx.before[index] != RS_PPA_GUARD) ||
            (rs_ppa_sd_rx.after[index] != RS_PPA_GUARD)) {
            return false;
        }
    }
    return true;
}

static bool rs_ppa_sd_export(uint32_t id, const rs_ppalite_frame_t *frame,
                             const rs_sd_memory_info_t *card) {
    const volatile uint8_t *source;
    volatile uint8_t *transmit;
    volatile uint8_t *receive;
    bool pass;

    if ((frame == NULL) || (card == NULL) || !frame->valid ||
        ((frame->result_config & UINT32_C(0x10)) == 0U) || (frame->height != 120U) ||
        (frame->stride_bytes != 160U) || (frame->transport_bytes != 19200U) ||
        (((frame->row_bytes != 160U) || (frame->valid_bytes != 19200U)) &&
         ((frame->row_bytes != 159U) || (frame->valid_bytes != 19080U))) ||
        (card->capacity_blocks < 54U)) {
        return false;
    }
    source = (const volatile uint8_t *)frame->base;
    transmit = (volatile uint8_t *)rs_ppa_sd_tx.words;
    receive = (volatile uint8_t *)rs_ppa_sd_rx.words;
    for (uint32_t index = 0U; index < 16U; ++index) {
        rs_ppa_sd_tx.before[index] = RS_PPA_GUARD;
        rs_ppa_sd_tx.after[index] = RS_PPA_GUARD;
        rs_ppa_sd_rx.before[index] = RS_PPA_GUARD;
        rs_ppa_sd_rx.after[index] = RS_PPA_GUARD;
    }
    pass = rs_ppa_measure_begin();
    for (uint32_t chunk = 0U; (chunk < RS_PPA_SD_CHUNKS) && pass; ++chunk) {
        const uint32_t offset = chunk * 1024U;
        const uint32_t block = 16U + (chunk * 2U);
        for (uint32_t index = 0U; index < 1024U; ++index) {
            const uint32_t logical = offset + index;
            const uint32_t row = logical / frame->row_bytes;
            const uint32_t column = logical % frame->row_bytes;
            transmit[index] =
                logical < frame->valid_bytes ? source[(row * frame->stride_bytes) + column] : 0U;
            receive[index] = UINT8_C(0xDE);
        }
        if (rs_sd_memory_write_blocks(RS_SDIO_INSTANCE_0, card, block, 2U, rs_ppa_sd_tx.words,
                                      RS_TIMEOUT_DEFAULT) != RS_OK) {
            pass = false;
            break;
        }
        if (rs_sd_memory_read_blocks(RS_SDIO_INSTANCE_0, card, block, 2U, rs_ppa_sd_rx.words,
                                     RS_TIMEOUT_DEFAULT) != RS_OK) {
            pass = false;
            break;
        }
        for (uint32_t index = 0U; index < 1024U; ++index) {
            const uint32_t logical = offset + index;
            const uint32_t row = logical / frame->row_bytes;
            const uint32_t column = logical % frame->row_bytes;
            const uint8_t expected =
                logical < frame->valid_bytes ? source[(row * frame->stride_bytes) + column] : 0U;
            if (receive[index] != expected) {
                pass = false;
                break;
            }
        }
        pass = pass && rs_ppa_sd_guards();
    }
    if (!rs_ppa_measure_end(id, pass ? frame->valid_bytes : 0U)) {
        pass = false;
    }
    printf("PPALITE_P4_SD id=%u pass=%u first_lba=16 last_lba=53 blocks=38 bytes=%lu row=%lu "
           "stride=%lu stripped=%u readback=%u\n",
           id, pass ? 1U : 0U, (unsigned long)frame->valid_bytes, (unsigned long)frame->row_bytes,
           (unsigned long)frame->stride_bytes, frame->row_bytes < frame->stride_bytes ? 1U : 0U,
           pass ? 1U : 0U);
    return pass;
}

static bool rs_ppa_display(uint32_t id, const rs_ppalite_frame_t *frame) {
    const rs_st7789vi_window_t window = {0U, 0U, frame->width - 1U, frame->height - 1U};
    rs_st7789vi_dma_measurement_t measurement = {0};
    rs_status_t result;
    bool pass = rs_ppa_measure_begin();

    if (pass) {
        result = rs_st7789vi_display_frame(&window, frame, &rs_ppa_display_session, &measurement,
                                           RS_TIMEOUT_DEFAULT);
    } else {
        result = RS_EIO;
    }
    if (!rs_ppa_measure_end(id, (result == RS_OK) ? frame->valid_bytes : 0U)) {
        pass = false;
    }
    if ((result != RS_OK) || (measurement.chunks != frame->height) ||
        (measurement.frames !=
         (frame->output_byte_swap ? frame->valid_bytes : (uint32_t)frame->width * frame->height)) ||
        (measurement.payload_bytes != frame->valid_bytes) ||
        (measurement.transport_words != (frame->transport_bytes / sizeof(uint32_t))) ||
        (measurement.tx_fifo_final != 0U) || (measurement.divider == 0U)) {
        pass = false;
    }
    printf("PPALITE_P4_DISPLAY id=%u pass=%u pixels=%u payload=%lu transport=%lu chunks=%lu "
           "frame16=%u\n",
           id, pass ? 1U : 0U, (uint32_t)frame->width * frame->height,
           (unsigned long)measurement.payload_bytes, (unsigned long)measurement.transport_words,
           (unsigned long)measurement.chunks, measurement.frames == frame->valid_bytes ? 0U : 1U);
    return pass;
}

int main(void) {
    const rs_ppalite_config_t small = rs_ppa_small_config();
    const rs_ppalite_config_t gray = rs_ppa_qvga_config(true);
    const rs_ppalite_config_t rgb = rs_ppa_qvga_config(false);
    const rs_ppalite_config_t odd = rs_ppa_odd_config();
    const rs_ppalite_config_t full = rs_ppa_full_gray_config();
    const rs_ppalite_config_t padded = rs_ppa_padded_gray_config();
    const rs_spi_config_t spi_config = {
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
    rs_tiny_rcu_snapshot_t clock;
    rs_xpi_psram_t psram;
    rs_sd_memory_info_t card;
    rs_ppalite_info_t info;
    rs_ppalite_frame_t gray_frame = {0};
    rs_ppalite_frame_t rgb_frame = {0};
    rs_ppalite_frame_t odd_frame = {0};
    rs_ppalite_frame_t full_frame = {0};
    rs_ppalite_frame_t padded_frame = {0};
    rs_status_t cleanup;
    uint8_t code = 0U;

    __disable_irq();
    if ((rs_tiny_rcu_get_snapshot(&clock) != RS_OK) || !rs_p9_console_ready(&clock, rs_uart_init) ||
        (clock.sys_hz != UINT32_C(24000000)) || (clock.mem_hz != UINT32_C(24000000)) ||
        (clock.pclk_hz != UINT32_C(24000000)) || !rs_p9_psram_pin_ready(rs_gpio_configure) ||
        !rs_ppa_pins(12U, 23U, RS_GPIO_MODE_ALT1) || !rs_ppa_pins(0U, 5U, RS_GPIO_MODE_ALT0) ||
        (rs_tiny_rcu_set_clkout(1U, 1U) != RS_OK)) {
        code = 1U;
    }
    if (code == 0U) {
        printf("P9_CTRL camera\n");
        if (!rs_ppa_delay(32U) || (rs_ppalite_probe(&info) != RS_OK) ||
            (info.capability != UINT32_C(0x000003FF)) ||
            (rs_ppalite_select_route(RS_PPALITE_ROUTE_PROCESS, RS_TIMEOUT_DEFAULT) != RS_OK) ||
            (rs_xpi_psram_initialize(clock.mem_hz, RS_TIMEOUT_DEFAULT, &psram) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_RAW_ADDR, 153600U, 4U) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_GRAY_ADDR, 19200U, 4U) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_RGB_ADDR, 38400U, 4U) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_ODD_ADDR, 38400U, 4U) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_FULL_ADDR, 76800U, 4U) != RS_OK) ||
            (rs_xpi_psram_validate_dma(&psram, RS_PPA_PADDED_ADDR, 19200U, 4U) != RS_OK) ||
            (rs_sd_memory_initialize(RS_SDIO_INSTANCE_0, clock.pclk_hz, &card,
                                     RS_TIMEOUT_DEFAULT) != RS_OK) ||
            (card.capacity_blocks < 54U) || (card.actual_clock_hz != UINT32_C(12000000)) ||
            !rs_ppa_display_pins() || (rs_spi_configure(&spi_config) != RS_OK) ||
            (rs_spi_acquire(RS_TIMEOUT_DEFAULT) != RS_OK) ||
            (rs_st7789vi_init(RS_ST7789VI_ROTATION_NORMAL) != RS_OK) ||
            (rs_dma_session_acquire(&rs_ppa_display_session, RS_DMA_CHANNEL_BULK) != RS_OK)) {
            code = 2U;
        }
    }
    if (code == 0U) {
        rs_ppa_small.before[0] = RS_PPA_GUARD;
        rs_ppa_small.after[0] = RS_PPA_GUARD;
        if (!rs_ppa_run_capture(1U, &small, (uintptr_t)rs_ppa_small.data, sizeof(rs_ppa_small.data),
                                NULL) ||
            (rs_ppa_small.before[0] != RS_PPA_GUARD) || (rs_ppa_small.after[0] != RS_PPA_GUARD)) {
            code = 3U;
        }
    }
    if ((code == 0U) && !rs_ppa_recovery_case()) {
        code = 4U;
    }
    if ((code == 0U) && !rs_ppa_run_capture(3U, &small, (uintptr_t)rs_ppa_small.data,
                                            sizeof(rs_ppa_small.data), NULL)) {
        code = 5U;
    }
    if ((code == 0U) && !rs_ppa_run_capture(4U, &gray, RS_PPA_GRAY_ADDR, 19200U, &gray_frame)) {
        code = 6U;
    }
    if ((code == 0U) && !rs_ppa_sd_export(7U, &gray_frame, &card)) {
        code = 7U;
    }
    if ((code == 0U) && !rs_ppa_run_capture(5U, &rgb, RS_PPA_RGB_ADDR, 38400U, &rgb_frame)) {
        code = 8U;
    }
    if ((code == 0U) && !rs_ppa_display(8U, &rgb_frame)) {
        code = 9U;
    }
    if ((code == 0U) && !rs_ppa_run_capture(6U, &odd, RS_PPA_ODD_ADDR, 38400U, &odd_frame)) {
        code = 10U;
    }
    if ((code == 0U) && !rs_ppa_display(9U, &odd_frame)) {
        code = 11U;
    }
    if ((code == 0U) && !rs_ppa_run_capture(10U, &full, RS_PPA_FULL_ADDR, 76800U, &full_frame)) {
        code = 12U;
    }
    if ((code == 0U) &&
        !rs_ppa_run_capture(11U, &padded, RS_PPA_PADDED_ADDR, 19200U, &padded_frame)) {
        code = 13U;
    }
    if ((code == 0U) && !rs_ppa_sd_export(12U, &padded_frame, &card)) {
        code = 14U;
    }
    if ((code == 0U) && !rs_ppa_raw_reference()) {
        code = 15U;
    }
    if (code != 0U) {
        (void)rs_spi_abort(RS_TIMEOUT_DEFAULT);
        (void)rs_spi_recover(RS_TIMEOUT_DEFAULT);
    }
    cleanup = rs_dma_session_release(&rs_ppa_display_session);
    if ((cleanup != RS_OK) || (rs_spi_release(RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_ppalite_select_route(RS_PPALITE_ROUTE_RAW, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_tiny_rcu_set_clkout(0U, 0U) != RS_OK)) {
        code = 16U;
    }
    if ((rs_ppa_valid_frames != 7U) || (rs_ppa_recovered != 1U)) {
        code = 17U;
    }
    rs_sysctrl_write_test_status(code == 0U, code);
    printf("PPALITE_P4_RESULT code=%u frames=%u recovered=%u\n", code, rs_ppa_valid_frames,
           rs_ppa_recovered);
    for (;;) {
    }
}
