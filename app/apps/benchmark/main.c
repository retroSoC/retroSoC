#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/perf.h>
#include <retrosoc/hal/uart.h>

#define RS_BENCHMARK_WORDS       UINT32_C(64)
#define RS_BENCHMARK_SRAM_OFFSET UINT32_C(0x10000)
#define RS_BENCHMARK_SRAM_SEED   UINT32_C(0x13579BDF)
#define RS_BENCHMARK_SDRAM_SEED  UINT32_C(0x2468ACE0)
#define RS_BENCHMARK_PSRAM_SEED  UINT32_C(0x5A5A5A5A)

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
    rs_benchmark_put_dec((uint32_t)value);
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

static void rs_benchmark_report(const char *region, const char *operation, uint32_t checksum,
                                const rs_perf_snapshot_t *snapshot) {
    rs_benchmark_puts("PERF region=");
    rs_benchmark_puts(region);
    rs_benchmark_puts(" op=");
    rs_benchmark_puts(operation);
    rs_benchmark_puts(" words=");
    rs_benchmark_put_dec(RS_BENCHMARK_WORDS);
    rs_benchmark_puts(" checksum=");
    rs_benchmark_put_hex(checksum);
    rs_benchmark_put_counter(" mgmt_wait=", snapshot->mgmt_wait);
    rs_benchmark_put_counter(" rib_wait=", snapshot->rib_wait);
    rs_benchmark_put_counter(" sdram_wait=", snapshot->sdram_wait);
    rs_benchmark_put_counter(" psram_wait=", snapshot->psram_wait);
    rs_benchmark_put_counter(" flash_wait=", snapshot->flash_wait);
    rs_benchmark_put_counter(" dma_wait=", snapshot->dma_wait);
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
    uint32_t expected_checksum;
    uint32_t actual_checksum;

    (void)rs_perf_start();
    expected_checksum = rs_benchmark_write(memory, seed);
    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure(region, "write");
        return false;
    }
    rs_benchmark_report(region, "write", expected_checksum, &snapshot);

    (void)rs_perf_start();
    actual_checksum = rs_benchmark_read(memory);
    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure(region, "read");
        return false;
    }
    rs_benchmark_report(region, "read", actual_checksum, &snapshot);
    if (actual_checksum != expected_checksum) {
        rs_benchmark_report_data_failure(region, expected_checksum, actual_checksum);
        return false;
    }
    return true;
}

static bool rs_benchmark_dma(volatile uint32_t *source, volatile uint32_t *destination,
                             uint32_t expected_checksum) {
    rs_dma_error_t error;
    rs_perf_snapshot_t snapshot;
    rs_status_t status;
    uint32_t checksum;

    error.response_code = 0U;
    error.address = 0U;

    (void)rs_perf_start();
    status =
        rs_dma_config(0U, (uintptr_t)source, 1U, (uintptr_t)destination, 1U, RS_BENCHMARK_WORDS);
    if (status == RS_OK) {
        status = rs_dma_start();
    }
    if (status == RS_OK) {
        status = rs_dma_wait(RS_TIMEOUT_DEFAULT);
    }
    if (status != RS_OK) {
        (void)rs_dma_get_error(&error);
        rs_benchmark_puts("PERF_FAIL region=dma op=copy\n");
        return false;
    }

    if (rs_perf_snapshot(&snapshot) != RS_OK) {
        rs_benchmark_report_snapshot_failure("dma", "copy");
        return false;
    }
    checksum = rs_benchmark_read(destination);
    rs_benchmark_report("dma", "copy", checksum, &snapshot);
    if (checksum != expected_checksum) {
        rs_benchmark_report_data_failure("dma", expected_checksum, checksum);
        return false;
    }
    return true;
}

int main(void) {
    volatile uint32_t *const sram =
        (volatile uint32_t *)(uintptr_t)(RS_SOC_SRAM_BASE + RS_BENCHMARK_SRAM_OFFSET);
    volatile uint32_t *const sdram = (volatile uint32_t *)(uintptr_t)RS_SOC_SDRAM_BASE;
    volatile uint32_t *const psram = (volatile uint32_t *)(uintptr_t)RS_SOC_PSRAM_BASE;
    volatile uint32_t *const flash = (volatile uint32_t *)(uintptr_t)(RS_SOC_FLASH_BASE + 0x10000U);
    uint32_t checksum;

    uart0_init(CPU_FREQ, UART_BPS);
    rs_benchmark_puts("retroSoC: A Customized ASIC for Retro Stuff\n");

    if (!rs_benchmark_memory("sram", sram, RS_BENCHMARK_SRAM_SEED)) {
        return 1;
    }
    if (!rs_benchmark_memory("sdram", sdram, RS_BENCHMARK_SDRAM_SEED)) {
        return 1;
    }
    if (!rs_benchmark_memory("psram", psram, RS_BENCHMARK_PSRAM_SEED)) {
        return 1;
    }

    (void)rs_perf_start();
    checksum = rs_benchmark_read(flash);
    {
        rs_perf_snapshot_t snapshot;

        if (rs_perf_snapshot(&snapshot) != RS_OK) {
            rs_benchmark_report_snapshot_failure("flash", "read");
            return 1;
        }
        rs_benchmark_report("flash", "read", checksum, &snapshot);
    }

    if (!rs_benchmark_dma(psram, sdram + RS_BENCHMARK_WORDS, rs_benchmark_read(psram))) {
        return 1;
    }
    (void)rs_perf_stop();
    rs_benchmark_puts("PERF_BENCHMARK_PASS\n");
    return 0;
}
