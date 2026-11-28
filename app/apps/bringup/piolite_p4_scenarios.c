#include "piolite_p4_scenarios.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/piolite.h>
#include <retrosoc/lib/console.h>
#include <retrosoc/lib/printf.h>

#include "piolite_p4_examples.h"

#if defined(RS_PIOLITE_P4_SCENARIO_LOGIC_CAPTURE) || defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
#include "logic_capture.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_PULSE)
#include "pulse_capture.c"
#include "pulse_generate.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_UART)
#include "uart_rx.c"
#include "uart_tx.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_SPI)
#include "spi_master.c"
#include "spi_master_mode1.c"
#include "spi_master_mode2.c"
#include "spi_master_mode3.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_IR)
#include "ir_rx.c"
#include "ir_tx.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_LED)
#include "led_scan.c"
#endif
#if defined(RS_PIOLITE_P4_SCENARIO_GAMEPAD)
#include "gamepad.c"
#endif

#if defined(RS_PIOLITE_P4_TIMEOUT)
#error "RS_PIOLITE_P4_TIMEOUT is fixed by PIOLITE-P4 acceptance"
#endif
#define RS_PIOLITE_P4_TIMEOUT       UINT32_C(4000000)
#define RS_PIOLITE_P4_CAPTURE_WORDS UINT32_C(8192)
#define RS_PIOLITE_P4_REPORT_BYTES  8192U

static char rs_p4_report[RS_PIOLITE_P4_REPORT_BYTES];
static size_t rs_p4_report_length;
static bool rs_p4_report_truncated;

void rs_p4_report_printf(const char *format, ...) {
    va_list args;
    int result;
    if ((format == NULL) || (rs_p4_report_length >= RS_PIOLITE_P4_REPORT_BYTES)) {
        rs_p4_report_truncated = true;
        return;
    }
    va_start(args, format);
    result = rs_vsnprintf(&rs_p4_report[rs_p4_report_length],
                          RS_PIOLITE_P4_REPORT_BYTES - rs_p4_report_length, format, args);
    va_end(args);
    if (result < 0) {
        rs_p4_report_truncated = true;
        return;
    }
    if ((size_t)result >= (RS_PIOLITE_P4_REPORT_BYTES - rs_p4_report_length)) {
        rs_p4_report_length = RS_PIOLITE_P4_REPORT_BYTES - 1U;
        rs_p4_report[rs_p4_report_length] = '\0';
        rs_p4_report_truncated = true;
        return;
    }
    rs_p4_report_length += (size_t)result;
}

bool rs_p4_report_overflow(void) {
    return rs_p4_report_truncated;
}

void rs_p4_report_flush(void) {
    rs_p4_report[rs_p4_report_length] = '\0';
    print(rs_p4_report);
}

static rs_piolite_p4_session_t rs_p4_session;
#if defined(RS_PIOLITE_P4_SCENARIO_LOGIC_CAPTURE) || defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
static uint32_t rs_p4_capture[RS_PIOLITE_P4_CAPTURE_WORDS] __attribute__((aligned(64)));
static uint32_t rs_p4_capture_guard[2];

static uint8_t rs_p4_next_sample(uint8_t value, uint32_t pattern) {
    if (pattern == 0U) {
        return (uint8_t)(value + 1U);
    }
    if (pattern == 1U) {
        return (uint8_t)((value >> 1U) ^ (((value & 1U) != 0U) ? UINT8_C(0xB8) : UINT8_C(0)));
    }
    return (uint8_t)(value + UINT8_C(73));
}

static uint32_t rs_p4_fnv_byte(uint32_t hash, uint8_t value) {
    return (hash ^ value) * UINT32_C(16777619);
}

#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
static uint32_t rs_p4_contend_source[RS_PIOLITE_P4_CAPTURE_WORDS] __attribute__((aligned(64)));
static uint32_t rs_p4_contend_destination[RS_PIOLITE_P4_CAPTURE_WORDS] __attribute__((aligned(64)));
static uint32_t rs_p4_contend_heartbeat;
static uint32_t rs_p4_contend_iterations;
static bool rs_p4_contend_background_done;

static rs_status_t rs_p4_wait_heartbeat(uint32_t timeout, rs_dma_session_t *background,
                                        const rs_dma_config_t *config) {
    rs_p4_contend_heartbeat = 0U;
    while (timeout-- != 0U) {
        rs_dma_status_t dma_status;
        if (rs_dma_get_status(1U, &dma_status) != RS_OK) {
            return RS_EIO;
        }
        if (dma_status.error || dma_status.aborted ||
            (dma_status.done && (dma_status.bytes_done != config->byte_count))) {
            return RS_EIO;
        }
        if (dma_status.done && !dma_status.busy) {
            const rs_status_t start_status = rs_dma_session_start(background);
            if (start_status != RS_OK) {
                return start_status;
            }
            ++rs_p4_contend_iterations;
        }
        const rs_status_t status = rs_piolite_wait_done(&rs_p4_session.session, 0U, 1U);
        ++rs_p4_contend_heartbeat;
        if (status != RS_ETIMEOUT) {
            return status;
        }
    }
    return RS_ETIMEOUT;
}
#endif

static rs_status_t rs_p4_logic_once(uint32_t pattern, uint8_t *first, uint8_t *last,
                                    uint32_t *fnv) {
    const rs_piolite_p4_sm_options_t options = {
        .program = &piolite_p1_logic_capture,
        .divider = 12U,
    };
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_PIOLITE_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)rs_p4_capture,
        .byte_count = RS_PIOLITE_P4_CAPTURE_WORDS * 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 16U,
    };
    rs_piolite_status_t sm_status;
    rs_status_t status = rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
    uint32_t sample_count = 0U;
    uint8_t previous = 0U;
#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
    rs_dma_session_t background;
    rs_dma_config_t background_config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_p4_contend_source,
        .destination = (uintptr_t)rs_p4_contend_destination,
        .byte_count = RS_PIOLITE_P4_CAPTURE_WORDS * 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 16U,
    };
    bool background_acquired = false;
    rs_p4_contend_background_done = false;
    for (uint32_t index = 0U; index < RS_PIOLITE_P4_CAPTURE_WORDS; ++index) {
        rs_p4_contend_source[index] = UINT32_C(0xA5C30000) ^ (pattern << 24U) ^ index;
        rs_p4_contend_destination[index] = UINT32_C(0xCCCCCCCC);
    }
#endif
    *fnv = UINT32_C(2166136261);
    *first = 0U;
    *last = 0U;
    for (uint32_t index = 0U; index < RS_PIOLITE_P4_CAPTURE_WORDS; ++index) {
        rs_p4_capture[index] = UINT32_C(0xCCCCCCCC);
    }
    rs_p4_capture_guard[0] = UINT32_C(0x13579BDF);
    rs_p4_capture_guard[1] = UINT32_C(0x2468ACE0);
#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
    if (status == RS_OK) {
        status = rs_dma_session_acquire(&background, 1U);
        background_acquired = status == RS_OK;
    }
    if (status == RS_OK) {
        status = rs_dma_session_configure(&background, &background_config);
    }
    if (status == RS_OK) {
        status = rs_dma_session_start(&background);
        rs_p4_contend_iterations = 1U;
    }
#endif
    if (status == RS_OK) {
        status = rs_piolite_p4_dma_begin(&rs_p4_session, RS_PIOLITE_RX, 0U, 2U, &config,
                                         RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
        status = rs_p4_wait_heartbeat(RS_PIOLITE_P4_TIMEOUT, &background, &background_config);
#else
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
#endif
    }
    if (status == RS_OK) {
        status = rs_piolite_get_status(&rs_p4_session.session, 0U, &sm_status);
    }
    if ((status == RS_OK) &&
        (((sm_status.events & (UINT32_C(1) << RS_PIOLITE_ABI_EVENTS_RX_STALL)) != 0U) ||
         (sm_status.rx_stall_count != 0U))) {
        status = RS_EIO;
    }
    if (status == RS_OK) {
        for (uint32_t index = 0U; index < RS_PIOLITE_P4_CAPTURE_WORDS; ++index) {
            for (uint32_t lane = 0U; lane < 4U; ++lane) {
                const uint8_t value = (uint8_t)(rs_p4_capture[index] >> (lane * 8U));
                if ((sample_count != 0U) && (value != rs_p4_next_sample(previous, pattern))) {
                    status = RS_EIO;
                    break;
                }
                if (sample_count == 0U) {
                    *first = value;
                }
                previous = value;
                *last = value;
                *fnv = rs_p4_fnv_byte(*fnv, value);
                ++sample_count;
            }
            if (status != RS_OK) {
                break;
            }
        }
    }
    if ((sample_count != UINT32_C(32768)) || (rs_p4_capture_guard[0] != UINT32_C(0x13579BDF)) ||
        (rs_p4_capture_guard[1] != UINT32_C(0x2468ACE0))) {
        if (status == RS_OK) {
            status = RS_EIO;
        }
    }
#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
    if (background_acquired) {
        rs_status_t background_status = rs_dma_wait(1U, RS_PIOLITE_P4_TIMEOUT);
        rs_status_t release_status;
        bool data_ok = true;
        if (background_status != RS_OK) {
            (void)rs_dma_session_abort_wait(&background, RS_PIOLITE_P4_TIMEOUT);
        } else {
            for (uint32_t index = 0U; index < RS_PIOLITE_P4_CAPTURE_WORDS; ++index) {
                if (rs_p4_contend_destination[index] != rs_p4_contend_source[index]) {
                    data_ok = false;
                    break;
                }
            }
        }
        release_status = rs_dma_session_release(&background);
        rs_p4_contend_background_done = (background_status == RS_OK) && (release_status == RS_OK) &&
                                        data_ok && (rs_p4_contend_iterations >= 2U);
        if ((status == RS_OK) && !rs_p4_contend_background_done) {
            status = background_status == RS_OK ? RS_EIO : background_status;
        }
    }
#endif
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_LOGIC_CAPTURE)
static uint8_t rs_p4_run_logic(void) {
    for (uint32_t pattern = 0U; pattern < 3U; ++pattern) {
        uint8_t first;
        uint8_t last;
        uint32_t fnv;
        const rs_status_t status = rs_p4_logic_once(pattern, &first, &last, &fnv);
        if (status != RS_OK) {
            rs_p4_report_printf("PIOLITE_P4_LOGIC pattern=%u error=%d\n", (unsigned int)pattern,
                                (int)status);
            return (uint8_t)(10U + pattern);
        }
        rs_p4_report_printf(
            "PIOLITE_P4_LOGIC pattern=%u samples=32768 words=8192 first=%02x last=%02x fnv=%08x "
            "stalls=0\n",
            (unsigned int)pattern, (unsigned int)first, (unsigned int)last, (unsigned int)fnv);
    }
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
static uint8_t rs_p4_run_contention(void) {
    for (uint32_t pattern = 0U; pattern < 3U; ++pattern) {
        uint8_t first;
        uint8_t last;
        uint32_t fnv;
        const rs_status_t status = rs_p4_logic_once(pattern, &first, &last, &fnv);
        if ((status != RS_OK) || !rs_p4_contend_background_done ||
            (rs_p4_contend_heartbeat == 0U) || (rs_p4_contend_iterations < 2U)) {
            rs_p4_report_printf("PIOLITE_P4_CONTEND pattern=%u error=%d bg_done=%u heartbeat=%u\n",
                                (unsigned int)pattern, (int)status,
                                (unsigned int)rs_p4_contend_background_done,
                                (unsigned int)rs_p4_contend_heartbeat);
            return (uint8_t)(15U + pattern);
        }
        rs_p4_report_printf(
            "PIOLITE_P4_LOGIC pattern=%u samples=32768 words=8192 first=%02x last=%02x fnv=%08x "
            "stalls=0\n",
            (unsigned int)pattern, (unsigned int)first, (unsigned int)last, (unsigned int)fnv);
        rs_p4_report_printf("PIOLITE_P4_CONTEND pattern=%u bg_done=1 heartbeat=%u iterations=%u\n",
                            (unsigned int)pattern, (unsigned int)rs_p4_contend_heartbeat,
                            (unsigned int)rs_p4_contend_iterations);
    }
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_PULSE)
static uint32_t rs_p4_pulse_tx[2] __attribute__((aligned(64)));
static uint8_t rs_p4_pulse_stage;

static rs_status_t rs_p4_pulse_start(uint16_t high, uint16_t low) {
    const rs_piolite_p4_sm_options_t generator = {
        .program = &piolite_p1_pulse_generate,
        .divider = 1U,
    };
    const rs_piolite_p4_sm_options_t capture = {
        .program = &piolite_p1_pulse_capture,
        .divider = 1U,
    };
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)rs_p4_pulse_tx,
        .destination = (uintptr_t)0U,
        .byte_count = 8U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 2U,
    };
    rs_status_t status;
    rs_p4_pulse_tx[0] = high;
    rs_p4_pulse_tx[1] = low;
    rs_p4_pulse_stage = 1U;
    status = rs_piolite_p4_open(&rs_p4_session, &generator, &capture, RS_PIOLITE_P4_TIMEOUT);
    if (status == RS_OK) {
        rs_p4_pulse_stage = 2U;
        status = rs_piolite_p4_dma_begin(&rs_p4_session, RS_PIOLITE_TX, 0U, 3U, &config,
                                         RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        rs_p4_pulse_stage = 3U;
        status = rs_piolite_start(&rs_p4_session.session, 3U);
    }
    return status;
}

static rs_status_t rs_p4_pulse_once(uint16_t high, uint16_t low, uint32_t *captured) {
    rs_piolite_status_t status_snapshot;
    rs_status_t status = rs_p4_pulse_start(high, low);
    *captured = 0U;
    if (status == RS_OK) {
        rs_p4_pulse_stage = 4U;
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
        rs_p4_pulse_stage = 5U;
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 1U, &status_snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if (((status_snapshot.fifo_levels >> 8U) & 0xFU) != 0U) {
                status = rs_piolite_read(&rs_p4_session.session, 1U, captured);
                break;
            }
        }
    }
    if (status == RS_OK) {
        *captured = UINT32_C(2) * (UINT32_C(65536) - *captured);
        status = rs_piolite_wait_done(&rs_p4_session.session, 1U, RS_PIOLITE_P4_TIMEOUT);
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_pulse_abort(void) {
    rs_piolite_status_t snapshot;
    rs_status_t status = rs_p4_pulse_start(UINT16_MAX, UINT16_MAX);
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    if (status == RS_OK) {
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 0U, &snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if ((snapshot.pc & 0x1FU) == 9U) {
                status = RS_OK;
                break;
            }
        }
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_run_pulse(void) {
    static const uint16_t durations[6][2] = {
        {3U, 5U}, {8U, 2U}, {1U, 1U}, {0U, 1U}, {1U, 0U}, {UINT16_MAX, 1U},
    };
    for (uint32_t index = 0U; index < 6U; ++index) {
        uint32_t captured;
        const rs_status_t status =
            rs_p4_pulse_once(durations[index][0], durations[index][1], &captured);
        if (status != RS_OK) {
            rs_p4_report_printf("PIOLITE_P4_PULSE case=%u error=%d stage=%u open=%u cleanup=%d\n",
                                (unsigned int)index, (int)status, (unsigned int)rs_p4_pulse_stage,
                                (unsigned int)rs_p4_session.open_stage,
                                (int)rs_p4_session.cleanup_status);
            return (uint8_t)((rs_p4_pulse_stage << 4U) | ((uint8_t)(-status) & 0xFU));
        }
        rs_p4_report_printf("PIOLITE_P4_PULSE case=%u high=%u low=%u capture=%u done=1\n",
                            (unsigned int)index, (unsigned int)durations[index][0],
                            (unsigned int)durations[index][1], (unsigned int)captured);
    }
    if (rs_p4_pulse_abort() != RS_OK) {
        return 30U;
    }
    rs_p4_report_printf("PIOLITE_P4_PULSE_ABORT complete=1\n");
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_SPI)
static uint32_t rs_p4_spi_tx __attribute__((aligned(64)));
static uint32_t rs_p4_spi_rx[4] __attribute__((aligned(64)));

static const rs_piolite_program_t *rs_p4_spi_program(uint32_t mode) {
    switch (mode) {
    case 0U:
        return &piolite_p1_spi_master;
    case 1U:
        return &piolite_p1_spi_master_mode1;
    case 2U:
        return &piolite_p1_spi_master_mode2;
    default:
        return &piolite_p1_spi_master_mode3;
    }
}

static uint32_t rs_p4_spi_mask(uint32_t width) {
    return width == 32U ? UINT32_MAX : ((UINT32_C(1) << width) - 1U);
}

static uint32_t rs_p4_spi_tx_pattern(uint32_t mode, uint32_t width) {
    return (UINT32_C(0xA5C33C96) ^ (mode * UINT32_C(0x00102040)) ^ (width << 1U)) &
           rs_p4_spi_mask(width);
}

static uint32_t rs_p4_spi_rx_pattern(uint32_t mode, uint32_t width) {
    return (UINT32_C(0x5A3CC35A) ^ (mode * UINT32_C(0x01020408)) ^ width) & rs_p4_spi_mask(width);
}

static rs_status_t rs_p4_spi_starvation(void) {
    const rs_piolite_p4_sm_options_t options = {
        .program = &piolite_p1_spi_master,
        .divider = 2U,
        .initial_value = 0x20U,
        .initial_xy = UINT32_C(7) << 16U,
    };
    rs_piolite_status_t snapshot = {0};
    uint8_t stage = 1U;
    rs_status_t status = rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    if (status == RS_OK) {
        stage = 2U;
        status = rs_piolite_flag_clear(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
        stage = 3U;
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
        stage = 4U;
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 0U, &snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if (((snapshot.pc & 0x1FU) == 1U) && ((snapshot.status & 0x70U) == 0x30U)) {
                status = RS_OK;
                break;
            }
        }
    }
    if (status != RS_OK) {
        rs_p4_report_printf(
            "PIOLITE_P4_SPI_DEBUG stage=%u open=%u error=%d active=%u claimed=%u pc=%u status=%08x "
            "fault=%08x cleanup=%d\n",
            (unsigned int)stage, (unsigned int)rs_p4_session.open_stage, (int)status,
            (unsigned int)rs_p4_session.session.active, (unsigned int)rs_p4_session.session.claimed,
            (unsigned int)snapshot.pc, (unsigned int)snapshot.status, (unsigned int)snapshot.fault,
            (int)rs_p4_session.cleanup_status);
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_spi_stage;

static rs_status_t rs_p4_spi_transfer(uint32_t mode, uint32_t width, uint32_t *observed_rx) {
    const rs_piolite_p4_sm_options_t options = {
        .program = rs_p4_spi_program(mode),
        .divider = 2U,
        .initial_value = ((mode & 1U) != 0U) ? 0x30U : 0x20U,
        .initial_xy = (width - 1U) << 16U,
        .tx_bits = (uint8_t)width,
    };
    rs_dma_config_t tx_config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)&rs_p4_spi_tx,
        .destination = (uintptr_t)0U,
        .byte_count = 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 1U,
    };
    rs_dma_config_t rx_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_PIOLITE_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)rs_p4_spi_rx,
        .byte_count = (width / 8U) * 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 1U,
    };
    rs_status_t status;
    *observed_rx = 0U;
    rs_p4_spi_tx = rs_p4_spi_tx_pattern(mode, width);
    for (uint32_t index = 0U; index < 4U; ++index) {
        rs_p4_spi_rx[index] = UINT32_C(0xCCCCCCCC);
    }
    rs_p4_spi_stage = 1U;
    status = rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
    if (status == RS_OK) {
        rs_p4_spi_stage = 2U;
        status = rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_RX, 0U, 2U,
                                     RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_TX, 0U, 3U,
                                     RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        rs_p4_spi_stage = 3U;
        status = rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_RX, &rx_config);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_TX, &tx_config);
    }
    if (status == RS_OK) {
        rs_p4_spi_stage = 4U;
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
        rs_p4_spi_stage = 5U;
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        rs_p4_spi_stage = 6U;
        for (uint32_t index = 0U; index < (width / 8U); ++index) {
            if ((rs_p4_spi_rx[index] & UINT32_C(0xFFFFFF00)) != 0U) {
                status = RS_EIO;
                break;
            }
            *observed_rx |= rs_p4_spi_rx[index] << (index * 8U);
        }
        if (*observed_rx != rs_p4_spi_rx_pattern(mode, width)) {
            status = RS_EIO;
        }
    }
    if (status == RS_OK) {
        rs_p4_spi_stage = 7U;
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_run_spi(void) {
    rs_piolite_info_t info;
    if (rs_piolite_probe(&info) != RS_OK) {
        return 40U;
    }
    if (rs_p4_spi_starvation() != RS_OK) {
        return 41U;
    }
    rs_p4_report_printf("PIOLITE_P4_SPI_STARVATION safe=1\n");
    for (uint32_t mode = 0U; mode < 4U; ++mode) {
        for (uint32_t width_index = 0U; width_index < 3U; ++width_index) {
            const uint32_t width = UINT32_C(8) << width_index;
            uint32_t observed_rx;
            const rs_status_t status = rs_p4_spi_transfer(mode, width, &observed_rx);
            if (status != RS_OK) {
                rs_p4_report_printf("PIOLITE_P4_SPI mode=%u width=%u error=%d\n",
                                    (unsigned int)mode, (unsigned int)width, (int)status);
                const uint8_t reason =
                    rs_p4_spi_stage == 7U ? rs_p4_session.open_stage : (uint8_t)(-status);
                return (uint8_t)((rs_p4_spi_stage << 4U) | (reason & 0xFU));
            }
            rs_p4_report_printf("PIOLITE_P4_SPI mode=%u width=%u tx=%08x rx=%08x rate=%u\n",
                                (unsigned int)mode, (unsigned int)width,
                                (unsigned int)rs_p4_spi_tx_pattern(mode, width),
                                (unsigned int)observed_rx, (unsigned int)(info.clock_hz / 24U));
        }
    }
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_UART)
#define RS_PIOLITE_P4_UART_BYTES 16U
static uint32_t rs_p4_uart_tx[RS_PIOLITE_P4_UART_BYTES] __attribute__((aligned(64)));
static uint32_t rs_p4_uart_rx[RS_PIOLITE_P4_UART_BYTES] __attribute__((aligned(64)));

static uint8_t rs_p4_uart_byte(uint32_t phase, uint32_t index) {
    static const uint8_t prefixes[4] = {0x00U, 0xFFU, 0xA5U, 0x5AU};
    if (index < 4U) {
        return prefixes[index] ^ (uint8_t)phase;
    }
    return (uint8_t)((index * 73U) + (phase * 29U) + ((index >> 2U) * 11U));
}

static uint8_t rs_p4_uart_stage;

static rs_status_t rs_p4_uart_duplex(uint32_t phase, uint32_t *fnv) {
    const rs_piolite_p4_sm_options_t transmitter = {
        .program = &piolite_p1_uart_tx,
        .divider = 26U,
        .initial_value = 1U,
        .initial_xy = RS_PIOLITE_P4_UART_BYTES << 16U,
    };
    const rs_piolite_p4_sm_options_t receiver = {
        .program = &piolite_p1_uart_rx,
        .divider = 26U,
        .initial_xy = RS_PIOLITE_P4_UART_BYTES << 16U,
    };
    rs_dma_config_t tx_config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)rs_p4_uart_tx,
        .destination = (uintptr_t)0U,
        .byte_count = RS_PIOLITE_P4_UART_BYTES * 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 4U,
    };
    rs_dma_config_t rx_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_PIOLITE_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)rs_p4_uart_rx,
        .byte_count = RS_PIOLITE_P4_UART_BYTES * 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 4U,
    };
    rs_piolite_status_t tx_status;
    rs_piolite_status_t rx_status;
    rs_status_t status;
    *fnv = UINT32_C(2166136261);
    for (uint32_t index = 0U; index < RS_PIOLITE_P4_UART_BYTES; ++index) {
        rs_p4_uart_tx[index] = rs_p4_uart_byte(phase, index);
        rs_p4_uart_rx[index] = UINT32_C(0xCCCCCCCC);
    }
    rs_p4_uart_stage = 1U;
    status = rs_piolite_p4_open(&rs_p4_session, &transmitter, &receiver, RS_PIOLITE_P4_TIMEOUT);
    if (status == RS_OK) {
        rs_p4_uart_stage = 2U;
        status = rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_RX, 1U, 2U,
                                     RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_TX, 0U, 3U,
                                     RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        rs_p4_uart_stage = 3U;
        status = rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_RX, &rx_config);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_TX, &tx_config);
    }
    if (status == RS_OK) {
        rs_p4_uart_stage = 4U;
        status = rs_piolite_start(&rs_p4_session.session, 3U);
    }
    if (status == RS_OK) {
        rs_p4_uart_stage = 5U;
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        rs_p4_uart_stage = 6U;
        status = rs_piolite_wait_done(&rs_p4_session.session, 1U, RS_PIOLITE_P4_TIMEOUT);
    }
    rs_p4_uart_stage = 7U;
    if ((status == RS_OK) &&
        ((rs_piolite_get_status(&rs_p4_session.session, 0U, &tx_status) != RS_OK) ||
         (rs_piolite_get_status(&rs_p4_session.session, 1U, &rx_status) != RS_OK))) {
        status = RS_EIO;
    }
    if ((status == RS_OK) &&
        ((tx_status.shift_counts != 0U) || (rx_status.shift_counts != 0U) ||
         (tx_status.tx_stall_count != 0U) || (rx_status.rx_stall_count != 0U))) {
        status = RS_EIO;
    }
    rs_p4_uart_stage = 8U;
    if (status == RS_OK) {
        for (uint32_t index = 0U; index < RS_PIOLITE_P4_UART_BYTES; ++index) {
            const uint8_t expected = rs_p4_uart_byte(phase, index);
            if ((rs_p4_uart_rx[index] & UINT32_C(0xFFFFFF00)) != 0U) {
                status = RS_EIO;
                break;
            }
            if ((uint8_t)rs_p4_uart_rx[index] != expected) {
                status = RS_EIO;
                break;
            }
            *fnv = (*fnv ^ expected) * UINT32_C(16777619);
        }
    }
    if (status == RS_OK) {
        rs_p4_uart_stage = 9U;
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_uart_single(const rs_piolite_program_t *program, uint32_t initial_value) {
    const rs_piolite_p4_sm_options_t options = {
        .program = program,
        .divider = 26U,
        .initial_value = initial_value,
        .initial_xy = UINT32_C(0xFFFF) << 16U,
    };
    rs_status_t status = rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    return status;
}

static rs_status_t rs_p4_uart_wait_fault(uint32_t kind) {
    rs_piolite_status_t snapshot;
    rs_status_t status = (kind != 1U) ? rs_p4_uart_single(&piolite_p1_uart_rx, 0U)
                                      : rs_p4_uart_single(&piolite_p1_uart_tx, 1U);
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    if (status == RS_OK) {
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 0U, &snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if (((kind == 0U) &&
                 ((snapshot.events & (UINT32_C(1) << RS_PIOLITE_ABI_EVENTS_RX_STALL)) != 0U)) ||
                ((kind == 1U) && ((snapshot.pc & 0x1FU) == 2U) &&
                 ((snapshot.status & 0x70U) == 0x30U)) ||
                ((kind == 2U) && ((snapshot.pc & 0x1FU) == 10U) &&
                 ((snapshot.status & 0x70U) == 0x10U))) {
                status = RS_OK;
                break;
            }
        }
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_uart_framing(void) {
    return rs_p4_uart_wait_fault(2U);
}

static uint8_t rs_p4_run_uart(void) {
    static const uint32_t phases[4] = {0U, 3U, 7U, 13U};
    for (uint32_t index = 0U; index < 4U; ++index) {
        uint32_t fnv;
        const rs_status_t status = rs_p4_uart_duplex(phases[index], &fnv);
        if (status != RS_OK) {
            rs_p4_report_printf("PIOLITE_P4_UART case=%u error=%d\n", (unsigned int)index,
                                (int)status);
            return (uint8_t)((rs_p4_uart_stage << 4U) | ((uint8_t)(-status) & 0xFU));
        }
        rs_p4_report_printf(
            "PIOLITE_P4_UART case=%u phase=%u bytes=16 baud=115384 error_ppm=1603 fnv=%08x\n",
            (unsigned int)index, (unsigned int)phases[index], (unsigned int)fnv);
    }
    if (rs_p4_uart_wait_fault(0U) != RS_OK) {
        return 65U;
    }
    rs_p4_report_printf("PIOLITE_P4_UART_RX_STARVATION detected=1\n");
    if (rs_p4_uart_wait_fault(2U) != RS_OK) {
        return 66U;
    }
    rs_p4_report_printf("PIOLITE_P4_UART_BREAK detected=1\n");
    if (rs_p4_uart_framing() != RS_OK) {
        return 67U;
    }
    rs_p4_report_printf("PIOLITE_P4_UART_FRAMING detected=1\n");
    if (rs_p4_uart_wait_fault(1U) != RS_OK) {
        return 68U;
    }
    rs_p4_report_printf("PIOLITE_P4_UART_TX_STARVATION detected=1\n");
    {
        uint32_t fnv;
        const rs_status_t status = rs_p4_uart_duplex(0U, &fnv);
        if (status != RS_OK) {
            return 69U;
        }
        rs_p4_report_printf(
            "PIOLITE_P4_UART_RECOVERY phase=0 bytes=16 baud=115384 error_ppm=1603 fnv=%08x\n",
            (unsigned int)fnv);
    }
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_IR)
static uint32_t rs_p4_ir_tx[2] __attribute__((aligned(64)));

static rs_status_t rs_p4_ir_read_timeout(uint32_t *value, rs_timeout_t timeout) {
    rs_piolite_status_t snapshot;
    while (timeout-- != 0U) {
        const rs_status_t status = rs_piolite_get_status(&rs_p4_session.session, 1U, &snapshot);
        if (status != RS_OK) {
            return status;
        }
        if (snapshot.fault != 0U) {
            return RS_EIO;
        }
        if (((snapshot.fifo_levels >> 8U) & 0xFU) != 0U) {
            return rs_piolite_read(&rs_p4_session.session, 1U, value);
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_p4_ir_read(uint32_t *value) {
    return rs_p4_ir_read_timeout(value, RS_PIOLITE_P4_TIMEOUT);
}

static rs_status_t rs_p4_ir_open(uint16_t mark, uint16_t space, uint16_t initial_y) {
    const rs_piolite_p4_sm_options_t transmitter = {
        .program = &piolite_p1_ir_tx,
        .divider = 211U,
    };
    const rs_piolite_p4_sm_options_t receiver = {
        .program = &piolite_p1_ir_rx,
        .divider = 211U,
        .initial_xy = (uint32_t)initial_y << 16U,
    };
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)rs_p4_ir_tx,
        .destination = (uintptr_t)0U,
        .byte_count = 8U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 2U,
    };
    rs_status_t status;
    rs_p4_ir_tx[0] = mark;
    rs_p4_ir_tx[1] = space;
    status = rs_piolite_p4_open(&rs_p4_session, &transmitter, &receiver, RS_PIOLITE_P4_TIMEOUT);
    if (status == RS_OK) {
        status = rs_piolite_p4_dma_begin(&rs_p4_session, RS_PIOLITE_TX, 0U, 3U, &config,
                                         RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 3U);
    }
    return status;
}

static rs_status_t rs_p4_ir_once(uint16_t mark, uint16_t space, uint32_t *high, uint32_t *low) {
    rs_status_t status = rs_p4_ir_open(mark, space, 0U);
    *high = 0U;
    *low = 0U;
    if (status == RS_OK) {
        status = rs_p4_ir_read(high);
    }
    if (status == RS_OK) {
        status = rs_p4_ir_read(low);
    }
    if (status == RS_OK) {
        *high = UINT32_C(1) + (UINT32_C(2) * (UINT32_C(65535) - *high));
        *low = UINT32_C(5) + (UINT32_C(2) * (UINT32_C(65535) - *low));
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&rs_p4_session.session, 1U, RS_PIOLITE_P4_TIMEOUT);
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_ir_timeout(void) {
    rs_status_t status = rs_p4_ir_open(3U, 4U, UINT16_MAX);
    if (status == RS_OK) {
        uint32_t value;
        const rs_status_t read_status = rs_p4_ir_read_timeout(&value, 1000U);
        status = read_status == RS_ETIMEOUT ? RS_OK : RS_EIO;
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_ir_overflow(void) {
    rs_piolite_status_t snapshot;
    rs_status_t status = rs_p4_ir_open(3U, 4U, UINT16_MAX);
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    if (status == RS_OK) {
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 1U, &snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if (((snapshot.events & (UINT32_C(1) << RS_PIOLITE_ABI_EVENTS_RX_STALL)) != 0U) &&
                (snapshot.rx_stall_count != 0U)) {
                status = RS_OK;
                break;
            }
        }
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_run_ir(void) {
    static const uint16_t tx_patterns[3][2] = {{3U, 4U}, {10U, 2U}, {1U, 1U}};
    static const uint16_t rx_patterns[3][2] = {{5U, 7U}, {13U, 9U}, {1U, 11U}};
    for (uint32_t index = 0U; index < 3U; ++index) {
        uint32_t high;
        uint32_t low;
        const rs_status_t status =
            rs_p4_ir_once(tx_patterns[index][0], tx_patterns[index][1], &high, &low);
        const uint32_t expected_high = rx_patterns[index][0] == 0U ? 1U : rx_patterns[index][0];
        const uint32_t expected_low = rx_patterns[index][1] == 0U ? 1U : rx_patterns[index][1];
        if ((status != RS_OK) || (high + 2U < expected_high) || (expected_high + 2U < high) ||
            (low + 2U < expected_low) || (expected_low + 2U < low)) {
            rs_p4_report_printf("PIOLITE_P4_IR case=%u error=%d high=%u low=%u\n",
                                (unsigned int)index, (int)status, (unsigned int)high,
                                (unsigned int)low);
            return (uint8_t)(70U + index);
        }
        rs_p4_report_printf(
            "PIOLITE_P4_IR case=%u mark=%u space=%u high=%u low=%u rate=37915 error_ppm=2245\n",
            (unsigned int)index, (unsigned int)tx_patterns[index][0],
            (unsigned int)tx_patterns[index][1], (unsigned int)high, (unsigned int)low);
    }
    if (rs_p4_ir_timeout() != RS_OK) {
        return 73U;
    }
    rs_p4_report_printf("PIOLITE_P4_IR_TIMEOUT detected=1\n");
    if (rs_p4_ir_overflow() != RS_OK) {
        return 74U;
    }
    rs_p4_report_printf("PIOLITE_P4_IR_OVERFLOW detected=1\n");
    {
        uint32_t high;
        uint32_t low;
        const rs_status_t status = rs_p4_ir_once(3U, 4U, &high, &low);
        if ((status != RS_OK) || (high + 2U < 5U) || (5U + 2U < high) || (low + 2U < 7U) ||
            (7U + 2U < low)) {
            return 75U;
        }
        rs_p4_report_printf(
            "PIOLITE_P4_IR_RECOVERY mark=3 space=4 high=%u low=%u rate=37915 error_ppm=2245\n",
            (unsigned int)high, (unsigned int)low);
    }
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_LED)
static uint32_t rs_p4_led_tx[16] __attribute__((aligned(64)));

static rs_status_t rs_p4_led_open(void) {
    const rs_piolite_p4_sm_options_t options = {
        .program = &piolite_p1_led_scan,
        .divider = 100U,
        .initial_xy = UINT32_C(16) << 16U,
    };
    return rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
}

static rs_status_t rs_p4_led_frames(uint32_t *fnv) {
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)rs_p4_led_tx,
        .destination = (uintptr_t)0U,
        .byte_count = 64U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 4U,
    };
    rs_status_t status;
    *fnv = UINT32_C(2166136261);
    for (uint32_t index = 0U; index < 16U; ++index) {
        const uint32_t row = index & 7U;
        const uint32_t frame = index >> 3U;
        const uint32_t columns = UINT32_C(0x81) ^ (row * UINT32_C(0x11)) ^ frame;
        rs_p4_led_tx[index] = (columns << 8U) | (UINT32_C(1) << row);
        *fnv = (*fnv ^ (uint8_t)rs_p4_led_tx[index]) * UINT32_C(16777619);
        *fnv = (*fnv ^ (uint8_t)(rs_p4_led_tx[index] >> 8U)) * UINT32_C(16777619);
    }
    status = rs_p4_led_open();
    if (status == RS_OK) {
        status = rs_piolite_p4_dma_begin(&rs_p4_session, RS_PIOLITE_TX, 0U, 3U, &config,
                                         RS_PIOLITE_P4_TIMEOUT);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static rs_status_t rs_p4_led_abort(void) {
    rs_piolite_status_t snapshot;
    rs_status_t status = rs_p4_led_open();
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    if (status == RS_OK) {
        status = RS_ETIMEOUT;
        while (timeout-- != 0U) {
            if (rs_piolite_get_status(&rs_p4_session.session, 0U, &snapshot) != RS_OK) {
                status = RS_EIO;
                break;
            }
            if (((snapshot.pc & 0x1FU) == 1U) && ((snapshot.status & 0x70U) == 0x30U)) {
                status = RS_OK;
                break;
            }
        }
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_run_led(void) {
    uint32_t fnv;
    if (rs_p4_led_frames(&fnv) != RS_OK) {
        return 80U;
    }
    rs_p4_report_printf("PIOLITE_P4_LED frames=2 rows=16 fps=389 blank=1 fnv=%08x\n",
                        (unsigned int)fnv);
    if (rs_p4_led_abort() != RS_OK) {
        return 81U;
    }
    rs_p4_report_printf("PIOLITE_P4_LED_ABORT blank=1\n");
    return 0U;
}
#endif

#if defined(RS_PIOLITE_P4_SCENARIO_GAMEPAD)
static rs_status_t rs_p4_gamepad_read(uint32_t *value) {
    rs_piolite_status_t snapshot;
    uint32_t timeout = RS_PIOLITE_P4_TIMEOUT;
    while (timeout-- != 0U) {
        const rs_status_t status = rs_piolite_get_status(&rs_p4_session.session, 0U, &snapshot);
        if (status != RS_OK) {
            return status;
        }
        if (snapshot.fault != 0U) {
            return RS_EIO;
        }
        if (((snapshot.fifo_levels >> 8U) & 0xFU) != 0U) {
            return rs_piolite_read(&rs_p4_session.session, 0U, value);
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_p4_gamepad_session(const uint8_t *expected, uint32_t count,
                                         bool detect_disconnect, uint32_t *actual_count,
                                         bool *disconnected, uint32_t *fnv) {
    const rs_piolite_p4_sm_options_t options = {
        .program = &piolite_p1_gamepad,
        .divider = 100U,
        .initial_xy = count << 16U,
    };
    rs_status_t status = rs_piolite_p4_open(&rs_p4_session, &options, NULL, RS_PIOLITE_P4_TIMEOUT);
    *actual_count = 0U;
    *disconnected = false;
    *fnv = UINT32_C(2166136261);
    if (status == RS_OK) {
        status = rs_piolite_start(&rs_p4_session.session, 1U);
    }
    while ((status == RS_OK) && (*actual_count < count)) {
        uint32_t value;
        status = rs_p4_gamepad_read(&value);
        if (status != RS_OK) {
            break;
        }
        if (((value & UINT32_C(0xFFFFFF00)) != 0U) ||
            (detect_disconnect && ((uint8_t)value == UINT8_C(0xFF)))) {
            if (detect_disconnect && ((uint8_t)value == UINT8_C(0xFF))) {
                *disconnected = true;
                *actual_count += 1U;
                break;
            }
            status = RS_EIO;
            break;
        }
        if ((uint8_t)value != expected[*actual_count]) {
            status = RS_EIO;
            break;
        }
        *fnv = (*fnv ^ (uint8_t)value) * UINT32_C(16777619);
        *actual_count += 1U;
    }
    if (*disconnected) {
        *fnv = UINT32_C(2166136261);
        for (uint32_t index = 0U; index < *actual_count; ++index) {
            *fnv = (*fnv ^ expected[index]) * UINT32_C(16777619);
        }
    } else if (status == RS_OK) {
        status = rs_piolite_wait_done(&rs_p4_session.session, 0U, RS_PIOLITE_P4_TIMEOUT);
    }
    {
        const rs_status_t cleanup = rs_piolite_p4_close(&rs_p4_session, RS_PIOLITE_P4_TIMEOUT);
        if (status == RS_OK) {
            status = cleanup;
        }
    }
    return status;
}

static uint8_t rs_p4_run_gamepad(void) {
    static const uint8_t fixed[4] = {0xA5U, 0xA5U, 0xA5U, 0xA5U};
    static const uint8_t changing[4] = {0x00U, 0xFFU, 0x5AU, 0xC3U};
    static const uint8_t disconnect[4] = {0x00U, 0xFFU, 0x96U, 0x42U};
    static const uint8_t recovery[4] = {0x69U, 0x69U, 0x69U, 0x69U};
    const uint8_t *patterns[4] = {fixed, changing, disconnect, recovery};
    for (uint32_t index = 0U; index < 4U; ++index) {
        uint32_t count;
        uint32_t fnv;
        bool disconnected;
        const rs_status_t status =
            rs_p4_gamepad_session(patterns[index], 4U, index == 2U, &count, &disconnected, &fnv);
        if ((status != RS_OK) || (count != ((index == 2U) ? 2U : 4U)) ||
            (disconnected != (index == 2U))) {
            return (uint8_t)(90U + index);
        }
        rs_p4_report_printf("PIOLITE_P4_GAMEPAD session=%u scans=%u fnv=%08x disconnected=%u\n",
                            (unsigned int)index, (unsigned int)count, (unsigned int)fnv,
                            disconnected ? 1U : 0U);
    }
    return 0U;
}
#endif

const char *rs_piolite_p4_scenario_name(void) {
#if defined(RS_PIOLITE_P4_SCENARIO_LOGIC_CAPTURE)
    return "LOGIC_CAPTURE";
#elif defined(RS_PIOLITE_P4_SCENARIO_PULSE)
    return "PULSE";
#elif defined(RS_PIOLITE_P4_SCENARIO_UART)
    return "UART";
#elif defined(RS_PIOLITE_P4_SCENARIO_SPI)
    return "SPI";
#elif defined(RS_PIOLITE_P4_SCENARIO_IR)
    return "IR";
#elif defined(RS_PIOLITE_P4_SCENARIO_LED)
    return "LED";
#elif defined(RS_PIOLITE_P4_SCENARIO_GAMEPAD)
    return "GAMEPAD";
#elif defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
    return "CONTENTION";
#else
    return "INVALID";
#endif
}

uint8_t rs_piolite_p4_run_selected(void) {
#if defined(RS_PIOLITE_P4_SCENARIO_LOGIC_CAPTURE)
    return rs_p4_run_logic();
#elif defined(RS_PIOLITE_P4_SCENARIO_CONTENTION)
    return rs_p4_run_contention();
#elif defined(RS_PIOLITE_P4_SCENARIO_PULSE)
    return rs_p4_run_pulse();
#elif defined(RS_PIOLITE_P4_SCENARIO_SPI)
    return rs_p4_run_spi();
#elif defined(RS_PIOLITE_P4_SCENARIO_UART)
    return rs_p4_run_uart();
#elif defined(RS_PIOLITE_P4_SCENARIO_IR)
    return rs_p4_run_ir();
#elif defined(RS_PIOLITE_P4_SCENARIO_LED)
    return rs_p4_run_led();
#elif defined(RS_PIOLITE_P4_SCENARIO_GAMEPAD)
    return rs_p4_run_gamepad();
#else
    return 90U;
#endif
}
