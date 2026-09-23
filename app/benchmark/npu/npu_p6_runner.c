#include "npu_p6_runner.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/status.h>
#include <retrosoc/hal/ga2d.h>
#include <retrosoc/hal/npu.h>
#include <retrosoc/hal/npu_regs.h>

#include "npu_p6_reference.h"

#if defined(RS_NPU_P6_WORKLOAD_KWS)
#include "kws_npu.h"
#define RS_NPU_P6_WORKLOAD_ID      UINT32_C(1)
#define RS_NPU_P6_WORKLOAD_NAME    "kws"
#define RS_NPU_P6_INPUT_BYTES      RS_KWS_NPU_INPUT_BYTES
#define RS_NPU_P6_OUTPUT_BYTES     RS_KWS_NPU_OUTPUT_BYTES
#define RS_NPU_P6_DESCRIPTOR_COUNT RS_KWS_NPU_DESCRIPTOR_COUNT
#define RS_NPU_P6_ARENA_BYTES      RS_KWS_NPU_ARENA_BYTES
#define rs_npu_p6_workspace_t      rs_kws_npu_workspace_t
#define rs_npu_p6_regions_t        rs_kws_npu_regions_t
#define rs_npu_p6_profile_t        rs_kws_npu_profile_t
#define rs_npu_p6_default_regions  rs_kws_npu_default_regions
#define rs_npu_p6_prepare          rs_kws_npu_prepare
#define rs_npu_p6_execute          rs_kws_npu_execute
#define rs_npu_p6_softmax          rs_kws_npu_test_softmax
#define rs_npu_p6_weights          rs_kws_npu_weights
#define rs_npu_p6_params           rs_kws_npu_params
static const uint8_t s_manifest_digest[32] = {
    0x4bU, 0x5bU, 0x32U, 0xe7U, 0x00U, 0xeeU, 0xf0U, 0xf6U, 0xccU, 0x54U, 0x6cU,
    0xd8U, 0x8fU, 0xc6U, 0xc7U, 0x4fU, 0x61U, 0xc6U, 0x25U, 0xfeU, 0x79U, 0x16U,
    0xd1U, 0x68U, 0xecU, 0x34U, 0x8eU, 0x52U, 0x72U, 0x32U, 0x5bU, 0x81U,
};
#elif defined(RS_NPU_P6_WORKLOAD_VWW)
#include "vww_npu.h"
#define RS_NPU_P6_WORKLOAD_ID      UINT32_C(2)
#define RS_NPU_P6_WORKLOAD_NAME    "vww"
#define RS_NPU_P6_INPUT_BYTES      RS_VWW_NPU_INPUT_BYTES
#define RS_NPU_P6_OUTPUT_BYTES     RS_VWW_NPU_OUTPUT_BYTES
#define RS_NPU_P6_DESCRIPTOR_COUNT RS_VWW_NPU_DESCRIPTOR_COUNT
#define RS_NPU_P6_ARENA_BYTES      RS_VWW_NPU_ARENA_BYTES
#define rs_npu_p6_workspace_t      rs_vww_npu_workspace_t
#define rs_npu_p6_regions_t        rs_vww_npu_regions_t
#define rs_npu_p6_profile_t        rs_vww_npu_profile_t
#define rs_npu_p6_default_regions  rs_vww_npu_default_regions
#define rs_npu_p6_prepare          rs_vww_npu_prepare
#define rs_npu_p6_execute          rs_vww_npu_execute
#define rs_npu_p6_softmax          rs_vww_npu_test_softmax
#define rs_npu_p6_weights          rs_vww_npu_weights
#define rs_npu_p6_params           rs_vww_npu_params
static const uint8_t s_manifest_digest[32] = {
    0xfcU, 0xd6U, 0xa7U, 0x25U, 0xa7U, 0x54U, 0x9dU, 0xcaU, 0xd4U, 0xbaU, 0x8cU,
    0x49U, 0x68U, 0xf5U, 0x9fU, 0x36U, 0x50U, 0x88U, 0xc8U, 0x22U, 0xe2U, 0xf1U,
    0x7aU, 0xd5U, 0xeeU, 0x4bU, 0x8eU, 0xafU, 0xb2U, 0x1bU, 0xc5U, 0xb3U,
};
#else
#error "NPU-P6 runner requires exactly one workload selection"
#endif

#define RS_NPU_P6_SHARD_BASE        UINT32_C(0x38400000)
#define RS_NPU_P6_SHARD_MAGIC       UINT32_C(0x5336504E)
#define RS_NPU_P6_SHARD_SCHEMA      UINT32_C(2)
#define RS_NPU_P6_HEADER_BYTES      UINT32_C(128)
#define RS_NPU_P6_CASE_HEADER_BYTES UINT32_C(8)
#define RS_NPU_P6_RECORD_BYTES                                                                     \
    ((RS_NPU_P6_CASE_HEADER_BYTES + RS_NPU_P6_INPUT_BYTES +                                        \
      (UINT32_C(2) * RS_NPU_P6_OUTPUT_BYTES) + UINT32_C(3)) &                                      \
     ~UINT32_C(3))
#define RS_NPU_P6_CASES_PER_SHARD UINT32_C(100)
#define RS_NPU_P6_UART_TXDATA     UINT32_C(0x10)
#define RS_NPU_P6_UART_STATUS     UINT32_C(0x18)
#define RS_NPU_P6_UART_TX_FULL    UINT32_C(0x20)
#define RS_NPU_P6_UART_POLLS      UINT32_C(1000000)
#define RS_NPU_P6_DIGEST_OFFSET   UINT32_C(44)
#define RS_NPU_P6_CONTEND_SOURCE  UINT32_C(0x3A000000)
#define RS_NPU_P6_CONTEND_DEST    UINT32_C(0x3A400000)
#define RS_NPU_P6_CONTEND_PITCH   UINT32_C(64)
#define RS_NPU_P6_CONTEND_WIDTH   UINT16_C(32)
#define RS_NPU_P6_CONTEND_HEIGHT  UINT16_C(32768)

typedef struct {
    uint32_t shard_index;
    uint32_t first_case;
    uint32_t case_count;
    uint32_t record_bytes;
    const uint8_t *payload;
} rs_npu_p6_shard_t;

static rs_npu_p6_workspace_t s_workspace;
static rs_npu_p6_profile_t s_profile;
static int8_t s_reference_output[RS_NPU_P6_OUTPUT_BYTES];
static int8_t s_npu_output[RS_NPU_P6_OUTPUT_BYTES];
static bool s_uart_ok;

static uint64_t rs_npu_p6_cycles(void) {
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        __asm__ volatile("rdcycleh %0" : "=r"(high_before));
        __asm__ volatile("rdcycle %0" : "=r"(low));
        __asm__ volatile("rdcycleh %0" : "=r"(high_after));
    } while (high_before != high_after);
    return ((uint64_t)high_before << 32U) | low;
}

static void rs_npu_p6_uart_character(char character) {
    uint32_t polls = RS_NPU_P6_UART_POLLS;

    while ((RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, RS_NPU_P6_UART_STATUS) & RS_NPU_P6_UART_TX_FULL) !=
           0U) {
        --polls;
        if (polls == 0U) {
            s_uart_ok = false;
            return;
        }
    }
    RS_SOC_REG32(RS_SOC_APB4_UART1_BASE, RS_NPU_P6_UART_TXDATA) = (uint32_t)(uint8_t)character;
}

static void rs_npu_p6_uart_text(const char *text) {
    if (text == NULL) {
        s_uart_ok = false;
        return;
    }
    while (*text != '\0') {
        rs_npu_p6_uart_character(*text);
        ++text;
    }
}

static void rs_npu_p6_uart_u32(uint32_t value) {
    char digits[10];
    uint32_t count = 0U;

    do {
        digits[count] = (char)('0' + (value % UINT32_C(10)));
        value /= UINT32_C(10);
        ++count;
    } while (value != 0U);
    while (count != 0U) {
        --count;
        rs_npu_p6_uart_character(digits[count]);
    }
}

static void rs_npu_p6_uart_u64(uint64_t value) {
    static const char hexadecimal[] = "0123456789abcdef";

    rs_npu_p6_uart_text("0x");
    for (uint32_t shift = 64U; shift != 0U;) {
        shift -= 4U;
        rs_npu_p6_uart_character(hexadecimal[(value >> shift) & UINT64_C(0xF)]);
    }
}

static uint32_t rs_npu_p6_crc32(const uint8_t *data, uint32_t bytes) {
    uint32_t crc = UINT32_C(0xFFFFFFFF);

    for (uint32_t index = 0U; index < bytes; ++index) {
        crc ^= data[index];
        for (uint32_t bit = 0U; bit < 8U; ++bit) {
            uint32_t mask = UINT32_C(0) - (crc & UINT32_C(1));
            crc = (crc >> 1U) ^ (UINT32_C(0xEDB88320) & mask);
        }
    }
    return ~crc;
}

static bool rs_npu_p6_equal(const uint8_t *left, const uint8_t *right, uint32_t bytes) {
    bool equal = true;

    for (uint32_t index = 0U; index < bytes; ++index) {
        if (left[index] != right[index]) {
            equal = false;
        }
    }
    return equal;
}

static bool rs_npu_p6_parse_shard(rs_npu_p6_shard_t *shard) {
    const uint8_t *image = (const uint8_t *)(uintptr_t)RS_NPU_P6_SHARD_BASE;
    const uint32_t *words = (const uint32_t *)(const void *)image;
    uint32_t payload_bytes;

    if ((shard == NULL) || (words[0] != RS_NPU_P6_SHARD_MAGIC) ||
        (words[1] != RS_NPU_P6_SHARD_SCHEMA) || (words[2] != RS_NPU_P6_WORKLOAD_ID) ||
        (words[4] != UINT32_C(10)) || (words[6] != RS_NPU_P6_CASES_PER_SHARD) ||
        (words[7] != RS_NPU_P6_INPUT_BYTES) || (words[8] != RS_NPU_P6_OUTPUT_BYTES) ||
        (words[9] != RS_NPU_P6_RECORD_BYTES) ||
        !rs_npu_p6_equal(&image[RS_NPU_P6_DIGEST_OFFSET], s_manifest_digest,
                         sizeof(s_manifest_digest))) {
        return false;
    }
    if ((words[3] >= words[4]) || (words[5] != (words[3] * RS_NPU_P6_CASES_PER_SHARD)) ||
        (words[6] > (UINT32_MAX / words[9]))) {
        return false;
    }
    payload_bytes = words[6] * words[9];
    if (rs_npu_p6_crc32(&image[RS_NPU_P6_HEADER_BYTES], payload_bytes) != words[10]) {
        return false;
    }
    shard->shard_index = words[3];
    shard->first_case = words[5];
    shard->case_count = words[6];
    shard->record_bytes = words[9];
    shard->payload = &image[RS_NPU_P6_HEADER_BYTES];
    return true;
}

static uint32_t rs_npu_p6_classification(const int8_t *output) {
    uint32_t best = 0U;

    for (uint32_t index = 1U; index < RS_NPU_P6_OUTPUT_BYTES; ++index) {
        if (output[index] > output[best]) {
            best = index;
        }
    }
    return best;
}

static bool rs_npu_p6_start_contention(void) {
    const rs_ga2d_job_t job = {
        .operation = RS_GA2D_OP_COPY,
        .foreground =
            {
                .address = RS_NPU_P6_CONTEND_SOURCE,
                .pitch = RS_NPU_P6_CONTEND_PITCH,
                .format = RS_GA2D_FORMAT_RGB565,
            },
        .background = {0U, 0U, RS_GA2D_FORMAT_RGB565},
        .destination =
            {
                .address = RS_NPU_P6_CONTEND_DEST,
                .pitch = RS_NPU_P6_CONTEND_PITCH,
                .format = RS_GA2D_FORMAT_RGB565,
            },
        .width = RS_NPU_P6_CONTEND_WIDTH,
        .height = RS_NPU_P6_CONTEND_HEIGHT,
        .global_alpha = UINT8_C(255),
        .color = 0U,
    };

    return (rs_ga2d_configure(&job) == RS_OK) && (rs_ga2d_start() == RS_OK);
}

static void rs_npu_p6_field_u32(const char *name, uint32_t value) {
    rs_npu_p6_uart_character(' ');
    rs_npu_p6_uart_text(name);
    rs_npu_p6_uart_character('=');
    rs_npu_p6_uart_u32(value);
}

static void rs_npu_p6_field_u64(const char *name, uint64_t value) {
    rs_npu_p6_uart_character(' ');
    rs_npu_p6_uart_text(name);
    rs_npu_p6_uart_character('=');
    rs_npu_p6_uart_u64(value);
}

static bool rs_npu_p6_case_fail(uint32_t case_index, const char *stage) {
    rs_npu_p6_uart_text("NPU_P6_CASE_FAIL workload=" RS_NPU_P6_WORKLOAD_NAME);
    rs_npu_p6_field_u32("index", case_index);
    rs_npu_p6_uart_text(" stage=");
    rs_npu_p6_uart_text(stage);
    rs_npu_p6_uart_character('\n');
    return false;
}

static void rs_npu_p6_case_log(uint32_t shard_index, uint32_t case_index, uint32_t label,
                               bool cold_cache, bool contention, uint64_t reference_cycles,
                               uint64_t npu_cycles) {
    rs_npu_p6_uart_text("NPU_P6_CASE workload=" RS_NPU_P6_WORKLOAD_NAME);
    rs_npu_p6_field_u32("shard", shard_index);
    rs_npu_p6_field_u32("index", case_index);
    rs_npu_p6_uart_text(cold_cache ? " cache=cold" : " cache=steady");
    rs_npu_p6_uart_text(contention ? " contention=ga2d-copy-32x32768-rgb565" : " contention=none");
    rs_npu_p6_field_u32("label", label);
    rs_npu_p6_field_u64("reference_cycles", reference_cycles);
    rs_npu_p6_field_u64("npu_cycles", npu_cycles);
    rs_npu_p6_field_u64("input_copy_cycles", s_profile.input_copy_cycles);
    rs_npu_p6_field_u64("npu_wait_cycles", s_profile.npu_wait_cycles);
    rs_npu_p6_field_u64("softmax_cycles", s_profile.softmax_cycles);
    rs_npu_p6_field_u64("active_cycles", s_profile.counters.active_cycles);
    rs_npu_p6_field_u64("clock_pause_cycles", s_profile.counters.clock_pause_cycles);
    rs_npu_p6_field_u64("useful_macs", s_profile.counters.useful_macs);
    rs_npu_p6_field_u64("pack_cycles", s_profile.counters.pack_cycles);
    rs_npu_p6_field_u64("bank_stall_cycles", s_profile.counters.local_bank_stall_cycles);
    rs_npu_p6_field_u64("dma_read_bytes", s_profile.counters.dma_read_bytes);
    rs_npu_p6_field_u64("dma_write_bytes", s_profile.counters.dma_write_bytes);
    rs_npu_p6_field_u64("dma_stall_cycles", s_profile.counters.dma_stall_cycles);
    rs_npu_p6_field_u64("requant_stall_cycles", s_profile.counters.requant_stall_cycles);
    rs_npu_p6_field_u64("retired_descriptors", s_profile.counters.retired_descriptors);
    rs_npu_p6_field_u32("reference_class", rs_npu_p6_classification(s_reference_output));
    rs_npu_p6_field_u32("npu_class", rs_npu_p6_classification(s_npu_output));
    rs_npu_p6_uart_text(" status=PASS\n");
}

static bool rs_npu_p6_run_case(const uint8_t *record, uint32_t expected_index, uint32_t shard_index,
                               bool cold_cache) {
    const uint32_t *header = (const uint32_t *)(const void *)record;
    const int8_t *input = (const int8_t *)(const void *)&record[RS_NPU_P6_CASE_HEADER_BYTES];
    const uint8_t *expected_terminal = &record[RS_NPU_P6_CASE_HEADER_BYTES + RS_NPU_P6_INPUT_BYTES];
    const uint8_t *expected_softmax = &expected_terminal[RS_NPU_P6_OUTPUT_BYTES];
    rs_npu_p6_regions_t regions;
    rs_npu_p6_memory_t memory;
    uint32_t terminal_address;
    uint32_t terminal_offset;
    uint64_t started;
    uint64_t reference_cycles;
    uint64_t npu_cycles;
    bool contention = expected_index < UINT32_C(10);

    if ((header[0] != expected_index) ||
        (rs_npu_p6_default_regions(&s_workspace, &regions) != RS_OK) ||
        (rs_npu_p6_prepare(&s_workspace, &regions, input, RS_NPU_P6_INPUT_BYTES) != RS_OK)) {
        return rs_npu_p6_case_fail(expected_index, "prepare-reference");
    }
    terminal_address =
        s_workspace
            .descriptors[RS_NPU_P6_DESCRIPTOR_COUNT - 1U][RS_NPU_DESCRIPTOR_WORD_OUTPUT_BASE];
    if ((terminal_address < regions.arena_base) ||
        ((terminal_address - regions.arena_base) >
         (RS_NPU_P6_ARENA_BYTES - RS_NPU_P6_OUTPUT_BYTES))) {
        return rs_npu_p6_case_fail(expected_index, "terminal-range");
    }
    terminal_offset = terminal_address - regions.arena_base;
    memory.arena.base = regions.arena_base;
    memory.arena.bytes = sizeof(s_workspace.arena);
    memory.arena.data = s_workspace.arena;
    memory.weights.base = regions.weights_base;
    memory.weights.bytes = sizeof(rs_npu_p6_weights);
    memory.weights.data = rs_npu_p6_weights;
    memory.params.base = regions.params_base;
    memory.params.bytes = sizeof(rs_npu_p6_params);
    memory.params.data = rs_npu_p6_params;
    if (contention && !rs_npu_p6_start_contention()) {
        return rs_npu_p6_case_fail(expected_index, "contention-reference-start");
    }
    started = rs_npu_p6_cycles();
    if ((rs_npu_p6_reference_execute(&s_workspace.descriptors[0][0], RS_NPU_P6_DESCRIPTOR_COUNT,
                                     &memory) != RS_OK) ||
        (rs_npu_p6_softmax((const int8_t *)&s_workspace.arena[terminal_offset],
                           s_reference_output) != RS_OK)) {
        return rs_npu_p6_case_fail(expected_index, "reference-execute");
    }
    reference_cycles = rs_npu_p6_cycles() - started;
    if (contention && (rs_ga2d_wait(RS_TIMEOUT_DEFAULT * UINT32_C(64)) != RS_OK)) {
        return rs_npu_p6_case_fail(expected_index, "contention-reference-wait");
    }
    if (!rs_npu_p6_equal(&s_workspace.arena[terminal_offset], expected_terminal,
                         RS_NPU_P6_OUTPUT_BYTES) ||
        !rs_npu_p6_equal((const uint8_t *)(const void *)s_reference_output, expected_softmax,
                         RS_NPU_P6_OUTPUT_BYTES)) {
        return rs_npu_p6_case_fail(expected_index, "reference-golden");
    }
    if (rs_npu_p6_prepare(&s_workspace, &regions, input, RS_NPU_P6_INPUT_BYTES) != RS_OK) {
        return rs_npu_p6_case_fail(expected_index, "prepare-npu");
    }
    if (contention && !rs_npu_p6_start_contention()) {
        return rs_npu_p6_case_fail(expected_index, "contention-npu-start");
    }
    if (rs_npu_p6_execute(&s_workspace, (RS_NPU_P6_WORKLOAD_ID << 24U) | expected_index,
                          RS_TIMEOUT_DEFAULT * UINT32_C(64), s_npu_output, RS_NPU_P6_OUTPUT_BYTES,
                          &s_profile) != RS_OK) {
        return rs_npu_p6_case_fail(expected_index, "npu-execute");
    }
    npu_cycles = s_profile.npu_wait_cycles + s_profile.softmax_cycles;
    if (contention && (rs_ga2d_wait(RS_TIMEOUT_DEFAULT * UINT32_C(64)) != RS_OK)) {
        return rs_npu_p6_case_fail(expected_index, "contention-npu-wait");
    }
    if ((reference_cycles == 0U) || (npu_cycles == 0U) ||
        (s_profile.counters.retired_descriptors != RS_NPU_P6_DESCRIPTOR_COUNT) ||
        !rs_npu_p6_equal(&s_workspace.arena[terminal_offset], expected_terminal,
                         RS_NPU_P6_OUTPUT_BYTES) ||
        !rs_npu_p6_equal((const uint8_t *)(const void *)s_npu_output, expected_softmax,
                         RS_NPU_P6_OUTPUT_BYTES) ||
        !rs_npu_p6_equal((const uint8_t *)(const void *)s_reference_output,
                         (const uint8_t *)(const void *)s_npu_output, RS_NPU_P6_OUTPUT_BYTES)) {
        return rs_npu_p6_case_fail(expected_index, "npu-golden");
    }
    rs_npu_p6_case_log(shard_index, expected_index, header[1], cold_cache, contention,
                       reference_cycles, npu_cycles);
    return s_uart_ok;
}

int rs_hp_npu_p6_acceptance(void) {
    rs_npu_p6_shard_t shard;

    s_uart_ok = true;
    if ((rs_npu_irq_ack(RS_NPU_IRQ_ALL) != RS_OK) || (rs_npu_irq_enable(0U) != RS_OK) ||
        !rs_npu_p6_parse_shard(&shard)) {
        return 0;
    }
    rs_npu_p6_uart_text("NPU_P6_BEGIN workload=" RS_NPU_P6_WORKLOAD_NAME);
    rs_npu_p6_field_u32("shard", shard.shard_index);
    rs_npu_p6_field_u32("first", shard.first_case);
    rs_npu_p6_field_u32("cases", shard.case_count);
    rs_npu_p6_uart_text(
        " cache_policy=cold-first-steady-subsequent timing=rdcycle_72mhz input_copy=excluded "
        "corpus_transport=excluded contention=ga2d-first-10\n");
    for (uint32_t index = 0U; index < shard.case_count; ++index) {
        const uint8_t *record = &shard.payload[index * shard.record_bytes];

        if (!rs_npu_p6_run_case(record, shard.first_case + index, shard.shard_index, index == 0U)) {
            return 0;
        }
    }
    rs_npu_p6_uart_text("NPU_P6_SHARD_PASS workload=" RS_NPU_P6_WORKLOAD_NAME);
    rs_npu_p6_field_u32("shard", shard.shard_index);
    rs_npu_p6_field_u32("cases", shard.case_count);
    rs_npu_p6_uart_character('\n');
    return s_uart_ok ? 1 : 0;
}

static void rs_npu_p6_clean_range(const void *pointer, uint32_t bytes) {
    uintptr_t cursor = (uintptr_t)pointer & ~(uintptr_t)UINT32_C(63);
    uintptr_t end = ((uintptr_t)pointer + bytes + UINT32_C(63)) & ~(uintptr_t)UINT32_C(63);

    while (cursor < end) {
        __asm__ volatile("cbo.clean 0(%0)" : : "r"(cursor) : "memory");
        cursor += UINT32_C(64);
    }
}

void rs_hp_npu_p6_cache_clean(void) {
    rs_npu_p6_clean_range(&s_workspace, sizeof(s_workspace));
    rs_npu_p6_clean_range(&s_profile, sizeof(s_profile));
    rs_npu_p6_clean_range(s_reference_output, sizeof(s_reference_output));
    rs_npu_p6_clean_range(s_npu_output, sizeof(s_npu_output));
    rs_npu_p6_clean_range(rs_npu_p6_weights, sizeof(rs_npu_p6_weights));
    rs_npu_p6_clean_range(rs_npu_p6_params, sizeof(rs_npu_p6_params));
    __asm__ volatile("fence rw, rw" : : : "memory");
}
