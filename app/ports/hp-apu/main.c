#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/hal/apu_regs.h>

#include "apu_release_page.h"

#define HP_UART_BAUD_INT         UINT32_C(0x00)
#define HP_UART_BAUD_FRAC        UINT32_C(0x04)
#define HP_UART_LINE_CTRL        UINT32_C(0x08)
#define HP_UART_CTRL             UINT32_C(0x0C)
#define HP_UART_TXDATA           UINT32_C(0x10)
#define HP_UART_STATUS           UINT32_C(0x18)
#define HP_UART_FIFO_CTRL        UINT32_C(0x20)
#define HP_UART_ERROR            UINT32_C(0x30)
#define HP_UART_INTR_ENABLE      UINT32_C(0x38)
#define HP_UART_TX_FULL          UINT32_C(0x20)

#define HP_MAILBOX_LP_COMMAND    UINT32_C(0x10)
#define HP_MAILBOX_LP_ARG0       UINT32_C(0x14)
#define HP_MAILBOX_LP_SEQUENCE   UINT32_C(0x18)
#define HP_MAILBOX_HP_EVENT      UINT32_C(0x20)
#define HP_MAILBOX_HP_ARG0       UINT32_C(0x24)
#define HP_MAILBOX_HP_SEQUENCE   UINT32_C(0x28)
#define HP_MAILBOX_HP_DOORBELL   UINT32_C(0x2C)
#define HP_MAILBOX_HP_INTR_STATE UINT32_C(0x40)

#define HP_CBO_LINE_BYTES        UINT32_C(64)
#define HP_MAILBOX_BUDGET        UINT32_C(0x08000000)
#define HP_JOB_BUDGET            UINT32_C(0x08000000)
#define HP_JOB_TERMINAL                                                                            \
    ((UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE) | (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ERROR) |  \
     (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_ABORTED))

volatile uint32_t hp_fault_record[5];

static volatile uint32_t *hp_reg(uint32_t address) {
    return (volatile uint32_t *)(uintptr_t)address;
}

static void hp_uart_init(void) {
    volatile uint32_t *const uart = hp_reg(RS_SOC_APB4_UART1_BASE);

    uart[HP_UART_CTRL / 4U] = 0U;
    uart[HP_UART_FIFO_CTRL / 4U] = 3U;
    uart[HP_UART_ERROR / 4U] = 0x7FU;
    uart[HP_UART_INTR_ENABLE / 4U] = 0U;
    uart[HP_UART_BAUD_INT / 4U] = 78U;
    uart[HP_UART_BAUD_FRAC / 4U] = 32U;
    uart[HP_UART_LINE_CTRL / 4U] = 3U;
    uart[HP_UART_CTRL / 4U] = 3U;
}

static void hp_uart_putc(char value) {
    volatile uint32_t *const uart = hp_reg(RS_SOC_APB4_UART1_BASE);

    while ((uart[HP_UART_STATUS / 4U] & HP_UART_TX_FULL) != 0U) {
    }
    uart[HP_UART_TXDATA / 4U] = (uint32_t)(uint8_t)value;
}

static void hp_uart_puts(const char *text) {
    for (uint32_t index = 0U; text[index] != '\0'; ++index) {
        hp_uart_putc(text[index]);
    }
}

static void hp_uart_puthex(uint32_t value) {
    char digits[8];

    for (uint32_t index = 0U; index < 8U; ++index) {
        const uint32_t nibble = (value >> ((7U - index) * 4U)) & UINT32_C(0xF);
        digits[index] = (char)((nibble < 10U) ? ('0' + nibble) : ('A' + (nibble - 10U)));
    }
    for (uint32_t index = 0U; index < 8U; ++index) {
        hp_uart_putc(digits[index]);
    }
}

static void hp_cbo_clean(uint32_t address, uint32_t bytes) {
    uint32_t cursor = address & ~(HP_CBO_LINE_BYTES - 1U);
    const uint32_t end = address + bytes;

    while (cursor < end) {
        __asm__ volatile("cbo.clean 0(%0)" ::"r"(cursor) : "memory");
        cursor += HP_CBO_LINE_BYTES;
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
}

static void hp_cbo_inval(uint32_t address, uint32_t bytes) {
    uint32_t cursor = address & ~(HP_CBO_LINE_BYTES - 1U);
    const uint32_t end = address + bytes;

    while (cursor < end) {
        __asm__ volatile("cbo.inval 0(%0)" ::"r"(cursor) : "memory");
        cursor += HP_CBO_LINE_BYTES;
    }
    __asm__ volatile("fence rw, rw" ::: "memory");
}

static uint32_t hp_crc32_byte(uint32_t crc, uint8_t value) {
    crc ^= value;
    for (uint32_t bit = 0U; bit < 8U; ++bit) {
        const uint32_t mask = UINT32_C(0) - (crc & UINT32_C(1));
        crc = (crc >> 1U) ^ (UINT32_C(0xEDB88320) & mask);
    }
    return crc;
}

static uint32_t hp_crc32(const volatile uint8_t *data, uint32_t size) {
    uint32_t crc = UINT32_C(0xFFFFFFFF);

    for (uint32_t index = 0U; index < size; ++index) {
        crc = hp_crc32_byte(crc, data[index]);
    }
    return ~crc;
}

static bool hp_range_in(uint32_t address, uint32_t bytes, uint32_t base, uint32_t limit) {
    const uint64_t last = (uint64_t)address + (uint64_t)bytes - 1U;

    return (bytes != 0U) && (address >= base) && (last <= (uint64_t)limit);
}

static bool hp_owner_ready(void) {
    const uint32_t owner = *hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_OWNER_STATUS);

    return ((owner & UINT32_C(3)) == 1U) &&
           ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_QUIESCE)) == 0U) &&
           ((owner & (UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_RESET)) == 0U);
}

static bool hp_microcode_ready(void) {
    return hp_owner_ready() &&
           ((*hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_MC_STATUS) &
             (UINT32_C(1) << RS_APU_ABI_MC_STATUS_VALID)) != 0U) &&
           (*hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_MC_LOCK) != 0U);
}

static bool hp_wait_microcode(void) {
    for (uint32_t budget = 0U; budget < HP_JOB_BUDGET; ++budget) {
        if (hp_microcode_ready()) {
            return true;
        }
    }
    return false;
}

static bool hp_wait_kws_model(void) {
    for (uint32_t budget = 0U; budget < HP_JOB_BUDGET; ++budget) {
        if (hp_owner_ready() &&
            ((*hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_KWS_MODEL_STATUS) & UINT32_C(6)) ==
             UINT32_C(6)) &&
            (*hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_KWS_CONTROL) == 0U)) {
            return true;
        }
    }
    return false;
}

static uint32_t hp_job_wait(void) {
    for (uint32_t budget = 0U; budget < HP_JOB_BUDGET; ++budget) {
        const uint32_t status = *hp_reg(RS_SOC_APB4_APU_BASE + RS_APU_ABI_JOB_STATUS);

        if ((status & HP_JOB_TERMINAL) != 0U) {
            return status;
        }
    }
    return 0U;
}

static bool hp_mailbox_wait(uint32_t *code, uint32_t *argument) {
    volatile uint32_t *const mailbox = hp_reg(RS_SOC_APB4_HP_MAILBOX_BASE);

    for (uint32_t budget = 0U; budget < HP_MAILBOX_BUDGET; ++budget) {
        if (mailbox[HP_MAILBOX_LP_SEQUENCE / 4U] != 0U) {
            __asm__ volatile("fence r, r" ::: "memory");
            *code = mailbox[HP_MAILBOX_LP_COMMAND / 4U];
            *argument = mailbox[HP_MAILBOX_LP_ARG0 / 4U];
            mailbox[HP_MAILBOX_HP_INTR_STATE / 4U] = 1U;
            return true;
        }
    }
    return false;
}

static bool hp_submit_wav(volatile rs_apu_release_page_t *page) {
    const uint32_t apu = RS_SOC_APB4_APU_BASE;
    const uint32_t read_base = *hp_reg(apu + RS_APU_ABI_READ_BASE);
    const uint32_t read_limit = *hp_reg(apu + RS_APU_ABI_READ_LIMIT);
    const uint32_t write_base = *hp_reg(apu + RS_APU_ABI_WRITE_BASE);
    const uint32_t write_limit = *hp_reg(apu + RS_APU_ABI_WRITE_LIMIT);

    if (!hp_wait_microcode() ||
        ((*hp_reg(apu + RS_APU_ABI_JOB_STATUS) & (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_BUSY)) !=
         0U) ||
        (*hp_reg(apu + RS_APU_ABI_RING_CONTROL) != 0U) ||
        !hp_range_in(page->wav_address, page->wav_bytes, read_base, read_limit) ||
        !hp_range_in(page->output_address, page->output_capacity, write_base, write_limit)) {
        return false;
    }
    hp_cbo_clean(page->wav_address, page->wav_bytes);
    *hp_reg(apu + RS_APU_ABI_JOB_CONTROL) = 0U;
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_ADDRESS) = page->wav_address;
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_LENGTH) = page->wav_bytes;
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_ADDRESS) = page->output_address;
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_CAPACITY) = page->output_capacity;
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_CONFIG) =
        page->wav_rate | (page->wav_channels << 17U) | (page->wav_bits << 20U);
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_CONFIG) = page->wav_rate | (page->wav_channels << 17U);
    *hp_reg(apu + RS_APU_ABI_JOB_FLAGS) = 1U;
    __asm__ volatile("fence rw, rw" ::: "memory");
    page->hp_steps |= RS_APU_RELEASE_STEP_WAV_SUBMIT;
    *hp_reg(apu + RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_START_DIRECT;
    page->wav_status = hp_job_wait();
    page->wav_input_used = *hp_reg(apu + RS_APU_ABI_JOB_INPUT_USED);
    page->wav_output_bytes = *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_BYTES);
    page->wav_frames = *hp_reg(apu + RS_APU_ABI_JOB_FRAMES);
    page->wav_detail = *hp_reg(apu + RS_APU_ABI_JOB_DETAIL);
    if ((page->wav_status & (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE)) == 0U) {
        return false;
    }
    hp_cbo_inval(page->output_address, page->wav_output_bytes);
    page->wav_output_crc =
        hp_crc32((volatile const uint8_t *)(uintptr_t)page->output_address, page->wav_output_bytes);
    page->hp_steps |= RS_APU_RELEASE_STEP_WAV_DONE;
    return true;
}

static bool hp_submit_kws(volatile rs_apu_release_page_t *page) {
    const uint32_t apu = RS_SOC_APB4_APU_BASE;
    const uint32_t read_base = *hp_reg(apu + RS_APU_ABI_READ_BASE);
    const uint32_t read_limit = *hp_reg(apu + RS_APU_ABI_READ_LIMIT);
    uint32_t kws_result;

    if (!hp_wait_kws_model() ||
        !hp_range_in(page->kws_address, page->kws_bytes, read_base, read_limit)) {
        return false;
    }
    *hp_reg(apu + RS_APU_ABI_KWS_CONTROL) = UINT32_C(3);
    page->hp_steps |= RS_APU_RELEASE_STEP_KWS_ARM;
    hp_cbo_clean(page->kws_address, page->kws_bytes);
    *hp_reg(apu + RS_APU_ABI_JOB_CONTROL) = UINT32_C(1);
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_ADDRESS) = page->kws_address;
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_LENGTH) = page->kws_bytes;
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_ADDRESS) = 0U;
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_CAPACITY) = 0U;
    *hp_reg(apu + RS_APU_ABI_JOB_INPUT_CONFIG) =
        UINT32_C(16000) | (UINT32_C(1) << 17U) | (UINT32_C(16) << 20U);
    *hp_reg(apu + RS_APU_ABI_JOB_OUTPUT_CONFIG) = 0U;
    *hp_reg(apu + RS_APU_ABI_JOB_FLAGS) = 0U;
    *hp_reg(apu + RS_APU_ABI_KWS_CONFIG) = page->kws_threshold | (page->kws_debounce << 8U);
    __asm__ volatile("fence rw, rw" ::: "memory");
    page->hp_steps |= RS_APU_RELEASE_STEP_KWS_SUBMIT;
    *hp_reg(apu + RS_APU_ABI_COMMAND) = UINT32_C(1) << RS_APU_ABI_COMMAND_START_DIRECT;
    page->kws_status = hp_job_wait();
    page->kws_input_used = *hp_reg(apu + RS_APU_ABI_JOB_INPUT_USED);
    page->kws_frames = *hp_reg(apu + RS_APU_ABI_JOB_FRAMES);
    if ((page->kws_status & (UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE)) == 0U) {
        return false;
    }
    kws_result = *hp_reg(apu + RS_APU_ABI_KWS_RESULT);
    page->kws_timestamp_lo = *hp_reg(apu + RS_APU_ABI_KWS_TIMESTAMP_LO);
    page->kws_timestamp_hi = *hp_reg(apu + RS_APU_ABI_KWS_TIMESTAMP_HI);
    page->kws_class_id = kws_result & UINT32_C(0xFF);
    page->kws_score = (kws_result >> 8U) & UINT32_C(0xFF);
    page->kws_hit = (kws_result >> 16U) & UINT32_C(1);
    page->hp_steps |= RS_APU_RELEASE_STEP_KWS_DONE;
    return true;
}

static void __attribute__((noinline)) hp_probe_lp_only(volatile rs_apu_release_page_t *page) {
    const uint32_t apu = RS_SOC_APB4_APU_BASE;
    const uint32_t faults_before = hp_fault_record[3];

    page->acl_read_base_readback = *hp_reg(apu + RS_APU_ABI_READ_BASE);
    page->acl_read_limit_readback = *hp_reg(apu + RS_APU_ABI_READ_LIMIT);
    *hp_reg(apu + RS_APU_ABI_READ_BASE) = 0U;
    /* The trap handler redirects mepc here; whether the store-fault trap is
     * precise or imprecise, execution resumes at this pad exactly once and the
     * mailbox publish path stays intact. */
    __asm__ volatile(".globl hp_probe_recover\nhp_probe_recover:" ::: "memory");
    if (hp_fault_record[3] != faults_before) {
        page->fault_count = hp_fault_record[3];
        page->fault_mcause = hp_fault_record[0];
        page->fault_mepc = hp_fault_record[1];
        page->fault_mtval = hp_fault_record[2];
        page->hp_steps |= RS_APU_RELEASE_STEP_FAULT;
    }
}

static void hp_publish(volatile rs_apu_release_page_t *page, uint32_t summary) {
    volatile uint32_t *const mailbox = hp_reg(RS_SOC_APB4_HP_MAILBOX_BASE);

    page->hp_steps |= RS_APU_RELEASE_STEP_PUBLISH;
    page->result_magic = RS_APU_RELEASE_RESULT_MAGIC;
    hp_cbo_clean(RS_APU_RELEASE_PAGE_ADDRESS, RS_APU_RELEASE_PAGE_BYTES);
    mailbox[HP_MAILBOX_HP_EVENT / 4U] = RS_APU_RELEASE_EVENT_DONE;
    mailbox[HP_MAILBOX_HP_ARG0 / 4U] = summary;
    mailbox[HP_MAILBOX_HP_SEQUENCE / 4U] = RS_APU_RELEASE_MAILBOX_SEQUENCE;
    __asm__ volatile("fence w, w" ::: "memory");
    mailbox[HP_MAILBOX_HP_DOORBELL / 4U] = 1U;
}

static void hp_report(const char *marker, uint32_t value) {
    hp_uart_puts(marker);
    hp_uart_puthex(value);
    hp_uart_puts("\n");
}

void main(void) {
    volatile rs_apu_release_page_t *page =
        (volatile rs_apu_release_page_t *)(uintptr_t)RS_APU_RELEASE_PAGE_ADDRESS;
    uint32_t code = 0U;
    uint32_t argument = 0U;
    uint32_t summary = 1U;

    hp_uart_init();
    hp_uart_puts("HP_APU_BOOT\n");
    if (!hp_mailbox_wait(&code, &argument)) {
        hp_uart_puts("HP_APU_NO_MAILBOX\n");
        for (;;) {
        }
    }
    hp_cbo_inval(RS_APU_RELEASE_PAGE_ADDRESS, RS_APU_RELEASE_PAGE_BYTES);
    page->hp_steps = RS_APU_RELEASE_STEP_MAILBOX;
    if ((code != RS_APU_RELEASE_JOB_RUN) || (argument != RS_APU_RELEASE_PAGE_ADDRESS) ||
        (page->magic != RS_APU_RELEASE_PAGE_MAGIC) ||
        (page->version != RS_APU_RELEASE_PAGE_VERSION)) {
        hp_report("HP_APU_BAD_PAGE", code);
        page->hp_error = 2U;
        hp_publish(page, 2U);
        for (;;) {
        }
    }
    page->hp_steps |= RS_APU_RELEASE_STEP_PAGE;
    if (!hp_submit_wav(page)) {
        hp_report("HP_APU_WAV_STOP", page->wav_status);
        page->hp_error = 3U;
        hp_publish(page, 3U);
        for (;;) {
        }
    }
    hp_report("HP_APU_WAV_DONE", page->wav_output_bytes);
    if (!hp_submit_kws(page)) {
        hp_report("HP_APU_KWS_STOP", page->kws_status);
        page->hp_error = 4U;
        hp_publish(page, 4U);
        for (;;) {
        }
    }
    hp_report("HP_APU_KWS_DONE", page->kws_class_id);
    hp_probe_lp_only(page);
    hp_report("HP_APU_TRAP_SEEN", page->fault_mcause);
    summary = (page->hp_steps == RS_APU_RELEASE_STEP_ALL) ? 0U : 5U;
    page->hp_error = summary;
    hp_publish(page, summary);
    hp_uart_puts("HP_APU_DONE\n");
    for (;;) {
    }
}
