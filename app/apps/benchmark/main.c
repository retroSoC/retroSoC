#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/ga2d.h>
#include <retrosoc/hal/perf.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/service/test.h>

#include "../../../crt/src/hal/ga2d_math.h"

#define RS_BENCHMARK_WORDS             UINT32_C(64)
/* Leave nearly 8 KiB of SRAM headroom above this buffer for the stack. */
#define RS_BENCHMARK_SRAM_OFFSET       UINT32_C(0x6000)
#define RS_BENCHMARK_SRAM_SEED         UINT32_C(0x13579BDF)
#define RS_BENCHMARK_SDRAM_SEED        UINT32_C(0x2468ACE0)
#define RS_BENCHMARK_PSRAM_SEED        UINT32_C(0x5A5A5A5A)
/* The ld2_sram layout places .bss/.data at the PSRAM base; keep the payload
   above any linker-allocated variables. */
#define RS_BENCHMARK_PSRAM_OFFSET      UINT32_C(0x2000)
#define RS_BENCHMARK_GA2D_WIDTH        UINT16_C(8)
#define RS_BENCHMARK_GA2D_HEIGHT       UINT16_C(4)
#define RS_BENCHMARK_GA2D_PITCH        UINT32_C(48)
#define RS_BENCHMARK_GA2D_ROW_BYTES    UINT32_C(32)
#define RS_BENCHMARK_GA2D_PIXEL_COUNT  UINT32_C(32)
#define RS_BENCHMARK_GA2D_FILL_COLOR   UINT32_C(0x80123456)
#define RS_BENCHMARK_GA2D_BLEND_COLOR  UINT32_C(0xFF4C9A62)
#define RS_BENCHMARK_GA2D_FG_OFFSET    UINT32_C(0x00100000)
#define RS_BENCHMARK_GA2D_BG_OFFSET    UINT32_C(0x00400000)
#define RS_BENCHMARK_GA2D_DST_OFFSET   UINT32_C(0x00700000)
#define RS_BENCHMARK_GA2D_GUARD_BYTES  UINT32_C(0x100)
#define RS_BENCHMARK_GA2D_STRIDE_BYTES UINT32_C(64)
#define RS_BENCHMARK_GA2D_SAMPLE_ROWS  UINT32_C(4)
#define RS_BENCHMARK_GA2D_FG_SEED      UINT32_C(0x5A)
#define RS_BENCHMARK_GA2D_BG_SEED      UINT32_C(0xA5)
#define RS_BENCHMARK_GA2D_GUARD_VALUE  UINT8_C(0xD3)

/* Split-run knobs for long measurement campaigns: the committed defaults run
 * the full payload set; a nonzero begin/skip is used only to resume a timed-out
 * campaign segment without re-executing completed cases. */
#ifndef RS_BENCHMARK_GA2D_CASE_BEGIN
#define RS_BENCHMARK_GA2D_CASE_BEGIN 0U
#endif
#ifndef RS_BENCHMARK_SKIP_BASE
#define RS_BENCHMARK_SKIP_BASE 0U
#endif

typedef struct {
    const char *region;
    const char *operation;
    rs_ga2d_operation_t code;
    rs_ga2d_format_t foreground_format;
    uint32_t foreground_bpp;
    bool use_background;
    uint32_t traffic_bpp;
    uint32_t read_bpp;
    uint16_t width;
    uint16_t height;
    bool strided;
} rs_benchmark_ga2d_case_t;

/* Contiguous op x size matrix plus representative strided cases; every frozen
   size appears in both pitch modes. */
static const rs_benchmark_ga2d_case_t RS_BENCHMARK_GA2D_CASES[] = {
    {"ga2d_320x240_c", "fill", RS_GA2D_OP_FILL, RS_GA2D_FORMAT_A8, 0U, false, 2U, 0U, 320U, 240U,
     false},
    {"ga2d_320x240_c", "copy", RS_GA2D_OP_COPY, RS_GA2D_FORMAT_RGB565, 2U, false, 4U, 2U, 320U,
     240U, false},
    {"ga2d_320x240_c", "convert", RS_GA2D_OP_CONVERT, RS_GA2D_FORMAT_RGB888, 3U, false, 5U, 3U,
     320U, 240U, false},
    {"ga2d_320x240_c", "blend", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_ARGB8888, 4U, true, 8U, 6U, 320U,
     240U, false},
    {"ga2d_320x240_c", "blend_a8", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_A8, 1U, true, 5U, 3U, 320U,
     240U, false},
    {"ga2d_480x272_c", "fill", RS_GA2D_OP_FILL, RS_GA2D_FORMAT_A8, 0U, false, 2U, 0U, 480U, 272U,
     false},
    {"ga2d_480x272_c", "copy", RS_GA2D_OP_COPY, RS_GA2D_FORMAT_RGB565, 2U, false, 4U, 2U, 480U,
     272U, false},
    {"ga2d_480x272_c", "convert", RS_GA2D_OP_CONVERT, RS_GA2D_FORMAT_RGB888, 3U, false, 5U, 3U,
     480U, 272U, false},
    {"ga2d_480x272_c", "blend", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_ARGB8888, 4U, true, 8U, 6U, 480U,
     272U, false},
    {"ga2d_480x272_c", "blend_a8", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_A8, 1U, true, 5U, 3U, 480U,
     272U, false},
    {"ga2d_800x480_c", "fill", RS_GA2D_OP_FILL, RS_GA2D_FORMAT_A8, 0U, false, 2U, 0U, 800U, 480U,
     false},
    {"ga2d_800x480_c", "copy", RS_GA2D_OP_COPY, RS_GA2D_FORMAT_RGB565, 2U, false, 4U, 2U, 800U,
     480U, false},
    {"ga2d_800x480_c", "convert", RS_GA2D_OP_CONVERT, RS_GA2D_FORMAT_RGB888, 3U, false, 5U, 3U,
     800U, 480U, false},
    {"ga2d_800x480_c", "blend", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_ARGB8888, 4U, true, 8U, 6U, 800U,
     480U, false},
    {"ga2d_800x480_c", "blend_a8", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_A8, 1U, true, 5U, 3U, 800U,
     480U, false},
    {"ga2d_320x240_s", "copy", RS_GA2D_OP_COPY, RS_GA2D_FORMAT_RGB565, 2U, false, 4U, 2U, 320U,
     240U, true},
    {"ga2d_480x272_s", "convert", RS_GA2D_OP_CONVERT, RS_GA2D_FORMAT_RGB888, 3U, false, 5U, 3U,
     480U, 272U, true},
    {"ga2d_800x480_s", "blend", RS_GA2D_OP_BLEND, RS_GA2D_FORMAT_ARGB8888, 4U, true, 8U, 6U, 800U,
     480U, true},
};
#define RS_BENCHMARK_GA2D_CASE_COUNT                                                               \
    (sizeof(RS_BENCHMARK_GA2D_CASES) / sizeof(RS_BENCHMARK_GA2D_CASES[0]))

static rs_ga2d_capability_t s_ga2d_capability;

static void rs_benchmark_puts(const char *text) {
    while (*text != '\0') {
        putch(*text);
        ++text;
    }
}

static void rs_benchmark_put_dec(uint32_t value) {
    char digits[10];
    uint32_t digit_count = 0U;

    do {
        digits[digit_count] = (char)('0' + (value % 10U));
        value /= 10U;
        ++digit_count;
    } while (value != 0U);
    do {
        --digit_count;
        putch(digits[digit_count]);
    } while (digit_count != 0U);
}

static void rs_benchmark_put_dec64(uint64_t value) {
    char digits[20];
    uint32_t digit_count = 0U;

    do {
        digits[digit_count] = (char)('0' + (value % 10U));
        value /= 10U;
        ++digit_count;
    } while (value != 0U);
    do {
        --digit_count;
        putch(digits[digit_count]);
    } while (digit_count != 0U);
}

static void rs_benchmark_put_hex(uint32_t value) {
    static const char digits[] = "0123456789abcdef";
    uint32_t nibble_index;

    for (nibble_index = 8U; nibble_index > 0U; --nibble_index) {
        const uint32_t shift = (nibble_index - 1U) * 4U;

        putch(digits[(value >> shift) & 0xFU]);
    }
}

static void rs_benchmark_put_counter(const char *name, uint64_t value) {
    rs_benchmark_puts(name);
    rs_benchmark_put_dec64(value);
}

static void rs_benchmark_enable_cycle_counter(void) {
    /* Hazard3 leaves reset with mcountinhibit.CY set, which freezes mcycle.
       The benchmark profile builds without the _zicsr extension, so emit the
       csrrc x0, 0x320, rs encoding directly. */
    const uint32_t mask = 1U;

    __asm__ volatile(".insn r 0x73, 0x3, 0x19, x0, %0, x0" : : "r"(mask) : "memory");
}

static uint64_t rs_benchmark_read_cycle_counter(void) {
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        __asm__ volatile("rdcycleh %0" : "=r"(high_before));
        __asm__ volatile("rdcycle %0" : "=r"(low));
        __asm__ volatile("rdcycleh %0" : "=r"(high_after));
    } while (high_before != high_after);

    return ((uint64_t)high_after << 32U) | (uint64_t)low;
}

static uint32_t rs_benchmark_write(volatile uint32_t *memory, uint32_t seed) {
    uint32_t index;
    uint32_t value = seed;
    uint32_t checksum = 0U;

    for (index = 0U; index < RS_BENCHMARK_WORDS; ++index) {
        value = (value << 5) ^ (value >> 3) ^ index;
        memory[index] = value;
        checksum ^= value + index;
    }
    return checksum;
}

static uint32_t rs_benchmark_read(volatile const uint32_t *memory) {
    uint32_t index;
    uint32_t checksum = 0U;

    for (index = 0U; index < RS_BENCHMARK_WORDS; ++index) {
        checksum ^= memory[index] + index;
    }
    return checksum;
}

static void rs_benchmark_report(const char *region, const char *operation, uint32_t words,
                                uint32_t checksum, uint64_t cpu_cycles, uint64_t workload_bytes,
                                uint32_t pixels, uint32_t jobs, const rs_perf_snapshot_t *snapshot,
                                const rs_ga2d_stats_t *ga2d_stats, uint32_t width, uint32_t height,
                                uint32_t pitch) {
    uint64_t ga2d_cycles = 0U;
    uint64_t ga2d_read_bytes = 0U;
    uint64_t ga2d_write_bytes = 0U;

    if (ga2d_stats != NULL) {
        ga2d_cycles = ga2d_stats->cycles;
        ga2d_read_bytes = ga2d_stats->read_bytes;
        ga2d_write_bytes = ga2d_stats->write_bytes;
    }
    rs_benchmark_puts("PERF region=");
    rs_benchmark_puts(region);
    rs_benchmark_puts(" op=");
    rs_benchmark_puts(operation);
    rs_benchmark_puts(" words=");
    rs_benchmark_put_dec(words);
    rs_benchmark_puts(" checksum=");
    rs_benchmark_put_hex(checksum);
    rs_benchmark_put_counter(" cycles=", cpu_cycles);
    rs_benchmark_put_counter(" mgmt_wait=", snapshot->mgmt_wait);
    rs_benchmark_put_counter(" apb4_periph_wait=", snapshot->apb4_periph_wait);
    rs_benchmark_put_counter(" sdram_wait=", snapshot->sdram_wait);
    rs_benchmark_put_counter(" psram_wait=", snapshot->psram_wait);
    rs_benchmark_put_counter(" flash_wait=", snapshot->flash_wait);
    rs_benchmark_put_counter(" dma_wait=", snapshot->dma_wait);
    rs_benchmark_put_counter(" workload_bytes=", workload_bytes);
    rs_benchmark_put_counter(" pixels=", pixels);
    rs_benchmark_put_counter(" jobs=", jobs);
    rs_benchmark_put_counter(" cpu_cycles=", cpu_cycles);
    rs_benchmark_put_counter(" cpu_hz=", RS_CPU_CLOCK_HZ);
    rs_benchmark_put_counter(" pclk_hz=", RS_PCLK_CLOCK_HZ);
    rs_benchmark_puts(" ga2d_features=0x");
    rs_benchmark_put_hex(s_ga2d_capability.features);
    rs_benchmark_puts(" ga2d_limits=0x");
    rs_benchmark_put_hex(s_ga2d_capability.limits);
    rs_benchmark_puts(" ga2d_formats=0x");
    rs_benchmark_put_hex(s_ga2d_capability.formats);
    rs_benchmark_put_counter(" ga2d_cycles=", ga2d_cycles);
    rs_benchmark_put_counter(" ga2d_read_bytes=", ga2d_read_bytes);
    rs_benchmark_put_counter(" ga2d_write_bytes=", ga2d_write_bytes);
    if (ga2d_stats != NULL) {
        rs_benchmark_puts(" width=");
        rs_benchmark_put_dec(width);
        rs_benchmark_puts(" height=");
        rs_benchmark_put_dec(height);
        rs_benchmark_puts(" pitch=");
        rs_benchmark_put_dec(pitch);
    }
    putch('\n');
}

static void rs_benchmark_report_snapshot_failure(const char *region, const char *operation) {
    rs_benchmark_puts("PERF_FAIL region=");
    rs_benchmark_puts(region);
    rs_benchmark_puts(" op=");
    rs_benchmark_puts(operation);
    rs_benchmark_puts(" reason=snapshot\n");
}

static void rs_benchmark_report_data_failure(const char *region, uint32_t expected,
                                             uint32_t actual) {
    rs_benchmark_puts("PERF_FAIL region=");
    rs_benchmark_puts(region);
    rs_benchmark_puts(" op=read reason=data expected=");
    rs_benchmark_put_hex(expected);
    rs_benchmark_puts(" actual=");
    rs_benchmark_put_hex(actual);
    putch('\n');
}

static void rs_benchmark_report_ga2d_failure(const rs_benchmark_ga2d_case_t *benchmark_case,
                                             const char *reason) {
    rs_benchmark_puts("PERF_FAIL region=");
    rs_benchmark_puts(benchmark_case->region);
    rs_benchmark_puts(" op=");
    rs_benchmark_puts(benchmark_case->operation);
    rs_benchmark_puts(" reason=");
    rs_benchmark_puts(reason);
    putch('\n');
}

static bool rs_benchmark_memory(const char *region, volatile uint32_t *memory, uint32_t seed) {
    rs_perf_snapshot_t snapshot;
    uint64_t cycle_start;
    uint64_t cycles;
    uint32_t expected_checksum;
    uint32_t actual_checksum;

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    expected_checksum = rs_benchmark_write(memory, seed);
    cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure(region, "write");
        return false;
    }
    rs_benchmark_report(region, "write", RS_BENCHMARK_WORDS, expected_checksum, cycles,
                        RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL, 0U, 0U, 0U);

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    actual_checksum = rs_benchmark_read(memory);
    cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure(region, "read");
        return false;
    }
    rs_benchmark_report(region, "read", RS_BENCHMARK_WORDS, actual_checksum, cycles,
                        RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL, 0U, 0U, 0U);
    if (actual_checksum != expected_checksum) {
        rs_benchmark_report_data_failure(region, expected_checksum, actual_checksum);
        return false;
    }
    return true;
}

static bool rs_benchmark_dma(volatile uint32_t *source, volatile uint32_t *destination,
                             uint32_t expected_checksum) {
    const rs_dma_config_t dma_config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)source,
        .destination = (uintptr_t)destination,
        .byte_count = RS_BENCHMARK_WORDS * sizeof(uint32_t),
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };
    rs_dma_error_t error;
    rs_perf_snapshot_t snapshot;
    rs_status_t status;
    uint64_t cycle_start;
    uint64_t cycles;
    uint32_t checksum;

    error.code = 0U;
    error.response_code = 0U;
    error.address = 0U;
    error.read = false;

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    status = rs_dma_configure(RS_DMA_CHANNEL_BULK, &dma_config);
    if (status == RS_OK) {
        status = rs_dma_start(RS_DMA_CHANNEL_BULK);
    }
    if (status == RS_OK) {
        status = rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT);
    }
    if (status != RS_OK) {
        (void)rs_dma_get_error(RS_DMA_CHANNEL_BULK, &error);
        rs_benchmark_puts("PERF_FAIL region=dma op=copy\n");
        return false;
    }
    cycles = rs_benchmark_read_cycle_counter() - cycle_start;

    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure("dma", "copy");
        return false;
    }
    checksum = rs_benchmark_read(destination);
    rs_benchmark_report("dma", "copy", RS_BENCHMARK_WORDS, checksum, cycles,
                        UINT64_C(2) * RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 1U, &snapshot,
                        NULL, 0U, 0U, 0U);
    if (checksum != expected_checksum) {
        rs_benchmark_report_data_failure("dma", expected_checksum, checksum);
        return false;
    }
    return true;
}

static uint32_t rs_benchmark_bytes_checksum(volatile const uint8_t *memory, uint32_t bytes) {
    uint32_t checksum = 0U;

    for (uint32_t index = 0U; index < bytes; ++index) {
        checksum = (checksum << 5U) ^ (checksum >> 2U) ^ (uint32_t)memory[index];
    }
    return checksum;
}

static uint8_t rs_benchmark_ga2d_pattern(uint32_t offset, uint32_t seed) {
    return (uint8_t)((offset ^ (offset >> 4U) ^ seed) & UINT32_C(0xFF));
}

static void rs_benchmark_ga2d_write_pattern_row(volatile uint8_t *row, uint32_t row_bytes,
                                                uint32_t row_offset, uint32_t seed) {
    volatile uint32_t *const words = (volatile uint32_t *)(uintptr_t)row;

    for (uint32_t word_index = 0U; word_index < (row_bytes / sizeof(uint32_t)); ++word_index) {
        const uint32_t offset = row_offset + (word_index * sizeof(uint32_t));
        uint32_t value = 0U;

        for (uint32_t byte_index = 0U; byte_index < sizeof(uint32_t); ++byte_index) {
            value |= (uint32_t)rs_benchmark_ga2d_pattern(offset + byte_index, seed)
                     << (byte_index * 8U);
        }
        words[word_index] = value;
    }
}

static bool rs_benchmark_ga2d_expected_pixel(const rs_benchmark_ga2d_case_t *benchmark_case,
                                             uint32_t foreground_offset, uint32_t background_offset,
                                             uint8_t *expected) {
    uint8_t foreground[4];
    uint8_t background[2];
    rs_ga2d_pixel_t pixel;
    rs_status_t status = RS_OK;

    for (uint32_t index = 0U; index < benchmark_case->foreground_bpp; ++index) {
        foreground[index] =
            rs_benchmark_ga2d_pattern(foreground_offset + index, RS_BENCHMARK_GA2D_FG_SEED);
    }
    switch (benchmark_case->code) {
    case RS_GA2D_OP_FILL:
        pixel.red = (uint8_t)(RS_BENCHMARK_GA2D_FILL_COLOR >> 16U);
        pixel.green = (uint8_t)(RS_BENCHMARK_GA2D_FILL_COLOR >> 8U);
        pixel.blue = (uint8_t)RS_BENCHMARK_GA2D_FILL_COLOR;
        pixel.alpha = UINT8_C(0xFF);
        status = rs_ga2d_pack_pixel(expected, RS_GA2D_FORMAT_RGB565, &pixel);
        break;
    case RS_GA2D_OP_COPY:
        expected[0] = foreground[0];
        expected[1] = foreground[1];
        break;
    case RS_GA2D_OP_CONVERT:
        status = rs_ga2d_convert_pixel(foreground, RS_GA2D_FORMAT_RGB888, expected,
                                       RS_GA2D_FORMAT_RGB565);
        break;
    case RS_GA2D_OP_BLEND:
        background[0] = rs_benchmark_ga2d_pattern(background_offset, RS_BENCHMARK_GA2D_BG_SEED);
        background[1] =
            rs_benchmark_ga2d_pattern(background_offset + 1U, RS_BENCHMARK_GA2D_BG_SEED);
        if (benchmark_case->foreground_format == RS_GA2D_FORMAT_A8) {
            status = rs_ga2d_blend_pixel(foreground, RS_GA2D_FORMAT_A8, background,
                                         RS_GA2D_FORMAT_RGB565, expected, RS_GA2D_FORMAT_RGB565,
                                         RS_BENCHMARK_GA2D_BLEND_COLOR, UINT8_C(0xFF));
        } else {
            status = rs_ga2d_blend_pixel(foreground, RS_GA2D_FORMAT_ARGB8888, background,
                                         RS_GA2D_FORMAT_RGB565, expected, RS_GA2D_FORMAT_RGB565,
                                         UINT32_C(0), UINT8_C(0xFF));
        }
        break;
    default:
        status = RS_EINVAL;
        break;
    }
    return status == RS_OK;
}

static bool rs_benchmark_ga2d_fill(volatile uint8_t *destination) {
    const rs_ga2d_job_t job = {
        .operation = RS_GA2D_OP_FILL,
        .foreground = {0U, 0U, RS_GA2D_FORMAT_A8},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)destination, RS_BENCHMARK_GA2D_PITCH, RS_GA2D_FORMAT_XRGB8888},
        .width = RS_BENCHMARK_GA2D_WIDTH,
        .height = RS_BENCHMARK_GA2D_HEIGHT,
        .global_alpha = UINT8_C(0),
        .color = RS_BENCHMARK_GA2D_FILL_COLOR,
    };
    rs_ga2d_stats_t ga2d_stats;
    rs_perf_snapshot_t snapshot;
    uint64_t cycle_start;
    uint64_t cpu_cycles;
    uint32_t checksum;

    for (uint32_t index = 0U; index < (RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_PITCH);
         ++index) {
        destination[index] = RS_BENCHMARK_GA2D_GUARD_VALUE;
    }
    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    if ((rs_ga2d_configure(&job) != RS_OK) || (rs_ga2d_start() != RS_OK) ||
        (rs_ga2d_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        rs_benchmark_puts("PERF_FAIL region=ga2d op=fill reason=job\n");
        return false;
    }
    cpu_cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if ((rs_ga2d_get_stats(&ga2d_stats) != RS_OK) || (rs_perf_snapshot(&snapshot) != RS_OK)) {
        rs_benchmark_report_snapshot_failure("ga2d", "fill");
        return false;
    }
    for (uint32_t row = 0U; row < RS_BENCHMARK_GA2D_HEIGHT; ++row) {
        for (uint32_t pixel = 0U; pixel < RS_BENCHMARK_GA2D_WIDTH; ++pixel) {
            const uint32_t pixel_offset = (row * RS_BENCHMARK_GA2D_PITCH) + (pixel * UINT32_C(4));

            if ((destination[pixel_offset] != UINT8_C(0x56)) ||
                (destination[pixel_offset + 1U] != UINT8_C(0x34)) ||
                (destination[pixel_offset + 2U] != UINT8_C(0x12)) ||
                (destination[pixel_offset + 3U] != UINT8_C(0xFF))) {
                rs_benchmark_puts("PERF_FAIL region=ga2d op=fill reason=data\n");
                return false;
            }
        }
        for (uint32_t byte = RS_BENCHMARK_GA2D_ROW_BYTES; byte < RS_BENCHMARK_GA2D_PITCH; ++byte) {
            if (destination[(row * RS_BENCHMARK_GA2D_PITCH) + byte] !=
                RS_BENCHMARK_GA2D_GUARD_VALUE) {
                rs_benchmark_puts("PERF_FAIL region=ga2d op=fill reason=guard\n");
                return false;
            }
        }
    }
    if ((ga2d_stats.lines_done != RS_BENCHMARK_GA2D_HEIGHT) || (ga2d_stats.read_bytes != 0U) ||
        (ga2d_stats.write_bytes !=
         (uint64_t)RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_ROW_BYTES)) {
        rs_benchmark_puts("PERF_FAIL region=ga2d op=fill reason=stats\n");
        return false;
    }
    checksum = rs_benchmark_bytes_checksum(destination,
                                           RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_PITCH);
    rs_benchmark_report("ga2d", "fill", 0U, checksum, cpu_cycles,
                        (uint64_t)RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_ROW_BYTES,
                        RS_BENCHMARK_GA2D_PIXEL_COUNT, 1U, &snapshot, &ga2d_stats,
                        RS_BENCHMARK_GA2D_WIDTH, RS_BENCHMARK_GA2D_HEIGHT, RS_BENCHMARK_GA2D_PITCH);
    return true;
}

static bool rs_benchmark_ga2d_copy(volatile uint8_t *source, volatile uint8_t *destination) {
    const rs_ga2d_job_t job = {
        .operation = RS_GA2D_OP_COPY,
        .foreground = {(uintptr_t)source, RS_BENCHMARK_GA2D_PITCH, RS_GA2D_FORMAT_XRGB8888},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)destination, RS_BENCHMARK_GA2D_PITCH, RS_GA2D_FORMAT_XRGB8888},
        .width = RS_BENCHMARK_GA2D_WIDTH,
        .height = RS_BENCHMARK_GA2D_HEIGHT,
        .global_alpha = UINT8_C(0),
        .color = UINT32_C(0),
    };
    rs_ga2d_stats_t ga2d_stats;
    rs_perf_snapshot_t snapshot;
    uint64_t cycle_start;
    uint64_t cpu_cycles;
    uint32_t checksum;

    for (uint32_t index = 0U; index < (RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_PITCH);
         ++index) {
        source[index] = (uint8_t)(index ^ UINT32_C(0x5A));
        destination[index] = UINT8_C(0xC7);
    }
    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    if ((rs_ga2d_configure(&job) != RS_OK) || (rs_ga2d_start() != RS_OK) ||
        (rs_ga2d_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        rs_benchmark_puts("PERF_FAIL region=ga2d op=copy reason=job\n");
        return false;
    }
    cpu_cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if ((rs_ga2d_get_stats(&ga2d_stats) != RS_OK) || (rs_perf_snapshot(&snapshot) != RS_OK)) {
        rs_benchmark_report_snapshot_failure("ga2d", "copy");
        return false;
    }
    for (uint32_t row = 0U; row < RS_BENCHMARK_GA2D_HEIGHT; ++row) {
        const uint32_t row_offset = row * RS_BENCHMARK_GA2D_PITCH;

        for (uint32_t byte = 0U; byte < RS_BENCHMARK_GA2D_ROW_BYTES; ++byte) {
            if (destination[row_offset + byte] != source[row_offset + byte]) {
                rs_benchmark_puts("PERF_FAIL region=ga2d op=copy reason=data\n");
                return false;
            }
        }
        for (uint32_t byte = RS_BENCHMARK_GA2D_ROW_BYTES; byte < RS_BENCHMARK_GA2D_PITCH; ++byte) {
            if (destination[row_offset + byte] != UINT8_C(0xC7)) {
                rs_benchmark_puts("PERF_FAIL region=ga2d op=copy reason=guard\n");
                return false;
            }
        }
    }
    if ((ga2d_stats.lines_done != RS_BENCHMARK_GA2D_HEIGHT) ||
        (ga2d_stats.read_bytes !=
         (uint64_t)RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_ROW_BYTES) ||
        (ga2d_stats.write_bytes !=
         (uint64_t)RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_ROW_BYTES)) {
        rs_benchmark_puts("PERF_FAIL region=ga2d op=copy reason=stats\n");
        return false;
    }
    checksum = rs_benchmark_bytes_checksum(destination,
                                           RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_PITCH);
    rs_benchmark_report("ga2d", "copy", 0U, checksum, cpu_cycles,
                        UINT64_C(2) * RS_BENCHMARK_GA2D_HEIGHT * RS_BENCHMARK_GA2D_ROW_BYTES,
                        RS_BENCHMARK_GA2D_PIXEL_COUNT, 1U, &snapshot, &ga2d_stats,
                        RS_BENCHMARK_GA2D_WIDTH, RS_BENCHMARK_GA2D_HEIGHT, RS_BENCHMARK_GA2D_PITCH);
    return true;
}

static bool rs_benchmark_ga2d_case(const rs_benchmark_ga2d_case_t *benchmark_case,
                                   volatile uint8_t *foreground, volatile uint8_t *background,
                                   volatile uint8_t *destination) {
    const uint32_t width = benchmark_case->width;
    const uint32_t height = benchmark_case->height;
    const uint32_t stride = benchmark_case->strided ? RS_BENCHMARK_GA2D_STRIDE_BYTES : 0U;
    const uint32_t destination_row_bytes = width * UINT32_C(2);
    const uint32_t destination_pitch = destination_row_bytes + stride;
    const uint32_t foreground_row_bytes = width * benchmark_case->foreground_bpp;
    const uint32_t foreground_pitch =
        (benchmark_case->code == RS_GA2D_OP_FILL) ? 0U : (foreground_row_bytes + stride);
    const uint32_t background_row_bytes = width * UINT32_C(2);
    const uint32_t background_pitch =
        benchmark_case->use_background ? (background_row_bytes + stride) : 0U;
    const uint32_t guard_end = ((height - 1U) * destination_pitch) + destination_row_bytes;
    volatile uint8_t *const guard_pre = destination - RS_BENCHMARK_GA2D_GUARD_BYTES;
    const uint64_t pixels = (uint64_t)width * (uint64_t)height;
    const uint32_t color = (benchmark_case->code == RS_GA2D_OP_FILL)
                               ? RS_BENCHMARK_GA2D_FILL_COLOR
                               : ((benchmark_case->foreground_format == RS_GA2D_FORMAT_A8)
                                      ? RS_BENCHMARK_GA2D_BLEND_COLOR
                                      : UINT32_C(0));
    const rs_ga2d_job_t job = {
        .operation = benchmark_case->code,
        .foreground = {(benchmark_case->code == RS_GA2D_OP_FILL) ? UINT32_C(0)
                                                                 : (uintptr_t)foreground,
                       foreground_pitch, benchmark_case->foreground_format},
        .background = {benchmark_case->use_background ? (uintptr_t)background : UINT32_C(0),
                       background_pitch,
                       benchmark_case->use_background ? RS_GA2D_FORMAT_RGB565 : RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)destination, destination_pitch, RS_GA2D_FORMAT_RGB565},
        .width = benchmark_case->width,
        .height = benchmark_case->height,
        .global_alpha = UINT8_C(0xFF),
        .color = color,
    };
    uint32_t sample_rows[RS_BENCHMARK_GA2D_SAMPLE_ROWS];
    rs_ga2d_stats_t ga2d_stats;
    rs_perf_snapshot_t snapshot;
    uint64_t cycle_start;
    uint64_t cpu_cycles;
    uint32_t checksum = 0U;

    sample_rows[0] = 0U;
    sample_rows[1] = height / 3U;
    sample_rows[2] = (height * 2U) / 3U;
    sample_rows[3] = height - 1U;

    for (uint32_t index = 0U; index < RS_BENCHMARK_GA2D_GUARD_BYTES; ++index) {
        guard_pre[index] = RS_BENCHMARK_GA2D_GUARD_VALUE;
        destination[guard_end + index] = RS_BENCHMARK_GA2D_GUARD_VALUE;
    }
    for (uint32_t sample = 0U; sample < RS_BENCHMARK_GA2D_SAMPLE_ROWS; ++sample) {
        const uint32_t row = sample_rows[sample];

        if (benchmark_case->strided) {
            for (uint32_t byte = destination_row_bytes; byte < destination_pitch; ++byte) {
                destination[(row * destination_pitch) + byte] = RS_BENCHMARK_GA2D_GUARD_VALUE;
            }
        }
        if (benchmark_case->code != RS_GA2D_OP_FILL) {
            rs_benchmark_ga2d_write_pattern_row(foreground + (row * foreground_pitch),
                                                foreground_row_bytes, row * foreground_pitch,
                                                RS_BENCHMARK_GA2D_FG_SEED);
        }
        if (benchmark_case->use_background) {
            rs_benchmark_ga2d_write_pattern_row(background + (row * background_pitch),
                                                background_row_bytes, row * background_pitch,
                                                RS_BENCHMARK_GA2D_BG_SEED);
        }
    }

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    if ((rs_ga2d_configure(&job) != RS_OK) || (rs_ga2d_start() != RS_OK) ||
        (rs_ga2d_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        rs_benchmark_report_ga2d_failure(benchmark_case, "job");
        return false;
    }
    cpu_cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if ((rs_ga2d_get_stats(&ga2d_stats) != RS_OK) || (rs_perf_snapshot(&snapshot) != RS_OK)) {
        rs_benchmark_report_snapshot_failure(benchmark_case->region, benchmark_case->operation);
        return false;
    }
    if ((ga2d_stats.lines_done != benchmark_case->height) ||
        (ga2d_stats.read_bytes != pixels * benchmark_case->read_bpp) ||
        (ga2d_stats.write_bytes != pixels * UINT64_C(2))) {
        rs_benchmark_report_ga2d_failure(benchmark_case, "stats");
        return false;
    }

    for (uint32_t sample = 0U; sample < RS_BENCHMARK_GA2D_SAMPLE_ROWS; ++sample) {
        const uint32_t row = sample_rows[sample];

        for (uint32_t column = 0U; column < width; ++column) {
            const uint32_t foreground_offset =
                (row * foreground_pitch) + (column * benchmark_case->foreground_bpp);
            const uint32_t background_offset = (row * background_pitch) + (column * UINT32_C(2));
            const uint32_t destination_offset = (row * destination_pitch) + (column * UINT32_C(2));
            uint8_t expected[2];
            uint8_t actual[2];

            if (!rs_benchmark_ga2d_expected_pixel(benchmark_case, foreground_offset,
                                                  background_offset, expected)) {
                rs_benchmark_report_ga2d_failure(benchmark_case, "reference");
                return false;
            }
            actual[0] = destination[destination_offset];
            actual[1] = destination[destination_offset + 1U];
            if ((actual[0] != expected[0]) || (actual[1] != expected[1])) {
                rs_benchmark_puts("PERF_FAIL region=");
                rs_benchmark_puts(benchmark_case->region);
                rs_benchmark_puts(" op=");
                rs_benchmark_puts(benchmark_case->operation);
                rs_benchmark_puts(" reason=data expected=");
                rs_benchmark_put_hex((uint32_t)expected[0] | ((uint32_t)expected[1] << 8U));
                rs_benchmark_puts(" actual=");
                rs_benchmark_put_hex((uint32_t)actual[0] | ((uint32_t)actual[1] << 8U));
                putch('\n');
                return false;
            }
            checksum = (checksum << 5U) ^ (checksum >> 2U) ^ (uint32_t)actual[0];
            checksum = (checksum << 5U) ^ (checksum >> 2U) ^ (uint32_t)actual[1];
        }
        if (benchmark_case->strided) {
            for (uint32_t byte = destination_row_bytes; byte < destination_pitch; ++byte) {
                if (destination[(row * destination_pitch) + byte] !=
                    RS_BENCHMARK_GA2D_GUARD_VALUE) {
                    rs_benchmark_report_ga2d_failure(benchmark_case, "guard");
                    return false;
                }
            }
        }
    }
    for (uint32_t index = 0U; index < RS_BENCHMARK_GA2D_GUARD_BYTES; ++index) {
        if ((guard_pre[index] != RS_BENCHMARK_GA2D_GUARD_VALUE) ||
            (destination[guard_end + index] != RS_BENCHMARK_GA2D_GUARD_VALUE)) {
            rs_benchmark_report_ga2d_failure(benchmark_case, "guard");
            return false;
        }
    }

    rs_benchmark_report(benchmark_case->region, benchmark_case->operation, 0U, checksum, cpu_cycles,
                        pixels * benchmark_case->traffic_bpp, (uint32_t)pixels, 1U, &snapshot,
                        &ga2d_stats, width, height, destination_pitch);
    return true;
}

int main(void) {
#if (RS_BENCHMARK_SKIP_BASE == 0U)
    volatile uint32_t *const sram =
        (volatile uint32_t *)(uintptr_t)(RS_SOC_SRAM_BASE + RS_BENCHMARK_SRAM_OFFSET);
    volatile uint32_t *const sdram = (volatile uint32_t *)(uintptr_t)RS_SOC_SDRAM_BASE;
    volatile uint32_t *const psram =
        (volatile uint32_t *)(uintptr_t)(RS_SOC_PSRAM_BASE + RS_BENCHMARK_PSRAM_OFFSET);
    volatile uint32_t *const flash = (volatile uint32_t *)(uintptr_t)(RS_SOC_FLASH_BASE + 0x10000U);
#endif
    volatile uint8_t *const ga2d_foreground =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_FG_OFFSET);
    volatile uint8_t *const ga2d_background =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_BG_OFFSET);
    volatile uint8_t *const ga2d_destination =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_DST_OFFSET);
#if (RS_BENCHMARK_SKIP_BASE == 0U)
    uint32_t checksum;
    uint64_t cycle_start;
    uint64_t cycles;
#endif

    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 5U);
    }
    rs_benchmark_puts("retroSoC: A Customized ASIC for Retro Stuff\n");
    rs_benchmark_enable_cycle_counter();
    if ((rs_ga2d_get_capability(&s_ga2d_capability) != RS_OK) ||
        (s_ga2d_capability.features != RS_GA2D_CAPABILITY_P5) ||
        (s_ga2d_capability.limits != RS_GA2D_LIMITS_P5) ||
        (s_ga2d_capability.formats != RS_GA2D_FORMAT_CAPABILITY_P5)) {
        rs_test_finish(RS_TEST_FAILED, 6U);
    }

#if (RS_BENCHMARK_SKIP_BASE == 0U)
    if (!rs_benchmark_memory("sram", sram, RS_BENCHMARK_SRAM_SEED)) {
        rs_test_finish(RS_TEST_FAILED, 1U);
    }
    if (!rs_benchmark_memory("sdram", sdram, RS_BENCHMARK_SDRAM_SEED)) {
        rs_test_finish(RS_TEST_FAILED, 2U);
    }
    if (!rs_benchmark_memory("psram", psram, RS_BENCHMARK_PSRAM_SEED)) {
        rs_test_finish(RS_TEST_FAILED, 3U);
    }

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    checksum = rs_benchmark_read(flash);
    cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    {
        rs_perf_snapshot_t snapshot;

        if (rs_perf_snapshot(&snapshot) != RS_OK) {
            rs_benchmark_report_snapshot_failure("flash", "read");
            rs_test_finish(RS_TEST_FAILED, 4U);
        }
        rs_benchmark_report("flash", "read", RS_BENCHMARK_WORDS, checksum, cycles,
                            RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL, 0U, 0U,
                            0U);
    }

    if (!rs_benchmark_dma(psram, sdram + RS_BENCHMARK_WORDS, rs_benchmark_read(psram))) {
        rs_test_finish(RS_TEST_FAILED, 5U);
    }
    if (!rs_benchmark_ga2d_fill(ga2d_destination)) {
        rs_test_finish(RS_TEST_FAILED, 7U);
    }
    if (!rs_benchmark_ga2d_copy(ga2d_foreground, ga2d_destination)) {
        rs_test_finish(RS_TEST_FAILED, 8U);
    }
#endif
    for (uint32_t index = RS_BENCHMARK_GA2D_CASE_BEGIN; index < RS_BENCHMARK_GA2D_CASE_COUNT;
         ++index) {
        if (!rs_benchmark_ga2d_case(&RS_BENCHMARK_GA2D_CASES[index], ga2d_foreground,
                                    ga2d_background, ga2d_destination)) {
            rs_test_finish(RS_TEST_FAILED, 9U);
        }
    }
    (void)rs_perf_stop();
    rs_benchmark_puts("PERF_BENCHMARK_PASS\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
