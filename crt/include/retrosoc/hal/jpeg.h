#ifndef RETROSOC_HAL_JPEG_H
#define RETROSOC_HAL_JPEG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/jpeg_regs.h>

typedef enum {
    RS_JPEG_MODE_ENCODE = 0,
    RS_JPEG_MODE_DECODE = 1,
} rs_jpeg_mode_t;

typedef enum {
    RS_JPEG_FORMAT_GRAY8 = 0,
    RS_JPEG_FORMAT_RGB565 = 1,
    RS_JPEG_FORMAT_RGB888 = 2,
    RS_JPEG_FORMAT_YUYV422 = 3,
    RS_JPEG_FORMAT_NV12 = 4,
} rs_jpeg_pixel_format_t;

typedef enum {
    RS_JPEG_SAMPLING_GRAY = 0,
    RS_JPEG_SAMPLING_444 = 1,
    RS_JPEG_SAMPLING_422 = 2,
    RS_JPEG_SAMPLING_420 = 3,
} rs_jpeg_sampling_t;

typedef struct {
    rs_jpeg_mode_t mode;
    rs_jpeg_pixel_format_t input_format;
    rs_jpeg_pixel_format_t output_format;
    rs_jpeg_sampling_t sampling;
    uint16_t width;
    uint16_t height;
    uint8_t quality;
    uint8_t table_context;
    uint16_t restart_interval;
    uintptr_t bitstream;
    uint32_t bitstream_size;
    uintptr_t planes[3];
    uint32_t strides[3];
    uintptr_t metadata;
    uint32_t metadata_length;
    bool auto_header;
    bool strict;
} rs_jpeg_job_t;

typedef struct {
    uint32_t control;
    uint32_t status;
    uint32_t image_size;
    uint32_t encode_config;
    uint32_t restart_interval;
    uint32_t bitstream_addr;
    uint32_t bitstream_size;
    uint32_t result_size;
    uint32_t plane0_addr;
    uint32_t plane0_stride;
    uint32_t plane1_addr;
    uint32_t plane1_stride;
    uint32_t plane2_addr;
    uint32_t plane2_stride;
    uint32_t metadata_addr;
    uint32_t metadata_length;
    uint32_t cookie_lo;
    uint32_t cookie_hi;
    uint32_t result_image_size;
    uint32_t result_format;
    uint32_t cycles_lo;
    uint32_t cycles_hi;
    uint32_t input_bytes;
    uint32_t output_bytes;
    uint32_t reserved[8];
} rs_jpeg_descriptor_t;

typedef struct {
    bool busy;
    bool ring_active;
    bool encode;
    uint32_t irq_state;
    uint32_t error_status;
    uintptr_t error_address;
    uint32_t result_size;
    uint16_t result_width;
    uint16_t result_height;
    uint64_t cycles;
    uint32_t input_bytes;
    uint32_t output_bytes;
} rs_jpeg_status_t;

_Static_assert(sizeof(rs_jpeg_descriptor_t) == RS_JPEG_DESCRIPTOR_BYTES,
               "JPEG descriptor ABI must be 128 bytes");

rs_status_t rs_jpeg_job_validate(const rs_jpeg_job_t *job);
rs_status_t rs_jpeg_descriptor_build(rs_jpeg_descriptor_t *descriptor, const rs_jpeg_job_t *job,
                                     uint64_t cookie, bool interrupt);
rs_status_t rs_jpeg_ring_validate(const rs_jpeg_descriptor_t *ring, uint32_t entries);
rs_status_t rs_jpeg_configure(const rs_jpeg_job_t *job);
rs_status_t rs_jpeg_start(void);
rs_status_t rs_jpeg_wait(rs_timeout_t timeout);
rs_status_t rs_jpeg_abort(rs_timeout_t timeout);
rs_status_t rs_jpeg_get_status(rs_jpeg_status_t *status);
rs_status_t rs_jpeg_irq_enable(uint32_t mask);
rs_status_t rs_jpeg_irq_pending(uint32_t *mask);
rs_status_t rs_jpeg_irq_clear(uint32_t mask);
rs_status_t rs_jpeg_table_write(uint8_t context, uint8_t kind, uint8_t index, uint32_t value);
rs_status_t rs_jpeg_table_commit(uint8_t context);
rs_status_t rs_jpeg_table_clear(uint8_t context);
rs_status_t rs_jpeg_ring_init(rs_jpeg_descriptor_t *ring, uint32_t entries);
rs_status_t rs_jpeg_ring_submit(uint32_t tail);

#endif
