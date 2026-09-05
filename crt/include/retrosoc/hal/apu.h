#ifndef RETROSOC_HAL_APU_H
#define RETROSOC_HAL_APU_H

#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/apu_regs.h>

typedef struct {
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability0;
    uint32_t capability1;
    uint32_t abi_digest;
} rs_apu_info_t;

typedef struct {
    uint32_t control;
    uint32_t result_status;
    uint32_t input_address;
    uint32_t input_length;
    uint32_t output_address;
    uint32_t output_capacity;
    uint32_t input_config;
    uint32_t output_config;
    uint32_t job_flags;
    uint32_t kws_config;
    uint32_t result_input_used;
    uint32_t result_output_bytes;
    uint32_t result_frames;
    uint32_t result_source_info;
    uint32_t result_cycles;
    uint32_t result_detail;
    uint32_t cookie[2];
    uint32_t start_timestamp[2];
    uint32_t finish_timestamp[2];
    uint32_t kws_result;
    uint32_t microcode_build_id;
    uint32_t reserved[8];
} rs_apu_descriptor_t;

typedef enum {
    RS_APU_WAV = 0,
    RS_APU_MP3 = 1,
    RS_APU_FLAC = 2,
} rs_apu_format_t;

typedef enum {
    RS_APU_MEMORY = 0,
    RS_APU_I2S = 1,
} rs_apu_output_t;

typedef enum {
    RS_APU_S16 = 0,
    RS_APU_S24_32 = 1,
} rs_apu_pcm_t;

typedef struct {
    rs_apu_format_t format;
    rs_apu_output_t output;
    rs_apu_pcm_t pcm;
    uint32_t input_address;
    uint32_t input_bytes;
    uint32_t output_address;
    uint32_t output_capacity;
    uint32_t expected_rate;
    uint32_t expected_channels;
    uint32_t expected_bits;
    uint32_t output_rate;
    uint32_t output_channels;
    uint32_t downmix;
    uint32_t resample;
    uint32_t strict;
    uint32_t cookie[2];
} rs_apu_job_t;

typedef struct {
    uint32_t address;
    uint32_t bytes;
    uint32_t expected_crc;
} rs_apu_image_t;

typedef struct {
    uint32_t status;
    uint32_t address;
    uint32_t detail;
} rs_apu_error_t;

typedef struct {
    uint32_t status;
    uint32_t input_used;
    uint32_t output_bytes;
    uint32_t frames;
    uint32_t source_info;
    uint32_t cycles;
    uint32_t detail;
    uint32_t cookie[2];
    uint32_t start_timestamp[2];
    uint32_t finish_timestamp[2];
    uint32_t microcode_build_id;
    rs_apu_error_t first_error;
} rs_apu_result_t;

typedef struct {
    rs_apu_descriptor_t *descriptors;
    uint32_t dma_address;
    uint32_t entries;
    uint32_t tail;
} rs_apu_ring_t;

_Static_assert(sizeof(rs_apu_descriptor_t) == RS_APU_ABI_DESCRIPTOR_BYTES,
               "APU descriptor ABI must be 128 bytes");
#define RS_APU_DESCRIPTOR_OFFSET_ASSERT(member, word)                                              \
    _Static_assert(offsetof(rs_apu_descriptor_t, member) == ((word) * sizeof(uint32_t)),           \
                   "APU descriptor member offset mismatch")
RS_APU_DESCRIPTOR_OFFSET_ASSERT(control, RS_APU_ABI_DESCRIPTOR_CONTROL);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_status, RS_APU_ABI_DESCRIPTOR_RESULT_STATUS);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(input_address, RS_APU_ABI_DESCRIPTOR_INPUT_ADDRESS);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(input_length, RS_APU_ABI_DESCRIPTOR_INPUT_LENGTH);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(output_address, RS_APU_ABI_DESCRIPTOR_OUTPUT_ADDRESS);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(output_capacity, RS_APU_ABI_DESCRIPTOR_OUTPUT_CAPACITY);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(input_config, RS_APU_ABI_DESCRIPTOR_INPUT_CONFIG);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(output_config, RS_APU_ABI_DESCRIPTOR_OUTPUT_CONFIG);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(job_flags, RS_APU_ABI_DESCRIPTOR_JOB_FLAGS);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(kws_config, RS_APU_ABI_DESCRIPTOR_KWS_CONFIG);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_input_used, RS_APU_ABI_DESCRIPTOR_RESULT_INPUT_USED);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_output_bytes, RS_APU_ABI_DESCRIPTOR_RESULT_OUTPUT_BYTES);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_frames, RS_APU_ABI_DESCRIPTOR_RESULT_FRAMES);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_source_info, RS_APU_ABI_DESCRIPTOR_RESULT_SOURCE_INFO);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_cycles, RS_APU_ABI_DESCRIPTOR_RESULT_CYCLES);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(result_detail, RS_APU_ABI_DESCRIPTOR_RESULT_DETAIL);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(cookie, RS_APU_ABI_DESCRIPTOR_COOKIE_LO);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(start_timestamp, RS_APU_ABI_DESCRIPTOR_START_TIMESTAMP_LO);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(finish_timestamp, RS_APU_ABI_DESCRIPTOR_FINISH_TIMESTAMP_LO);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(kws_result, RS_APU_ABI_DESCRIPTOR_KWS_RESULT);
RS_APU_DESCRIPTOR_OFFSET_ASSERT(microcode_build_id, RS_APU_ABI_DESCRIPTOR_MICROCODE_BUILD_ID);
#undef RS_APU_DESCRIPTOR_OFFSET_ASSERT

rs_status_t rs_apu_probe(rs_apu_info_t *info);
rs_status_t rs_apu_set_acl(uint32_t read_base, uint32_t read_limit, uint32_t write_base,
                           uint32_t write_limit);
rs_status_t rs_apu_microcode_load(const rs_apu_image_t *image, rs_timeout_t timeout);
rs_status_t rs_apu_validate_job(const rs_apu_job_t *job);
rs_status_t rs_apu_submit_direct(const rs_apu_job_t *job);
rs_status_t rs_apu_wait_direct(rs_apu_result_t *result, rs_timeout_t timeout);
rs_status_t rs_apu_decode(const rs_apu_job_t *job, rs_apu_result_t *result, rs_timeout_t timeout);
rs_status_t rs_apu_ring_configure(rs_apu_ring_t *ring, uint32_t stop_on_error,
                                  uint32_t coalesce_count, uint32_t coalesce_timeout);
rs_status_t rs_apu_ring_submit(rs_apu_ring_t *ring, const rs_apu_job_t *job, uint32_t ioc,
                               uint32_t *slot);
rs_status_t rs_apu_ring_result(const rs_apu_ring_t *ring, uint32_t slot, rs_apu_result_t *result,
                               rs_timeout_t timeout);
rs_status_t rs_apu_ring_disable(rs_timeout_t timeout);
rs_status_t rs_apu_stream_route(uint32_t tx_route, uint32_t rx_route);
rs_status_t rs_apu_abort(rs_timeout_t timeout);
rs_status_t rs_apu_soft_reset(void);
rs_status_t rs_apu_error_read(rs_apu_error_t *error);
rs_status_t rs_apu_error_clear(void);
rs_status_t rs_apu_irq_read(uint32_t *state);
rs_status_t rs_apu_irq_enable(uint32_t mask);
rs_status_t rs_apu_irq_ack(uint32_t mask);

#endif
