/* Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0 */
#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/onchip_sram.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

/* P3 compact experiment: four retained destinations fit B3. This is not the
 * original P1 matched binary. Verification remains outside measured windows. */
#define RS_P3_WORDS      1024U
#define RS_P3_JOBS       4U
#define RS_P3_GUARDS     16U
#define RS_P3_CASES      8U
#define RS_P3_ITERATIONS 4096U
#define RS_P3_SEED       UINT32_C(0x12345678)
#define RS_P3_EXPECTED   UINT32_C(0xf6e37410)
#define RS_P3_PATTERN    UINT32_C(0xa519c300)
#define RS_P3_GUARD      UINT32_C(0x5a36c9e7)

typedef struct {
    uint32_t before[RS_P3_GUARDS];
    uint32_t words[RS_P3_WORDS];
    uint32_t after[RS_P3_GUARDS];
} rs_p3_buffer_t;

typedef struct {
    uint64_t cycles;
    uint64_t instructions;
    uint64_t kernel_cycles;
    uint64_t cpu_wait;
    uint64_t dma_wait;
    rs_onchip_sram_perf_t memory;
    uint32_t checksum;
    uint32_t kernel_calls;
    uint32_t payload_bytes;
} rs_p3_result_t;

static _Alignas(64) volatile rs_p3_buffer_t rs_p3_source
    __attribute__((section(".bss.rs_dma.buffers")));
static _Alignas(64) volatile rs_p3_buffer_t rs_p3_destinations[RS_P3_JOBS]
    __attribute__((section(".bss.rs_dma.buffers")));
static _Alignas(64) rs_dma_tcd_t rs_p3_tcds[RS_P3_JOBS][4]
    __attribute__((section(".bss.rs_dma.tcd")));
static volatile uint32_t rs_p3_dma_cookie __attribute__((section(".data.rs_dma"))) =
    UINT32_C(0x7135a9c2);
static rs_dma_session_t rs_p3_owner;
uint32_t rs_p3_isa_check(void);
extern uint32_t _stack_point[];
extern uint32_t _ebss[];
static uintptr_t rs_p3_stack_floor;
static uintptr_t rs_p3_stack_painted_end;
static rs_p3_result_t rs_p3_results[RS_P3_CASES];
static volatile uint32_t rs_p3_seed = RS_P3_SEED;

static uint64_t rs_p3_cycles(void) {
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

static uint64_t rs_p3_instructions(void) {
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

static uint32_t rs_p3_kernel(uint32_t value) {
    for (uint32_t index = 0U; index < RS_P3_ITERATIONS; ++index) {
        value ^= value << 13U;
        value ^= value >> 17U;
        value ^= value << 5U;
    }
    return value;
}

static bool rs_p3_cpu(rs_p3_result_t *result) {
    const uint32_t seed = rs_p3_seed;
    const uint64_t begin = rs_p3_cycles();
    const uint32_t value = rs_p3_kernel(seed);
    __COMPILER_BARRIER();
    result->kernel_cycles += rs_p3_cycles() - begin;
    result->checksum = value;
    ++result->kernel_calls;
    return value == RS_P3_EXPECTED;
}

static void rs_p3_initialize(void) {
    for (uint32_t index = 0U; index < RS_P3_GUARDS; ++index) {
        rs_p3_source.before[index] = RS_P3_GUARD;
        rs_p3_source.after[index] = RS_P3_GUARD;
    }
    for (uint32_t index = 0U; index < RS_P3_WORDS; ++index) {
        rs_p3_source.words[index] = RS_P3_PATTERN ^ index;
    }
    for (uint32_t job = 0U; job < RS_P3_JOBS; ++job) {
        for (uint32_t index = 0U; index < RS_P3_GUARDS; ++index) {
            rs_p3_destinations[job].before[index] = RS_P3_GUARD;
            rs_p3_destinations[job].after[index] = RS_P3_GUARD;
        }
        for (uint32_t index = 0U; index < RS_P3_WORDS; ++index) {
            rs_p3_destinations[job].words[index] = UINT32_C(0xcccccccc);
        }
        for (uint32_t part = 0U; part < 4U; ++part) {
            rs_dma_tcd_t *const tcd = &rs_p3_tcds[job][part];
            *tcd = (rs_dma_tcd_t){0};
            if (part < 3U) {
                tcd->next_ptr = (uint32_t)(uintptr_t)&rs_p3_tcds[job][part + 1U];
            }
            tcd->source = (uint32_t)(uintptr_t)&rs_p3_source.words[part * 256U];
            tcd->destination = (uint32_t)(uintptr_t)&rs_p3_destinations[job].words[part * 256U];
            tcd->byte_count = UINT32_C(1024);
            tcd->control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                           (UINT32_C(16) << RS_DMA_TCD_BURST_SHIFT);
        }
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
}

static bool rs_p3_readback(uint32_t *checksum) {
    uint32_t hash = UINT32_C(2166136261);
    for (uint32_t index = 0U; index < RS_P3_GUARDS; ++index) {
        if ((rs_p3_source.before[index] != RS_P3_GUARD) ||
            (rs_p3_source.after[index] != RS_P3_GUARD)) {
            return false;
        }
    }
    for (uint32_t job = 0U; job < RS_P3_JOBS; ++job) {
        for (uint32_t index = 0U; index < RS_P3_GUARDS; ++index) {
            if ((rs_p3_destinations[job].before[index] != RS_P3_GUARD) ||
                (rs_p3_destinations[job].after[index] != RS_P3_GUARD)) {
                return false;
            }
        }
        for (uint32_t index = 0U; index < RS_P3_WORDS; ++index) {
            const uint32_t expected = RS_P3_PATTERN ^ index;
            const uint32_t observed = rs_p3_destinations[job].words[index];
            if ((observed != expected) || (rs_p3_source.words[index] != expected)) {
                return false;
            }
            /* Explicit unsigned modulo-2^32 diagnostic hash; full comparison
             * above is authoritative, rather than a hash-only memory check. */
            hash = (hash ^ observed) * UINT32_C(16777619);
        }
    }
    *checksum = hash;
    return true;
}

static bool rs_p3_dma(uint32_t case_id, rs_p3_result_t *result) {
    const bool descriptors = case_id == 6U;
    const bool concurrent_cpu = case_id >= 5U;
    const uint8_t burst = (case_id == 3U) ? 1U : 16U;
    const uint32_t chunk = (case_id == 7U) ? 256U : 4096U;
    rs_dma_status_t status;
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .byte_count = chunk,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .priority = 0U,
        .burst_beats = burst,
    };
    if (rs_dma_session_acquire(&rs_p3_owner, RS_DMA_CHANNEL_BULK) != RS_OK) {
        return false;
    }
    for (uint32_t job = 0U; job < RS_P3_JOBS; ++job) {
        for (uint32_t offset = 0U; offset < 4096U; offset += chunk) {
            config.source = (uintptr_t)&rs_p3_source.words[offset / 4U];
            config.destination = (uintptr_t)&rs_p3_destinations[job].words[offset / 4U];
            if (rs_dma_session_configure(&rs_p3_owner, &config) != RS_OK) {
                return false;
            }
            /* The verification image owns this channel for the finite hardware
             * chain. The existing convenience TCD helper submits one at a time. */
            RS_DMA_CH_REG(RS_DMA_CHANNEL_BULK, RS_DMA_CH_REG_TCD_HEAD) =
                descriptors ? (uint32_t)(uintptr_t)&rs_p3_tcds[job][0] : 0U;
            RS_DMA_CH_REG(RS_DMA_CHANNEL_BULK, RS_DMA_CH_REG_TCD_COUNT) = descriptors ? 4U : 0U;
            if (rs_dma_session_start(&rs_p3_owner) != RS_OK) {
                return false;
            }
            if (concurrent_cpu && (offset == 0U) && !rs_p3_cpu(result)) {
                return false;
            }
            if ((rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK) ||
                (rs_dma_get_status(RS_DMA_CHANNEL_BULK, &status) != RS_OK) || status.busy ||
                status.error || status.aborted || !status.done ||
                (status.bytes_done != (descriptors ? 1024U : chunk))) {
                return false;
            }
            result->payload_bytes += chunk;
            __asm__ volatile("fence rw, rw" ::: "memory");
        }
    }
    return rs_dma_session_release(&rs_p3_owner) == RS_OK;
}

static bool rs_p3_case(uint32_t case_id) {
    rs_p3_result_t *const result = &rs_p3_results[case_id];
    uint64_t cycles_begin;
    uint64_t instructions_begin;
    bool pass = true;

    if (case_id >= 2U) {
        rs_p3_initialize();
    }
    if ((rs_dma_reset(RS_DMA_CHANNEL_BULK) != RS_OK) ||
        (rs_sysctrl_set_perf_control(false, true, false) != RS_OK) ||
        (rs_sysctrl_set_perf_control(true, false, false) != RS_OK)) {
        return false;
    }
    __COMPILER_BARRIER();
    cycles_begin = rs_p3_cycles();
    instructions_begin = rs_p3_instructions();
    if (case_id == 1U) {
        pass = rs_p3_cpu(result);
    } else if (case_id == 2U) {
        for (uint32_t job = 0U; job < RS_P3_JOBS; ++job) {
            for (uint32_t index = 0U; index < RS_P3_WORDS; ++index) {
                rs_p3_destinations[job].words[index] = rs_p3_source.words[index];
            }
        }
        result->payload_bytes = UINT32_C(16384);
    } else if (case_id >= 3U) {
        pass = rs_p3_dma(case_id, result);
    } else {
        /* Empty-window calibration intentionally includes measurement overhead. */
    }
    __COMPILER_BARRIER();
    result->instructions = rs_p3_instructions() - instructions_begin;
    result->cycles = rs_p3_cycles() - cycles_begin;
    if ((rs_sysctrl_set_perf_control(false, false, true) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_MGMT_WAIT, &result->cpu_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_DMA_WAIT, &result->dma_wait) != RS_OK) ||
        (rs_onchip_sram_read_performance(&result->memory) != RS_OK)) {
        return false;
    }
    if (pass && (case_id >= 2U)) {
        pass = rs_p3_readback(&result->checksum);
    }
    return pass && (result->memory.error_responses == 0U);
}

static void rs_p3_finish(bool pass, uint8_t code) {
    rs_uart_status_t status;
    uint32_t timeout = RS_TIMEOUT_DEFAULT;
    bool drained = false;

    while (timeout != 0U) {
        --timeout;
        if (rs_uart_get_status(&status) != RS_OK) {
            break;
        }
        if ((status.tx_level == 0U) && ((status.flags & UINT32_C(4)) == 0U)) {
            drained = true;
            break;
        }
    }
    rs_sysctrl_write_test_status(pass && drained, drained ? code : UINT8_C(250));
    for (;;) {
    }
}

int main(void) {
    static const char *const names[RS_P3_CASES] = {
        "empty", "cpu", "memory", "dma1", "dma16", "contention", "tcd", "chunk256",
    };
    rs_onchip_sram_info_t memory;

    /* Source identity is retained by the host evidence manifest. Replay checks
     * the stable memory/ISA contract, not equality to a future RTL git hash.
     * The separate normal acceptance image keeps its full ArchInfo checks. */
    if ((rs_uart_init(RS_CPU_CLOCK_HZ, UART_BPS) != RS_OK) ||
        (rs_onchip_sram_probe(&memory) != RS_OK) || !memory.present ||
        (memory.memory_bytes != UINT32_C(131072)) || (memory.bank_count != 32U) ||
        (memory.data_bytes != 4U) || ((__RV_CSR_READ(CSR_MISA) & UINT32_C(1)) != 0U)) {
        rs_p3_finish(false, 1U);
    }
    if ((rs_p3_dma_cookie != UINT32_C(0x7135a9c2)) ||
        (rs_p3_source.words[RS_P3_WORDS - 1U] != 0U) ||
        (rs_p3_destinations[RS_P3_JOBS - 1U].words[RS_P3_WORDS - 1U] != 0U) ||
        (rs_p3_isa_check() != 0U)) {
        rs_p3_finish(false, 20U);
    }
    rs_p3_stack_floor = (uintptr_t)_stack_point - 4096U;
    __asm__ volatile("mv %0, sp" : "=r"(rs_p3_stack_painted_end));
    if (((uintptr_t)_ebss > rs_p3_stack_floor) ||
        (rs_p3_stack_painted_end < rs_p3_stack_floor + 128U)) {
        rs_p3_finish(false, 21U);
    }
    rs_p3_stack_painted_end -= 128U;
    for (uintptr_t address = rs_p3_stack_floor; address < rs_p3_stack_painted_end; address += 4U) {
        *(volatile uint32_t *)address = UINT32_C(0xc35a9e71);
    }
    for (uint32_t case_id = 0U; case_id < RS_P3_CASES; ++case_id) {
        if (!rs_p3_case(case_id)) {
            printf("P3_ERROR case=%u\n", case_id);
            rs_p3_finish(false, (uint8_t)(case_id + 2U));
        }
    }
    /* UART output is entirely outside every performance window. */
    printf("P3_HEADER version=3 cpu_hz=%u words=%u jobs=%u iterations=%u seed=0x%08x\n",
           RS_CPU_CLOCK_HZ, RS_P3_WORDS, RS_P3_JOBS, RS_P3_ITERATIONS, RS_P3_SEED);
    for (uint32_t case_id = 0U; case_id < RS_P3_CASES; ++case_id) {
        const rs_p3_result_t *const result = &rs_p3_results[case_id];
        printf("P3_CASE id=%u name=%s cycles=%llu instructions=%llu kernel_cycles=%llu "
               "kernel_calls=%u payload_bytes=%u checksum=0x%08x cpu_wait=%llu dma_wait=%llu "
               "sram_reads=%u sram_writes=%u sram_rbeats=%u sram_wbeats=%u sram_stalls=%u "
               "sram_errors=%u\n",
               case_id, names[case_id], (unsigned long long)result->cycles,
               (unsigned long long)result->instructions, (unsigned long long)result->kernel_cycles,
               result->kernel_calls, result->payload_bytes, result->checksum,
               (unsigned long long)result->cpu_wait, (unsigned long long)result->dma_wait,
               result->memory.read_requests, result->memory.write_requests,
               result->memory.read_beats, result->memory.write_beats, result->memory.stall_cycles,
               result->memory.error_responses);
    }
    {
        uintptr_t first = rs_p3_stack_floor;
        while ((first < rs_p3_stack_painted_end) &&
               (*(volatile const uint32_t *)first == UINT32_C(0xc35a9e71))) {
            first += 4U;
        }
        printf("P3_STACK reserved=4096 observed=%u\n", (uint32_t)((uintptr_t)_stack_point - first));
    }
    printf("P3_ISA PASS\n");
    printf("P3_COMPLETE version=3 cases=%u\n", RS_P3_CASES);
    rs_p3_finish(true, 0U);
    return 0;
}
