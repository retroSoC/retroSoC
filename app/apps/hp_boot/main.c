#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/ga2d.h>
#include <retrosoc/hal/hp_mailbox.h>
#include <retrosoc/hal/resource.h>
#include <retrosoc/hal/sdram.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

#include "hp_boot_bundle.h"

#define RS_HP_BOOT_HEADER_SIZE             UINT32_C(128)
#define RS_HP_BOOT_READY_EVENT             UINT32_C(1)
#define RS_HP_BOOT_READY_ARG               UINT32_C(0x4C4E5801)
#define RS_HP_BOOT_GA2D_START_COMMAND      UINT32_C(0x47413250)
#define RS_HP_BOOT_GA2D_START_ARG          UINT32_C(0x47413244)
#define RS_HP_BOOT_GA2D_PASS_EVENT         UINT32_C(2)
#define RS_HP_BOOT_GA2D_FAIL_EVENT         UINT32_C(3)
#define RS_HP_BOOT_GA2D_CACHE_EVENT        UINT32_C(4)
#define RS_HP_BOOT_GA2D_PASS_ARG           UINT32_C(0x47413244)
#define RS_HP_BOOT_GA2D_CACHE_ARG          UINT32_C(0x43424F4B)
#define RS_HP_BOOT_MAILBOX_READY_SEQUENCE  UINT32_C(1)
#define RS_HP_BOOT_MAILBOX_RESULT_SEQUENCE UINT32_C(2)
#define RS_HP_BOOT_MAILBOX_CACHE_SEQUENCE  UINT32_C(3)
#define RS_HP_BOOT_READBACK_STRIDE_BYTES   UINT32_C(1024)
#define RS_HP_BOOT_DMA_TIMEOUT             (RS_TIMEOUT_DEFAULT * UINT32_C(64))
#define RS_HP_BOOT_EVENT_TIMEOUT           (RS_TIMEOUT_DEFAULT * UINT32_C(64))

static rs_dma_tcd_t s_hp_boot_tcd __attribute__((aligned(64)));
static bool s_hp_boot_ga2d_owned_by_hp;

_Static_assert(sizeof(rs_hp_boot_header_t) == RS_HP_BOOT_HEADER_SIZE,
               "HP boot bundle header ABI mismatch");

static void rs_hp_boot_read_header(rs_hp_boot_header_t *header) {
    volatile const uint8_t *source =
        (volatile const uint8_t *)(uintptr_t)(RS_SOC_FLASH_BASE + RS_HP_BOOT_BUNDLE_OFFSET);
    uint8_t *destination = (uint8_t *)header;

    for (uint32_t index = 0U; index < sizeof(*header); ++index) {
        destination[index] = source[index];
    }
}

static bool rs_hp_boot_copy_entry(const rs_hp_boot_entry_t *entry) {
    volatile const uint32_t *source_words =
        (volatile const uint32_t *)(uintptr_t)(RS_SOC_FLASH_BASE + entry->flash_offset);
    volatile uint32_t *destination_words = (volatile uint32_t *)(uintptr_t)entry->load_address;
    uint32_t word_count = entry->size / (uint32_t)sizeof(uint32_t);
    uint32_t crc = UINT32_C(0xFFFFFFFF);
    bool verify_full = entry->size <= RS_HP_BOOT_READBACK_STRIDE_BYTES;

    for (uint32_t index = 0U; index < word_count; ++index) {
        uint32_t value = source_words[index];
        destination_words[index] = value;
        if (verify_full && (destination_words[index] != value)) {
            return false;
        }
        crc = rs_hp_boot_crc32_byte(crc, (uint8_t)value);
        crc = rs_hp_boot_crc32_byte(crc, (uint8_t)(value >> 8U));
        crc = rs_hp_boot_crc32_byte(crc, (uint8_t)(value >> 16U));
        crc = rs_hp_boot_crc32_byte(crc, (uint8_t)(value >> 24U));
    }
    for (uint32_t index = word_count * (uint32_t)sizeof(uint32_t); index < entry->size; ++index) {
        volatile const uint8_t *source_bytes =
            (volatile const uint8_t *)(uintptr_t)(RS_SOC_FLASH_BASE + entry->flash_offset);
        volatile uint8_t *destination_bytes = (volatile uint8_t *)(uintptr_t)entry->load_address;
        uint8_t value = source_bytes[index];
        destination_bytes[index] = value;
        if (verify_full && (destination_bytes[index] != value)) {
            return false;
        }
        crc = rs_hp_boot_crc32_byte(crc, value);
    }
    return (~crc) == entry->crc32;
}

static bool rs_hp_boot_dma_copy_entry(const rs_hp_boot_entry_t *entry) {
    rs_status_t status;

    s_hp_boot_tcd.next_ptr = UINT32_C(0);
    s_hp_boot_tcd.source = RS_SOC_FLASH_BASE + entry->flash_offset;
    s_hp_boot_tcd.destination = entry->load_address;
    s_hp_boot_tcd.byte_count = entry->size;
    s_hp_boot_tcd.source_stride = 0;
    s_hp_boot_tcd.destination_stride = 0;
    s_hp_boot_tcd.y_count = UINT16_C(1);
    s_hp_boot_tcd.reserved = UINT16_C(0);
    s_hp_boot_tcd.control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                            RS_DMA_TCD_CRC_ENABLE | RS_DMA_TCD_CRC_FINAL |
                            (UINT32_C(3) << RS_DMA_TCD_PRIORITY_SHIFT) |
                            (UINT32_C(16) << RS_DMA_TCD_BURST_SHIFT);
    s_hp_boot_tcd.control |= ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT) |
                             ((uint32_t)RS_DMA_REQUEST_SOFTWARE << RS_DMA_TCD_REQUEST_SHIFT);
    s_hp_boot_tcd.crc_expected = entry->crc32;
    s_hp_boot_tcd.crc_seed = UINT32_C(0xFFFFFFFF);
    s_hp_boot_tcd.crc_result = UINT32_C(0);
    s_hp_boot_tcd.status = UINT32_C(0);
    s_hp_boot_tcd.bytes_done = UINT32_C(0);
    s_hp_boot_tcd.error_status = UINT32_C(0);
    s_hp_boot_tcd.reserved_tail = UINT32_C(0);
    s_hp_boot_tcd.reserved_tail2 = UINT32_C(0);
    __asm__ volatile("fence rw, rw" ::: "memory");
    status = rs_dma_submit_tcd(RS_DMA_CHANNEL_HP, &s_hp_boot_tcd, RS_HP_BOOT_DMA_TIMEOUT);
    __asm__ volatile("fence rw, rw" ::: "memory");
    return (status == RS_OK) && (s_hp_boot_tcd.bytes_done == entry->size) &&
           (s_hp_boot_tcd.crc_result == entry->crc32);
}

static bool rs_hp_boot_wait_sdram(void) {
    rs_sdram_status_t status;

    for (uint32_t timeout = 0U; timeout < RS_TIMEOUT_DEFAULT; ++timeout) {
        if ((rs_sdram_get_status(&status) == RS_OK) && status.ready && !status.init_busy &&
            !status.error) {
            return true;
        }
    }
    return false;
}

static bool rs_hp_boot_ga2d_idle(rs_resource_owner_t expected_owner) {
    rs_ga2d_capability_t capability;
    rs_ga2d_status_t ga2d_status;
    rs_resource_status_t resource_status;

    return (rs_ga2d_get_capability(&capability) == RS_OK) &&
           (capability.features == RS_GA2D_CAPABILITY_P5) &&
           (capability.limits == RS_GA2D_LIMITS_P5) &&
           (capability.formats == RS_GA2D_FORMAT_CAPABILITY_P5) &&
           (rs_ga2d_get_status(&ga2d_status) == RS_OK) && !ga2d_status.busy &&
           !ga2d_status.draining && !ga2d_status.error && !ga2d_status.aborted &&
           !ga2d_status.recovery_required && ga2d_status.data_ready &&
           (rs_resource_get_status(RS_RESOURCE_GA2D, &resource_status) == RS_OK) &&
           (resource_status.owner == expected_owner) && resource_status.idle &&
           !resource_status.fault && !resource_status.blocked && !resource_status.quiesced &&
           !resource_status.in_reset;
}

static bool rs_hp_boot_wait_ga2d_idle(rs_resource_owner_t expected_owner) {
    for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
        if (rs_hp_boot_ga2d_idle(expected_owner)) {
            return true;
        }
    }
    return false;
}

static bool rs_hp_boot_wait_message(uint32_t code, uint32_t argument, uint32_t sequence) {
    rs_hp_mailbox_message_t message;

    for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
        uint32_t status;
        if (rs_hp_mailbox_receive_from_hp(&message) != RS_OK) {
            return false;
        }
        status = rs_hp_boot_message_status(message.code, message.argument, message.sequence, code,
                                           argument, sequence);
        if (status == 2U) {
            printf("HP_PAYLOAD_FAILED:%u\n", (unsigned int)message.argument);
            return false;
        }
        if (status == 1U) {
            return true;
        }
    }
    return false;
}

static bool rs_hp_boot_wait_cache_request(void) {
    rs_resource_cache_status_t cache_status;

    for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
        if (rs_resource_get_cache_status(&cache_status) != RS_OK) {
            return false;
        }
        if (cache_status.request && !cache_status.clean) {
            return true;
        }
    }
    return false;
}

static bool rs_hp_boot_wait_hp_held(void) {
    rs_sysctrl_hp_status_t hp_status;

    for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
        if ((rs_sysctrl_get_hp_status(&hp_status) == RS_OK) && hp_status.reset_asserted &&
            !hp_status.released && !hp_status.draining && !hp_status.forced_fault &&
            rs_hp_boot_ga2d_idle(RS_RESOURCE_OWNER_HP)) {
            return true;
        }
    }
    return false;
}

static void rs_hp_boot_fail(uint8_t code) {
    if (!s_hp_boot_ga2d_owned_by_hp) {
        (void)rs_sysctrl_set_hp_release(false);
    }
    printf("HP_BOOT_FAILED:%u\n", (unsigned int)code);
    rs_test_finish(RS_TEST_FAILED, code);
}

int main(void) {
    bool cache_clean_completed = false;
    rs_hp_boot_header_t header;
    rs_sysctrl_hp_status_t hp_status;
    rs_hp_mailbox_message_t message;
    rs_status_t release_status;

    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, UINT8_C(1));
    }
    if ((rs_sysctrl_set_hp_release(false) != RS_OK) ||
        (rs_sysctrl_select_hp_debug(false) != RS_OK) ||
        (rs_sysctrl_get_hp_status(&hp_status) != RS_OK) || !hp_status.present ||
        !hp_status.reset_asserted) {
        rs_hp_boot_fail(UINT8_C(2));
    }
    if (!rs_hp_boot_wait_sdram()) {
        rs_hp_boot_fail(UINT8_C(3));
    }

    rs_hp_boot_read_header(&header);
    if (!rs_hp_boot_header_valid(&header)) {
        rs_hp_boot_fail(UINT8_C(4));
    }
    for (uint32_t index = 0U; index < header.entry_count; ++index) {
        printf("HP_BOOT_LOAD:%u:%u\n", (unsigned int)header.entries[index].type,
               (unsigned int)header.entries[index].size);
        if (!rs_hp_boot_dma_copy_entry(&header.entries[index]) &&
            !rs_hp_boot_copy_entry(&header.entries[index])) {
            rs_hp_boot_fail((uint8_t)(UINT8_C(5) + (uint8_t)index));
        }
    }

    if (rs_hp_mailbox_probe() != RS_OK) {
        rs_hp_boot_fail(UINT8_C(9));
    }
    if (header.workload == RS_HP_BOOT_WORKLOAD_SMOKE) {
        if (!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_LP) ||
            (rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_HP, false) != RS_OK)) {
            rs_hp_boot_fail(UINT8_C(9));
        }
        s_hp_boot_ga2d_owned_by_hp = true;
        if (!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_HP)) {
            rs_hp_boot_fail(UINT8_C(9));
        }
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
    if ((rs_hp_mailbox_clear_lp_interrupt() != RS_OK) ||
        (rs_sysctrl_set_hp_release(true) != RS_OK) ||
        (rs_sysctrl_get_hp_status(&hp_status) != RS_OK) || !hp_status.released) {
        rs_hp_boot_fail(UINT8_C(10));
    }
    printf("HP_BOOT_RELEASED\n");

    if (header.workload == RS_HP_BOOT_WORKLOAD_RTTHREAD) {
        if (!rs_hp_boot_wait_message(RS_HP_BOOT_READY_EVENT, RS_HP_RTTHREAD_READY_ARG, 1U)) {
            rs_hp_boot_fail(UINT8_C(18));
        }
        printf("HP_RTTHREAD_READY\n");
        message.code = RS_HP_RTTHREAD_IRQ_COMMAND;
        message.argument = RS_HP_RTTHREAD_IRQ_ARG;
        message.sequence = 1U;
        if ((rs_hp_mailbox_send_to_hp(&message) != RS_OK) ||
            !rs_hp_boot_wait_message(2U, RS_HP_RTTHREAD_READY_ARG, 2U)) {
            rs_hp_boot_fail(UINT8_C(19));
        }
        printf("HP_RTTHREAD_PASS\n");
        rs_test_finish(RS_TEST_PASSED, UINT8_C(0));
    }

    if (!rs_hp_boot_wait_message(RS_HP_BOOT_READY_EVENT, RS_HP_BOOT_READY_ARG,
                                 RS_HP_BOOT_MAILBOX_READY_SEQUENCE)) {
        rs_hp_boot_fail(UINT8_C(11));
    }
    printf("HP_LINUX_READY\n");
    if (header.workload == RS_HP_BOOT_WORKLOAD_LINUX) {
        rs_test_finish(RS_TEST_PASSED, UINT8_C(0));
    }
    message.code = RS_HP_BOOT_GA2D_START_COMMAND;
    message.argument = RS_HP_BOOT_GA2D_START_ARG;
    message.sequence = RS_HP_BOOT_MAILBOX_READY_SEQUENCE;
    if (rs_hp_mailbox_send_to_hp(&message) != RS_OK) {
        rs_hp_boot_fail(UINT8_C(12));
    }
    if (!rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_PASS_EVENT, RS_HP_BOOT_GA2D_PASS_ARG,
                                 RS_HP_BOOT_MAILBOX_RESULT_SEQUENCE)) {
        rs_hp_boot_fail(UINT8_C(13));
    }
    printf("HP_GA2D_PASS\n");
    if (!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_HP)) {
        rs_hp_boot_fail(UINT8_C(14));
    }
    printf("HP_GA2D_IDLE\n");
    release_status = rs_sysctrl_set_hp_release(false);
    if ((release_status != RS_OK) && (release_status != RS_EIO)) {
        rs_hp_boot_fail(UINT8_C(15));
    }
    printf("HP_GA2D_CACHE_REQUESTED\n");
    if (rs_hp_boot_wait_cache_request()) {
        printf("HP_GA2D_CACHE_REQUEST\n");
        if (rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_CACHE_EVENT, RS_HP_BOOT_GA2D_CACHE_ARG,
                                    RS_HP_BOOT_MAILBOX_CACHE_SEQUENCE)) {
            printf("HP_GA2D_CACHE_MESSAGE\n");
            if (rs_resource_acknowledge_cache_clean() == RS_OK) {
                printf("HP_GA2D_CACHE_ACK\n");
                if (rs_hp_boot_wait_hp_held()) {
                    printf("HP_GA2D_HELD\n");
                    cache_clean_completed = true;
                }
            }
        }
    }
    if (!cache_clean_completed) {
        rs_hp_boot_fail(UINT8_C(16));
    }
    if (rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_LP, false) != RS_OK) {
        rs_hp_boot_fail(UINT8_C(17));
    }
    s_hp_boot_ga2d_owned_by_hp = false;
    if (!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_LP)) {
        rs_hp_boot_fail(UINT8_C(17));
    }
    printf("HP_GA2D_CACHE_CLEAN\n");
    rs_test_finish(RS_TEST_PASSED, UINT8_C(0));
}
