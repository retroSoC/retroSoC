#ifndef RETROSOC_APU_RELEASE_PAGE_H
#define RETROSOC_APU_RELEASE_PAGE_H

#include <stddef.h>
#include <stdint.h>

/* LP<->HP shared SDRAM ABI for the APU-P8 ownership evidence flow. Both the
 * LP apu_release application and the HP app/ports/hp-apu payload include this
 * single definition; the LP stages every buffer and publishes the job page
 * before releasing the HP hart. */

#define RS_APU_RELEASE_MC_ADDRESS     UINT32_C(0x3BC00000)
#define RS_APU_RELEASE_MC_CAPACITY    UINT32_C(0x00010000)
#define RS_APU_RELEASE_MODEL_ADDRESS  UINT32_C(0x3BC10000)
#define RS_APU_RELEASE_MODEL_CAPACITY UINT32_C(0x00008000)
#define RS_APU_RELEASE_WAV_ADDRESS    UINT32_C(0x3BC20000)
#define RS_APU_RELEASE_WAV_CAPACITY   UINT32_C(0x00010000)
#define RS_APU_RELEASE_PCM_ADDRESS    UINT32_C(0x3BC40000)
#define RS_APU_RELEASE_PCM_CAPACITY   UINT32_C(0x00010000)
#define RS_APU_RELEASE_KWS_ADDRESS    UINT32_C(0x3BC60000)
#define RS_APU_RELEASE_KWS_CAPACITY   UINT32_C(0x00008000)
#define RS_APU_RELEASE_PAGE_ADDRESS   UINT32_C(0x3BC80000)
#define RS_APU_RELEASE_PAGE_BYTES     UINT32_C(0x00001000)

#define RS_APU_RELEASE_ACL_READ_BASE  RS_APU_RELEASE_MC_ADDRESS
#define RS_APU_RELEASE_ACL_READ_LIMIT                                                              \
    (RS_APU_RELEASE_KWS_ADDRESS + RS_APU_RELEASE_KWS_CAPACITY - 1U)
#define RS_APU_RELEASE_ACL_WRITE_BASE RS_APU_RELEASE_PCM_ADDRESS
#define RS_APU_RELEASE_ACL_WRITE_LIMIT                                                             \
    (RS_APU_RELEASE_PCM_ADDRESS + RS_APU_RELEASE_PCM_CAPACITY - 1U)

#define RS_APU_RELEASE_PAGE_MAGIC       UINT32_C(0x4150384A)
#define RS_APU_RELEASE_PAGE_VERSION     UINT32_C(1)
#define RS_APU_RELEASE_RESULT_MAGIC     UINT32_C(0x48523031)

#define RS_APU_RELEASE_JOB_RUN          UINT32_C(1)
#define RS_APU_RELEASE_EVENT_DONE       UINT32_C(2)
#define RS_APU_RELEASE_MAILBOX_SEQUENCE UINT32_C(1)

#define RS_APU_RELEASE_STEP_MAILBOX     UINT32_C(0x0001)
#define RS_APU_RELEASE_STEP_PAGE        UINT32_C(0x0002)
#define RS_APU_RELEASE_STEP_WAV_SUBMIT  UINT32_C(0x0004)
#define RS_APU_RELEASE_STEP_WAV_DONE    UINT32_C(0x0008)
#define RS_APU_RELEASE_STEP_KWS_ARM     UINT32_C(0x0010)
#define RS_APU_RELEASE_STEP_KWS_SUBMIT  UINT32_C(0x0020)
#define RS_APU_RELEASE_STEP_KWS_DONE    UINT32_C(0x0040)
#define RS_APU_RELEASE_STEP_FAULT       UINT32_C(0x0080)
#define RS_APU_RELEASE_STEP_PUBLISH     UINT32_C(0x0100)
#define RS_APU_RELEASE_STEP_ALL         UINT32_C(0x01FF)

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t flags;
    uint32_t wav_address;
    uint32_t wav_bytes;
    uint32_t wav_crc;
    uint32_t output_address;
    uint32_t output_capacity;
    uint32_t expected_output_crc;
    uint32_t expected_output_bytes;
    uint32_t expected_frames;
    uint32_t wav_rate;
    uint32_t wav_channels;
    uint32_t wav_bits;
    uint32_t kws_address;
    uint32_t kws_bytes;
    uint32_t kws_expected_class;
    uint32_t kws_threshold;
    uint32_t kws_debounce;
    uint32_t acl_read_base;
    uint32_t acl_read_limit;
    uint32_t acl_write_base;
    uint32_t acl_write_limit;
    uint32_t reserved_job[9];
    uint32_t result_magic;
    uint32_t hp_steps;
    uint32_t wav_status;
    uint32_t wav_input_used;
    uint32_t wav_output_bytes;
    uint32_t wav_frames;
    uint32_t wav_output_crc;
    uint32_t wav_detail;
    uint32_t kws_status;
    uint32_t kws_input_used;
    uint32_t kws_frames;
    uint32_t kws_class_id;
    uint32_t kws_score;
    uint32_t kws_hit;
    uint32_t kws_timestamp_lo;
    uint32_t kws_timestamp_hi;
    uint32_t acl_read_base_readback;
    uint32_t acl_read_limit_readback;
    uint32_t fault_count;
    uint32_t fault_mcause;
    uint32_t fault_mepc;
    uint32_t fault_mtval;
    uint32_t hp_error;
    uint32_t reserved_result[8];
} rs_apu_release_page_t;

#define RS_APU_RELEASE_PAGE_ASSERT(member, expected)                                               \
    _Static_assert(offsetof(rs_apu_release_page_t, member) == (expected),                          \
                   "APU release page offset mismatch")
RS_APU_RELEASE_PAGE_ASSERT(magic, 0x00U);
RS_APU_RELEASE_PAGE_ASSERT(wav_address, 0x0CU);
RS_APU_RELEASE_PAGE_ASSERT(kws_address, 0x38U);
RS_APU_RELEASE_PAGE_ASSERT(acl_read_base, 0x4CU);
RS_APU_RELEASE_PAGE_ASSERT(result_magic, 0x80U);
RS_APU_RELEASE_PAGE_ASSERT(kws_status, 0xA0U);
RS_APU_RELEASE_PAGE_ASSERT(fault_count, 0xC8U);
RS_APU_RELEASE_PAGE_ASSERT(hp_error, 0xD8U);
#undef RS_APU_RELEASE_PAGE_ASSERT

_Static_assert(sizeof(rs_apu_release_page_t) <= RS_APU_RELEASE_PAGE_BYTES,
               "APU release page must fit one 4 KiB page");

#endif
