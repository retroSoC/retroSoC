#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/apu.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/hp_mailbox.h>
#include <retrosoc/hal/resource.h>
#include <retrosoc/hal/sdram.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

#include "hp_boot_bundle.h"
#include "apu_release_page.h"
#include "apu_release_assets.h"

#define RS_APU_RELEASE_DMA_TIMEOUT    (RS_TIMEOUT_DEFAULT * UINT32_C(64))
#define RS_APU_RELEASE_QUIESCE_BUDGET RS_TIMEOUT_DEFAULT
/* Loader polls count APB round trips, not cycles: on the Verilator SoC each
 * read crosses several clock domains, so the image fetches can consume tens of
 * thousands of polls before publishing. The budget bounds only a genuinely
 * stuck loader; every hardware failure path terminates the load early. */
#define RS_APU_RELEASE_LOAD_TIMEOUT   UINT32_C(250000)
#define RS_APU_RELEASE_EVENT_BUDGET   UINT32_C(0x04000000)
/* Settling spins between the SDRAM result flag and the single mailbox read:
 * covers the tail of the HP's publish writes so the read runs on a quiet bus. */
#define RS_APU_RELEASE_SETTLE_SPINS   UINT32_C(100000)
/* Bounded poll for the page result magic to become visible after the mailbox
 * event: the HP CBO-cleans the page before publishing, but the writeback and
 * the event cross different interconnect paths, so the page can lag the event
 * by a few hundred cycles. Each poll is one SDRAM round trip. */
#define RS_APU_RELEASE_SETTLE_BUDGET  UINT32_C(100000)
#define RS_APU_RELEASE_FAULT_MCAUSE   UINT32_C(7)

static rs_dma_tcd_t s_apu_release_tcd __attribute__((aligned(64)));

_Static_assert(sizeof(rs_hp_boot_header_t) == UINT32_C(128), "HP bundle header ABI mismatch");

static uint32_t rs_apu_release_cycle(void) {
    uint32_t cycle;

    __asm__ volatile("csrr %0, mcycle" : "=r"(cycle));
    return cycle;
}

static void rs_apu_release_milestone(const char *name) {
    printf("APU_RELEASE_CYCLE:%s:%08lx\n", name, (unsigned long)rs_apu_release_cycle());
}

static uint32_t rs_apu_release_crc32_byte(uint32_t crc, uint8_t value) {
    crc ^= value;
    for (uint32_t bit = 0U; bit < 8U; ++bit) {
        uint32_t mask = UINT32_C(0) - (crc & UINT32_C(1));
        crc = (crc >> 1U) ^ (UINT32_C(0xEDB88320) & mask);
    }
    return crc;
}

static uint32_t rs_apu_release_crc32(const volatile uint8_t *data, uint32_t size) {
    uint32_t crc = UINT32_C(0xFFFFFFFF);

    for (uint32_t index = 0U; index < size; ++index) {
        crc = rs_apu_release_crc32_byte(crc, data[index]);
    }
    return ~crc;
}

static void rs_apu_release_fail(uint8_t code) {
    /* Report the failure BEFORE draining the HP: the drain flush clears the
     * LP's data-plane CDC, which would drop an in-flight printf stack access
     * and wedge the hart before the diagnostic ever reaches the UART. */
    printf("APU_RELEASE_FAIL:%u\n", (unsigned int)code);
    (void)rs_sysctrl_set_hp_release(false);
    rs_test_finish(RS_TEST_FAILED, code);
}

static bool rs_apu_release_wait_sdram(void) {
    rs_sdram_status_t status;

    for (uint32_t timeout = 0U; timeout < RS_TIMEOUT_DEFAULT; ++timeout) {
        if ((rs_sdram_get_status(&status) == RS_OK) && status.ready && !status.init_busy &&
            !status.error) {
            return true;
        }
    }
    return false;
}

static void rs_apu_release_read_header(rs_hp_boot_header_t *header) {
    volatile const uint8_t *source =
        (volatile const uint8_t *)(uintptr_t)(RS_SOC_FLASH_BASE + RS_HP_BOOT_BUNDLE_OFFSET);
    uint8_t *destination = (uint8_t *)header;

    for (uint32_t index = 0U; index < sizeof(*header); ++index) {
        destination[index] = source[index];
    }
}

static bool rs_apu_release_range_valid(uint32_t address, uint32_t size, uint32_t base,
                                       uint32_t capacity) {
    return (size != 0U) && (address >= base) && (address < (base + capacity)) &&
           ((size - 1U) <= ((base + capacity - 1U) - address));
}

static bool rs_apu_release_header_valid(rs_hp_boot_header_t *header) {
    uint32_t expected_crc = header->header_crc32;

    header->header_crc32 = 0U;
    if ((header->magic != RS_HP_BOOT_BUNDLE_MAGIC) ||
        (header->version != RS_HP_BOOT_BUNDLE_VERSION) ||
        (header->header_size != sizeof(*header)) ||
        (header->entry_count != RS_HP_BOOT_BUNDLE_ENTRY_COUNT) ||
        (header->total_size < sizeof(*header)) ||
        (header->total_size > (RS_SOC_FLASH_SIZE - RS_HP_BOOT_BUNDLE_OFFSET)) ||
        (rs_apu_release_crc32((volatile const uint8_t *)header, sizeof(*header)) != expected_crc)) {
        return false;
    }
    for (uint32_t index = 0U; index < RS_HP_BOOT_BUNDLE_ENTRY_COUNT; ++index) {
        const rs_hp_boot_entry_t *entry = &header->entries[index];

        if ((entry->size == 0U) || ((entry->flash_offset & UINT32_C(3)) != 0U) ||
            ((entry->load_address & UINT32_C(3)) != 0U) ||
            !rs_apu_release_range_valid(entry->flash_offset, entry->size, RS_HP_BOOT_BUNDLE_OFFSET,
                                        header->total_size) ||
            !rs_apu_release_range_valid(entry->load_address, entry->size, RS_SOC_SDRAM_BASE,
                                        RS_SOC_SDRAM_SIZE)) {
            return false;
        }
    }
    return true;
}

static bool rs_apu_release_dma_copy(uint32_t source, uint32_t destination, uint32_t size,
                                    uint32_t expected_crc) {
    rs_status_t status;

    s_apu_release_tcd.next_ptr = UINT32_C(0);
    s_apu_release_tcd.source = source;
    s_apu_release_tcd.destination = destination;
    s_apu_release_tcd.byte_count = size;
    s_apu_release_tcd.source_stride = 0;
    s_apu_release_tcd.destination_stride = 0;
    s_apu_release_tcd.y_count = UINT16_C(1);
    s_apu_release_tcd.reserved = UINT16_C(0);
    s_apu_release_tcd.control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                                RS_DMA_TCD_CRC_ENABLE | RS_DMA_TCD_CRC_FINAL |
                                (UINT32_C(3) << RS_DMA_TCD_PRIORITY_SHIFT) |
                                (UINT32_C(16) << RS_DMA_TCD_BURST_SHIFT);
    s_apu_release_tcd.control |= ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT) |
                                 ((uint32_t)RS_DMA_REQUEST_SOFTWARE << RS_DMA_TCD_REQUEST_SHIFT);
    s_apu_release_tcd.crc_expected = expected_crc;
    s_apu_release_tcd.crc_seed = UINT32_C(0xFFFFFFFF);
    s_apu_release_tcd.crc_result = UINT32_C(0);
    s_apu_release_tcd.status = UINT32_C(0);
    s_apu_release_tcd.bytes_done = UINT32_C(0);
    s_apu_release_tcd.error_status = UINT32_C(0);
    s_apu_release_tcd.reserved_tail = UINT32_C(0);
    s_apu_release_tcd.reserved_tail2 = UINT32_C(0);
    __asm__ volatile("fence rw, rw" ::: "memory");
    status = rs_dma_submit_tcd(RS_DMA_CHANNEL_HP, &s_apu_release_tcd, RS_APU_RELEASE_DMA_TIMEOUT);
    __asm__ volatile("fence rw, rw" ::: "memory");
    return (status == RS_OK) && (s_apu_release_tcd.bytes_done == size) &&
           (s_apu_release_tcd.crc_result == expected_crc);
}

static bool rs_apu_release_cpu_copy(uint32_t source, uint32_t destination, uint32_t size,
                                    uint32_t expected_crc) {
    volatile const uint32_t *source_words = (volatile const uint32_t *)(uintptr_t)source;
    volatile uint32_t *destination_words = (volatile uint32_t *)(uintptr_t)destination;
    uint32_t word_count = size / (uint32_t)sizeof(uint32_t);

    for (uint32_t index = 0U; index < word_count; ++index) {
        destination_words[index] = source_words[index];
    }
    for (uint32_t index = word_count * (uint32_t)sizeof(uint32_t); index < size; ++index) {
        volatile const uint8_t *source_bytes = (volatile const uint8_t *)(uintptr_t)source;
        volatile uint8_t *destination_bytes = (volatile uint8_t *)(uintptr_t)destination;
        destination_bytes[index] = source_bytes[index];
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
    return rs_apu_release_crc32((volatile const uint8_t *)(uintptr_t)destination, size) ==
           expected_crc;
}

static bool rs_apu_release_stage(uint32_t source, uint32_t destination, uint32_t size,
                                 uint32_t expected_crc) {
    if (((source & UINT32_C(3)) != 0U) || ((destination & UINT32_C(63)) != 0U) || (size == 0U)) {
        return false;
    }
    /* The DMA engine CRCs the transferred bytes end-to-end; the CPU fallback
     * verifies with a readback CRC. The APU loader re-verifies the staged
     * microcode/model payload CRCs in hardware, so no extra LP pass is made. */
    if (!rs_apu_release_dma_copy(source, destination, size, expected_crc) &&
        !rs_apu_release_cpu_copy(source, destination, size, expected_crc)) {
        return false;
    }
    return true;
}

static bool rs_apu_release_load_bundle(void) {
    rs_hp_boot_header_t header;

    rs_apu_release_read_header(&header);
    if (!rs_apu_release_header_valid(&header)) {
        return false;
    }
    for (uint32_t index = 0U; index < RS_HP_BOOT_BUNDLE_ENTRY_COUNT; ++index) {
        const rs_hp_boot_entry_t *entry = &header.entries[index];

        if (!rs_apu_release_dma_copy(RS_SOC_FLASH_BASE + entry->flash_offset, entry->load_address,
                                     entry->size, entry->crc32) &&
            !rs_apu_release_cpu_copy(RS_SOC_FLASH_BASE + entry->flash_offset, entry->load_address,
                                     entry->size, entry->crc32)) {
            return false;
        }
    }
    return true;
}

static bool rs_apu_release_quiesce(void) {
    if (rs_resource_set_lifecycle(RS_RESOURCE_APU, true, false) != RS_OK) {
        return false;
    }
    for (uint32_t budget = 0U; budget < RS_APU_RELEASE_QUIESCE_BUDGET; ++budget) {
        const uint32_t owner = RS_APU_REG(RS_APU_ABI_OWNER_STATUS);
        const uint32_t status = RS_APU_REG(RS_APU_ABI_STATUS);

        if (((owner & UINT32_C(3)) == 0U) &&
            ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_QUIESCE)) != 0U) &&
            ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_RESET)) == 0U) &&
            ((status & (UINT32_C(1) << RS_APU_ABI_STATUS_IDLE)) != 0U)) {
            return true;
        }
    }
    return false;
}

static bool rs_apu_release_stage_assets(void) {
    if (!rs_apu_release_stage((uint32_t)(uintptr_t)rs_apu_release_apumc, RS_APU_RELEASE_MC_ADDRESS,
                              RS_APU_RELEASE_APUMC_SIZE, RS_APU_RELEASE_APUMC_CRC)) {
        return false;
    }
    if (!rs_apu_release_stage((uint32_t)(uintptr_t)rs_apu_release_apuc,
                              RS_APU_RELEASE_COEFF_ADDRESS, RS_APU_RELEASE_APUC_SIZE,
                              RS_APU_RELEASE_APUC_CRC)) {
        return false;
    }
    if (!rs_apu_release_stage((uint32_t)(uintptr_t)rs_apu_release_apum,
                              RS_APU_RELEASE_MODEL_ADDRESS, RS_APU_RELEASE_APUM_SIZE,
                              RS_APU_RELEASE_APUM_CRC)) {
        return false;
    }
    if (!rs_apu_release_stage((uint32_t)(uintptr_t)rs_apu_release_wav, RS_APU_RELEASE_WAV_ADDRESS,
                              RS_APU_RELEASE_WAV_SIZE, RS_APU_RELEASE_WAV_CRC)) {
        return false;
    }
    if (!rs_apu_release_stage((uint32_t)(uintptr_t)rs_apu_release_kws_pcm,
                              RS_APU_RELEASE_KWS_ADDRESS, RS_APU_RELEASE_KWS_SIZE,
                              RS_APU_RELEASE_KWS_CRC)) {
        return false;
    }
    return true;
}

static void rs_apu_release_dump_apu(void) {
    printf("APU_RELEASE_DBG:%08lx:%08lx:%08lx:%08lx:%08lx:%08lx:%08lx:%08lx\n",
           (unsigned long)RS_APU_REG(RS_APU_ABI_STATUS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_OWNER_STATUS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_MC_STATUS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_MC_ACTUAL_CRC),
           (unsigned long)RS_APU_REG(RS_APU_ABI_KWS_MODEL_STATUS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_ERROR_STATUS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_ERROR_ADDRESS),
           (unsigned long)RS_APU_REG(RS_APU_ABI_ERROR_DETAIL));
}

static uint32_t rs_apu_release_load_images(void) {
    const rs_apu_image_t mc_image = {
        .address = RS_APU_RELEASE_MC_ADDRESS,
        .bytes = RS_APU_RELEASE_APUMC_SIZE,
        .expected_crc = RS_APU_RELEASE_APUMC_PAYLOAD_CRC,
    };
    const rs_apu_image_t model_image = {
        .address = RS_APU_RELEASE_MODEL_ADDRESS,
        .bytes = RS_APU_RELEASE_APUM_SIZE,
        .expected_crc = RS_APU_RELEASE_APUM_PAYLOAD_CRC,
    };
    const rs_apu_image_t coefficient_image = {
        .address = RS_APU_RELEASE_COEFF_ADDRESS,
        .bytes = RS_APU_RELEASE_APUC_SIZE,
        .expected_crc = RS_APU_RELEASE_APUC_PAYLOAD_CRC,
    };
    uint32_t status;
    rs_status_t load_status;

    __asm__ volatile("fence rw, rw" ::: "memory");
    load_status = rs_apu_microcode_load(&mc_image, RS_APU_RELEASE_LOAD_TIMEOUT);
    if (load_status != RS_OK) {
        printf("APU_RELEASE_MCERR:%d\n", (int)load_status);
        rs_apu_release_dump_apu();
        return 1U;
    }
    status = RS_APU_REG(RS_APU_ABI_MC_STATUS);
    if (((status & (UINT32_C(1) << RS_APU_ABI_MC_STATUS_VALID)) == 0U) ||
        (RS_APU_REG(RS_APU_ABI_MC_LOCK) == 0U) ||
        (RS_APU_REG(RS_APU_ABI_MC_ACTUAL_CRC) != RS_APU_RELEASE_APUMC_PAYLOAD_CRC)) {
        rs_apu_release_dump_apu();
        return 2U;
    }
    printf("APU_RELEASE_MC:%08lx\n", (unsigned long)RS_APU_REG(RS_APU_ABI_MC_ACTUAL_CRC));
    rs_apu_release_milestone("MC");
    __asm__ volatile("fence rw, rw" ::: "memory");
    load_status = rs_apu_kws_coeff_load(&coefficient_image, RS_APU_RELEASE_LOAD_TIMEOUT);
    if (load_status != RS_OK) {
        printf("APU_RELEASE_COEFFERR:%d\n", (int)load_status);
        rs_apu_release_dump_apu();
        return 3U;
    }
    status = RS_APU_REG(RS_APU_ABI_KWS_COEFF_STATUS);
    if (((status & UINT32_C(6)) != UINT32_C(6)) ||
        (RS_APU_REG(RS_APU_ABI_KWS_COEFF_ACTUAL_CRC) != RS_APU_RELEASE_APUC_PAYLOAD_CRC)) {
        rs_apu_release_dump_apu();
        return 4U;
    }
    printf("APU_RELEASE_COEFF:%08lx\n", (unsigned long)RS_APU_REG(RS_APU_ABI_KWS_COEFF_ACTUAL_CRC));
    rs_apu_release_milestone("COEFF");
    __asm__ volatile("fence rw, rw" ::: "memory");
    load_status = rs_apu_kws_model_load(&model_image, RS_APU_RELEASE_LOAD_TIMEOUT);
    if (load_status != RS_OK) {
        printf("APU_RELEASE_MODELERR:%d\n", (int)load_status);
        rs_apu_release_dump_apu();
        return 5U;
    }
    status = RS_APU_REG(RS_APU_ABI_KWS_MODEL_STATUS);
    if (((status & UINT32_C(6)) != UINT32_C(6)) ||
        (RS_APU_REG(RS_APU_ABI_KWS_MODEL_ACTUAL_CRC) != RS_APU_RELEASE_APUM_PAYLOAD_CRC)) {
        rs_apu_release_dump_apu();
        return 6U;
    }
    printf("APU_RELEASE_MODEL:%08lx\n", (unsigned long)RS_APU_REG(RS_APU_ABI_KWS_MODEL_ACTUAL_CRC));
    rs_apu_release_milestone("MODEL");
    return 0U;
}

static void rs_apu_release_fill_page(void) {
    volatile rs_apu_release_page_t *page =
        (volatile rs_apu_release_page_t *)(uintptr_t)RS_APU_RELEASE_PAGE_ADDRESS;
    volatile uint32_t *words = (volatile uint32_t *)(uintptr_t)RS_APU_RELEASE_PAGE_ADDRESS;

    for (uint32_t index = 0U; index < (uint32_t)(sizeof(rs_apu_release_page_t) / sizeof(uint32_t));
         ++index) {
        words[index] = UINT32_C(0);
    }
    page->magic = RS_APU_RELEASE_PAGE_MAGIC;
    page->version = RS_APU_RELEASE_PAGE_VERSION;
    page->wav_address = RS_APU_RELEASE_WAV_ADDRESS;
    page->wav_bytes = RS_APU_RELEASE_WAV_SIZE;
    page->wav_crc = RS_APU_RELEASE_WAV_CRC;
    page->output_address = RS_APU_RELEASE_PCM_ADDRESS;
    page->output_capacity = RS_APU_RELEASE_PCM_CAPACITY;
    page->expected_output_crc = RS_APU_RELEASE_PCM_CRC;
    page->expected_output_bytes = RS_APU_RELEASE_PCM_BYTES;
    page->expected_frames = RS_APU_RELEASE_PCM_FRAMES;
    page->wav_rate = RS_APU_RELEASE_WAV_RATE;
    page->wav_channels = RS_APU_RELEASE_WAV_CHANNELS;
    page->wav_bits = RS_APU_RELEASE_WAV_BITS;
    page->kws_address = RS_APU_RELEASE_KWS_ADDRESS;
    page->kws_bytes = RS_APU_RELEASE_KWS_SIZE;
    page->kws_expected_class = RS_APU_RELEASE_KWS_CLASS;
    page->kws_threshold = RS_APU_RELEASE_KWS_THRESHOLD;
    page->kws_debounce = RS_APU_RELEASE_KWS_DEBOUNCE;
    page->acl_read_base = RS_APU_RELEASE_ACL_READ_BASE;
    page->acl_read_limit = RS_APU_RELEASE_ACL_READ_LIMIT;
    page->acl_write_base = RS_APU_RELEASE_ACL_WRITE_BASE;
    page->acl_write_limit = RS_APU_RELEASE_ACL_WRITE_LIMIT;
    __asm__ volatile("fence rw, rw" ::: "memory");
}

static bool rs_apu_release_handoff(void) {
    rs_resource_status_t before;
    rs_resource_status_t after;

    if ((rs_resource_get_status(RS_RESOURCE_APU, &before) != RS_OK) ||
        (rs_resource_set_owner(RS_RESOURCE_APU, RS_RESOURCE_OWNER_HP, false) != RS_OK) ||
        (rs_resource_get_status(RS_RESOURCE_APU, &after) != RS_OK)) {
        return false;
    }
    if ((after.owner != RS_RESOURCE_OWNER_HP) ||
        (after.handoff_count != (uint16_t)(before.handoff_count + UINT16_C(1)))) {
        return false;
    }
    for (uint32_t budget = 0U; budget < RS_APU_RELEASE_QUIESCE_BUDGET; ++budget) {
        const uint32_t owner = RS_APU_REG(RS_APU_ABI_OWNER_STATUS);

        if (((owner & UINT32_C(3)) == 1U) &&
            ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_QUIESCE)) == 0U) &&
            ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_RESET)) == 0U)) {
            printf("APU_RELEASE_HANDOFF:%u\n", (unsigned int)after.handoff_count);
            rs_apu_release_milestone("HANDOFF");
            return true;
        }
    }
    return false;
}

static bool rs_apu_release_check_page(void) {
    volatile const rs_apu_release_page_t *page =
        (volatile const rs_apu_release_page_t *)(uintptr_t)RS_APU_RELEASE_PAGE_ADDRESS;
    const uint32_t done_bit = UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE;
    const uint32_t bad_bits = (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ERROR) |
                              (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ABORTED);

    if ((page->result_magic != RS_APU_RELEASE_RESULT_MAGIC) ||
        (page->hp_steps != RS_APU_RELEASE_STEP_ALL) || (page->hp_error != 0U)) {
        return false;
    }
    if (((page->wav_status & done_bit) == 0U) || ((page->wav_status & bad_bits) != 0U) ||
        (page->wav_input_used != RS_APU_RELEASE_WAV_SIZE) ||
        (page->wav_output_bytes != RS_APU_RELEASE_PCM_BYTES) ||
        (page->wav_frames != RS_APU_RELEASE_PCM_FRAMES) ||
        (page->wav_output_crc != RS_APU_RELEASE_PCM_CRC)) {
        return false;
    }
    if (rs_apu_release_crc32((volatile const uint8_t *)(uintptr_t)RS_APU_RELEASE_PCM_ADDRESS,
                             RS_APU_RELEASE_PCM_BYTES) != RS_APU_RELEASE_PCM_CRC) {
        return false;
    }
    if (((page->kws_status & done_bit) == 0U) || ((page->kws_status & bad_bits) != 0U) ||
        (page->kws_input_used != UINT32_C(32000)) || (page->kws_frames != UINT32_C(16000)) ||
        (page->kws_class_id != RS_APU_RELEASE_KWS_CLASS) || (page->kws_hit != 1U) ||
        (page->kws_score < RS_APU_RELEASE_KWS_THRESHOLD)) {
        return false;
    }
    if ((page->acl_read_base_readback != RS_APU_RELEASE_ACL_READ_BASE) ||
        (page->acl_read_limit_readback != RS_APU_RELEASE_ACL_READ_LIMIT)) {
        return false;
    }
    if ((page->fault_count == 0U) || (page->fault_mcause != RS_APU_RELEASE_FAULT_MCAUSE) ||
        (page->fault_mtval != (RS_SOC_APB4_APU_BASE + RS_APU_ABI_READ_BASE))) {
        return false;
    }
    return true;
}

static void rs_apu_release_run(void) {
    rs_apu_info_t info;
    rs_sysctrl_hp_status_t hp_status;
    rs_hp_mailbox_message_t event;
    volatile rs_apu_release_page_t *page =
        (volatile rs_apu_release_page_t *)(uintptr_t)RS_APU_RELEASE_PAGE_ADDRESS;
    uint32_t budget;

    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, UINT8_C(1));
    }
    printf("APU_RELEASE_BOOT\n");
    rs_apu_release_milestone("BOOT");
    if ((rs_sysctrl_set_hp_release(false) != RS_OK) ||
        (rs_sysctrl_select_hp_debug(true) != RS_OK) ||
        (rs_sysctrl_get_hp_status(&hp_status) != RS_OK) || !hp_status.present ||
        !hp_status.reset_asserted) {
        rs_apu_release_fail(UINT8_C(2));
    }
    printf("APU_RELEASE_HP_HELD\n");
    rs_apu_release_milestone("HP_HELD");
    if (!rs_apu_release_wait_sdram()) {
        rs_apu_release_fail(UINT8_C(3));
    }
    printf("APU_RELEASE_SDRAM\n");
    rs_apu_release_milestone("SDRAM");
    if (!rs_apu_release_load_bundle()) {
        rs_apu_release_fail(UINT8_C(4));
    }
    printf("APU_RELEASE_BUNDLE\n");
    rs_apu_release_milestone("BUNDLE");
    if ((rs_apu_probe(&info) != RS_OK) || (info.capability0 != RS_APU_CAPABILITY0_P7_IMPLEMENTED) ||
        (info.abi_digest != RS_APU_DIGEST_P7_IMPLEMENTED)) {
        rs_apu_release_fail(UINT8_C(5));
    }
    printf("APU_RELEASE_PROBE:%08lx:%08lx\n", (unsigned long)info.capability0,
           (unsigned long)info.capability1);
    if (!rs_apu_release_quiesce()) {
        rs_apu_release_fail(UINT8_C(6));
    }
    printf("APU_RELEASE_QUIESCED\n");
    rs_apu_release_milestone("QUIESCED");
    if (!rs_apu_release_stage_assets()) {
        rs_apu_release_fail(UINT8_C(7));
    }
    printf("APU_RELEASE_STAGED\n");
    rs_apu_release_milestone("STAGED");
    if (rs_apu_set_acl(RS_APU_RELEASE_ACL_READ_BASE, RS_APU_RELEASE_ACL_READ_LIMIT,
                       RS_APU_RELEASE_ACL_WRITE_BASE, RS_APU_RELEASE_ACL_WRITE_LIMIT) != RS_OK) {
        rs_apu_release_fail(UINT8_C(8));
    }
    if (rs_apu_release_load_images() != 0U) {
        rs_apu_release_fail(UINT8_C(9));
    }
    if (!rs_apu_release_handoff()) {
        rs_apu_release_fail(UINT8_C(10));
    }
    rs_apu_release_fill_page();
    (void)rs_hp_mailbox_clear_lp_interrupt();
    if (rs_hp_mailbox_send_to_hp(&(const rs_hp_mailbox_message_t){
            .code = RS_APU_RELEASE_JOB_RUN,
            .argument = RS_APU_RELEASE_PAGE_ADDRESS,
            .sequence = RS_APU_RELEASE_MAILBOX_SEQUENCE,
        }) != RS_OK) {
        rs_apu_release_fail(UINT8_C(11));
    }
    if ((rs_sysctrl_set_hp_release(true) != RS_OK) ||
        (rs_sysctrl_get_hp_status(&hp_status) != RS_OK) || !hp_status.released) {
        rs_apu_release_fail(UINT8_C(12));
    }
    printf("APU_RELEASE_HP_RUN\n");
    rs_apu_release_milestone("HP_RUN");

    /* Wait for the HP done event; the bounded poll only exits early on a stuck
     * hart because every hardware failure path publishes its own event. */
    event.code = 0U;
    event.argument = 0U;
    event.sequence = 0U;
    for (budget = 0U; (budget < RS_APU_RELEASE_EVENT_BUDGET) && (event.sequence == 0U); ++budget) {
        (void)rs_hp_mailbox_receive_from_hp(&event);
    }
    if ((event.sequence == 0U) || (event.code != RS_APU_RELEASE_EVENT_DONE) ||
        (event.argument != 0U)) {
        rs_apu_release_fail(UINT8_C(13));
    }
    rs_apu_release_milestone("HP_EVENT");
    for (budget = 0U; budget < RS_APU_RELEASE_SETTLE_SPINS; ++budget) {
        __asm__ volatile("nop" ::: "memory");
    }
    for (budget = 0U; (budget < RS_APU_RELEASE_SETTLE_BUDGET) &&
                      (page->result_magic != RS_APU_RELEASE_RESULT_MAGIC);
         ++budget) {
    }
    if (!rs_apu_release_check_page()) {
        rs_apu_release_fail(UINT8_C(14));
    }
    printf("APU_RELEASE_WAV:%lu:%lu\n", (unsigned long)page->wav_frames,
           (unsigned long)page->wav_output_crc);
    printf("APU_RELEASE_KWS:%lu:%lu\n", (unsigned long)page->kws_class_id,
           (unsigned long)page->kws_score);
    printf("APU_RELEASE_TRAP:%lu:%lu\n", (unsigned long)page->fault_mcause,
           (unsigned long)page->fault_mtval);
    printf("APU_RELEASE_PASS\n");
    rs_apu_release_milestone("PASS");
    rs_test_finish(RS_TEST_PASSED, UINT8_C(0));
}

int main(void) {
    rs_apu_release_run();
    return 0;
}
