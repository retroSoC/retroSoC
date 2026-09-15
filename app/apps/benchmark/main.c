#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/ga2d.h>
#include <retrosoc/hal/perf.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/service/test.h>

#define RS_BENCHMARK_WORDS            UINT32_C(64)
/* Leave nearly 8 KiB of SRAM headroom above this buffer for the stack. */
#define RS_BENCHMARK_SRAM_OFFSET      UINT32_C(0x6000)
#define RS_BENCHMARK_SRAM_SEED        UINT32_C(0x13579BDF)
#define RS_BENCHMARK_SDRAM_SEED       UINT32_C(0x2468ACE0)
#define RS_BENCHMARK_PSRAM_SEED       UINT32_C(0x5A5A5A5A)
#define RS_BENCHMARK_GA2D_WIDTH       UINT16_C(8)
#define RS_BENCHMARK_GA2D_HEIGHT      UINT16_C(4)
#define RS_BENCHMARK_GA2D_PITCH       UINT32_C(48)
#define RS_BENCHMARK_GA2D_ROW_BYTES   UINT32_C(32)
#define RS_BENCHMARK_GA2D_PIXEL_COUNT UINT32_C(32)
#define RS_BENCHMARK_GA2D_FILL_OFFSET UINT32_C(0x00001000)
#define RS_BENCHMARK_GA2D_SRC_OFFSET  UINT32_C(0x00002000)
#define RS_BENCHMARK_GA2D_DST_OFFSET  UINT32_C(0x00003000)
#define RS_BENCHMARK_GA2D_FILL_COLOR  UINT32_C(0x80123456)

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
                                const rs_ga2d_stats_t *ga2d_stats) {
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
    rs_benchmark_puts(" ga2d_features=0x");
    rs_benchmark_put_hex(s_ga2d_capability.features);
    rs_benchmark_puts(" ga2d_limits=0x");
    rs_benchmark_put_hex(s_ga2d_capability.limits);
    rs_benchmark_puts(" ga2d_formats=0x");
    rs_benchmark_put_hex(s_ga2d_capability.formats);
    rs_benchmark_put_counter(" ga2d_cycles=", ga2d_cycles);
    rs_benchmark_put_counter(" ga2d_read_bytes=", ga2d_read_bytes);
    rs_benchmark_put_counter(" ga2d_write_bytes=", ga2d_write_bytes);
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
                        RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL);

    (void)rs_perf_start();
    cycle_start = rs_benchmark_read_cycle_counter();
    actual_checksum = rs_benchmark_read(memory);
    cycles = rs_benchmark_read_cycle_counter() - cycle_start;
    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure(region, "read");
        return false;
    }
    rs_benchmark_report(region, "read", RS_BENCHMARK_WORDS, actual_checksum, cycles,
                        RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL);
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
                        NULL);
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
        destination[index] = UINT8_C(0xD3);
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
            if (destination[(row * RS_BENCHMARK_GA2D_PITCH) + byte] != UINT8_C(0xD3)) {
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
                        RS_BENCHMARK_GA2D_PIXEL_COUNT, 1U, &snapshot, &ga2d_stats);
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
                        RS_BENCHMARK_GA2D_PIXEL_COUNT, 1U, &snapshot, &ga2d_stats);
    return true;
}

int main(void) {
    volatile uint32_t *const sram =
        (volatile uint32_t *)(uintptr_t)(RS_SOC_SRAM_BASE + RS_BENCHMARK_SRAM_OFFSET);
    volatile uint32_t *const sdram = (volatile uint32_t *)(uintptr_t)RS_SOC_SDRAM_BASE;
    volatile uint32_t *const psram = (volatile uint32_t *)(uintptr_t)RS_SOC_PSRAM_BASE;
    volatile uint32_t *const flash = (volatile uint32_t *)(uintptr_t)(RS_SOC_FLASH_BASE + 0x10000U);
    volatile uint8_t *const ga2d_fill =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_FILL_OFFSET);
    volatile uint8_t *const ga2d_source =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_SRC_OFFSET);
    volatile uint8_t *const ga2d_destination =
        (volatile uint8_t *)(uintptr_t)(RS_SOC_SDRAM_BASE + RS_BENCHMARK_GA2D_DST_OFFSET);
    uint32_t checksum;
    uint64_t cycle_start;
    uint64_t cycles;

    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 5U);
    }
    rs_benchmark_puts("retroSoC: A Customized ASIC for Retro Stuff\n");
    if ((rs_ga2d_get_capability(&s_ga2d_capability) != RS_OK) ||
        (s_ga2d_capability.features != RS_GA2D_CAPABILITY_P5) ||
        (s_ga2d_capability.limits != RS_GA2D_LIMITS_P5) ||
        (s_ga2d_capability.formats != RS_GA2D_FORMAT_CAPABILITY_P5)) {
        rs_test_finish(RS_TEST_FAILED, 6U);
    }

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
                            RS_BENCHMARK_WORDS * sizeof(uint32_t), 0U, 0U, &snapshot, NULL);
    }

    if (!rs_benchmark_dma(psram, sdram + RS_BENCHMARK_WORDS, rs_benchmark_read(psram))) {
        rs_test_finish(RS_TEST_FAILED, 5U);
    }
    if (!rs_benchmark_ga2d_fill(ga2d_fill)) {
        rs_test_finish(RS_TEST_FAILED, 7U);
    }
    if (!rs_benchmark_ga2d_copy(ga2d_source, ga2d_destination)) {
        rs_test_finish(RS_TEST_FAILED, 8U);
    }
    (void)rs_perf_stop();
    rs_benchmark_puts("PERF_BENCHMARK_PASS\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
