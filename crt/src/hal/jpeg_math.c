#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/jpeg.h>

static bool rs_jpeg_format_valid(rs_jpeg_pixel_format_t format) {
    return (uint32_t)format <= (uint32_t)RS_JPEG_FORMAT_NV12;
}

static uint32_t rs_jpeg_minimum_stride(rs_jpeg_pixel_format_t format, uint16_t width) {
    uint32_t result = (uint32_t)width;

    if ((format == RS_JPEG_FORMAT_RGB565) || (format == RS_JPEG_FORMAT_YUYV422)) {
        result *= 2U;
    } else if (format == RS_JPEG_FORMAT_RGB888) {
        result *= 3U;
    } else if (format == RS_JPEG_FORMAT_NV12) {
        result = (result + 1U) & ~UINT32_C(1);
    } else {
        /* GRAY8 uses one byte per pixel. */
    }
    return result;
}

static bool rs_jpeg_aligned(uintptr_t address, uintptr_t alignment) {
    return (address & (alignment - 1U)) == 0U;
}

rs_status_t rs_jpeg_job_validate(const rs_jpeg_job_t *job) {
    rs_jpeg_pixel_format_t surface_format;
    uint32_t minimum_stride;

    if ((job == NULL) ||
        ((job->mode != RS_JPEG_MODE_ENCODE) && (job->mode != RS_JPEG_MODE_DECODE)) ||
        !rs_jpeg_format_valid(job->input_format) || !rs_jpeg_format_valid(job->output_format) ||
        ((uint32_t)job->sampling > (uint32_t)RS_JPEG_SAMPLING_420) || (job->width == 0U) ||
        (job->height == 0U) || (job->width > RS_JPEG_MAX_DIMENSION) ||
        (job->height > RS_JPEG_MAX_DIMENSION) || (job->table_context > 3U) ||
        (job->bitstream == (uintptr_t)0U) || (job->bitstream_size == 0U) ||
        !rs_jpeg_aligned(job->bitstream, RS_JPEG_DMA_ALIGNMENT)) {
        return RS_EINVAL;
    }
    if ((job->mode == RS_JPEG_MODE_ENCODE) && ((job->quality == 0U) || (job->quality > 100U))) {
        return RS_EINVAL;
    }
    if ((job->metadata != (uintptr_t)0U) || (job->metadata_length != 0U)) {
        return RS_EINVAL;
    }

    surface_format = (job->mode == RS_JPEG_MODE_ENCODE) ? job->input_format : job->output_format;
    minimum_stride = rs_jpeg_minimum_stride(surface_format, job->width);
    if ((job->planes[0] == (uintptr_t)0U) ||
        !rs_jpeg_aligned(job->planes[0], RS_JPEG_DMA_ALIGNMENT) ||
        (job->strides[0] < minimum_stride)) {
        return RS_EINVAL;
    }
    if (surface_format == RS_JPEG_FORMAT_NV12) {
        if ((job->planes[1] == (uintptr_t)0U) ||
            !rs_jpeg_aligned(job->planes[1], RS_JPEG_DMA_ALIGNMENT) ||
            (job->strides[1] < minimum_stride)) {
            return RS_EINVAL;
        }
    }
    if ((job->bitstream > UINT32_MAX) || (job->planes[0] > UINT32_MAX) ||
        (job->planes[1] > UINT32_MAX) || (job->planes[2] > UINT32_MAX) ||
        (job->metadata > UINT32_MAX)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_jpeg_descriptor_build(rs_jpeg_descriptor_t *descriptor, const rs_jpeg_job_t *job,
                                     uint64_t cookie, bool interrupt) {
    uint32_t control = RS_JPEG_DESCRIPTOR_OWN;
    size_t index;
    rs_status_t result;

    if (descriptor == NULL) {
        return RS_EINVAL;
    }
    result = rs_jpeg_job_validate(job);
    if (result != RS_OK) {
        return result;
    }
    if (interrupt) {
        control |= RS_JPEG_DESCRIPTOR_IOC;
    }
    if (job->mode == RS_JPEG_MODE_ENCODE) {
        control |= RS_JPEG_DESCRIPTOR_ENCODE;
    }
    if (job->auto_header) {
        control |= RS_JPEG_DESCRIPTOR_AUTO_HEADER;
    }
    if (job->strict) {
        control |= RS_JPEG_DESCRIPTOR_STRICT;
    }
    if (job->metadata_length != 0U) {
        control |= RS_JPEG_DESCRIPTOR_METADATA;
    }
    control |= (uint32_t)job->table_context << RS_JPEG_DESCRIPTOR_TABLE_SHIFT;
    control |= (uint32_t)job->input_format << RS_JPEG_DESCRIPTOR_INPUT_SHIFT;
    control |= (uint32_t)job->output_format << RS_JPEG_DESCRIPTOR_OUTPUT_SHIFT;
    control |= (uint32_t)job->sampling << RS_JPEG_DESCRIPTOR_SAMPLE_SHIFT;

    descriptor->control = control;
    descriptor->status = 0U;
    descriptor->image_size = ((uint32_t)job->height << 16U) | (uint32_t)job->width;
    descriptor->encode_config = (uint32_t)job->quality;
    descriptor->restart_interval = (uint32_t)job->restart_interval;
    descriptor->bitstream_addr = (uint32_t)job->bitstream;
    descriptor->bitstream_size = job->bitstream_size;
    descriptor->result_size = 0U;
    descriptor->plane0_addr = (uint32_t)job->planes[0];
    descriptor->plane0_stride = job->strides[0];
    descriptor->plane1_addr = (uint32_t)job->planes[1];
    descriptor->plane1_stride = job->strides[1];
    descriptor->plane2_addr = (uint32_t)job->planes[2];
    descriptor->plane2_stride = job->strides[2];
    descriptor->metadata_addr = (uint32_t)job->metadata;
    descriptor->metadata_length = job->metadata_length;
    descriptor->cookie_lo = (uint32_t)cookie;
    descriptor->cookie_hi = (uint32_t)(cookie >> 32U);
    descriptor->result_image_size = 0U;
    descriptor->result_format = 0U;
    descriptor->cycles_lo = 0U;
    descriptor->cycles_hi = 0U;
    descriptor->input_bytes = 0U;
    descriptor->output_bytes = 0U;
    for (index = 0U; index < 8U; ++index) {
        descriptor->reserved[index] = 0U;
    }
    return RS_OK;
}

rs_status_t rs_jpeg_ring_validate(const rs_jpeg_descriptor_t *ring, uint32_t entries) {
    if ((ring == NULL) || !rs_jpeg_aligned((uintptr_t)ring, RS_JPEG_DESCRIPTOR_ALIGNMENT) ||
        (entries < 2U) || (entries > RS_JPEG_RING_MAX_ENTRIES) ||
        ((entries & (entries - 1U)) != 0U)) {
        return RS_EINVAL;
    }
    return RS_OK;
}
