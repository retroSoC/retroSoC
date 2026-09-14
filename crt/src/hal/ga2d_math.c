#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>

#include "ga2d_math.h"

#define RS_GA2D_ADDRESS_LIMIT UINT64_C(0x100000000)

static bool rs_ga2d_format_known(rs_ga2d_format_t format) {
    return ((format == RS_GA2D_FORMAT_RGB565) || (format == RS_GA2D_FORMAT_RGB888) ||
            (format == RS_GA2D_FORMAT_XRGB8888) || (format == RS_GA2D_FORMAT_ARGB8888) ||
            (format == RS_GA2D_FORMAT_A8));
}

static uint32_t rs_ga2d_bytes_per_pixel(rs_ga2d_format_t format) {
    uint32_t bytes = 0U;

    switch (format) {
    case RS_GA2D_FORMAT_RGB565:
        bytes = 2U;
        break;
    case RS_GA2D_FORMAT_RGB888:
        bytes = 3U;
        break;
    case RS_GA2D_FORMAT_XRGB8888:
    case RS_GA2D_FORMAT_ARGB8888:
        bytes = 4U;
        break;
    case RS_GA2D_FORMAT_A8:
        bytes = 1U;
        break;
    default:
        break;
    }
    return bytes;
}

static uint32_t rs_ga2d_pixel_alignment(rs_ga2d_format_t format) {
    uint32_t alignment = 1U;

    switch (format) {
    case RS_GA2D_FORMAT_RGB565:
        alignment = 2U;
        break;
    case RS_GA2D_FORMAT_XRGB8888:
    case RS_GA2D_FORMAT_ARGB8888:
        alignment = 4U;
        break;
    default:
        break;
    }
    return alignment;
}

static bool rs_ga2d_color_format(rs_ga2d_format_t format) {
    return (format == RS_GA2D_FORMAT_RGB565) || (format == RS_GA2D_FORMAT_RGB888) ||
           (format == RS_GA2D_FORMAT_XRGB8888) || (format == RS_GA2D_FORMAT_ARGB8888);
}

static bool rs_ga2d_interval_in_region(uint64_t base, uint64_t end, uint32_t region_base,
                                       uint32_t region_size) {
    const uint64_t start = (uint64_t)region_base;
    const uint64_t limit = start + (uint64_t)region_size;

    return (base >= start) && (end <= limit);
}

static bool rs_ga2d_interval_mapped(uint64_t base, uint64_t end, bool write) {
    if ((RS_SOC_HAS_SRAM != 0U) &&
        rs_ga2d_interval_in_region(base, end, RS_SOC_SRAM_BASE, RS_SOC_SRAM_SIZE)) {
        return true;
    }
    if (rs_ga2d_interval_in_region(base, end, RS_SOC_SDRAM_BASE, RS_SOC_SDRAM_SIZE) ||
        rs_ga2d_interval_in_region(base, end, RS_SOC_PSRAM_BASE, RS_SOC_PSRAM_SIZE) ||
        rs_ga2d_interval_in_region(base, end, RS_SOC_OPIPSRAM_BASE, RS_SOC_OPIPSRAM_SIZE)) {
        return true;
    }
    return !write && rs_ga2d_interval_in_region(base, end, RS_SOC_XPI_BASE, RS_SOC_XPI_SIZE);
}

static bool rs_ga2d_format_advertised(uint32_t formats, uint32_t shift, rs_ga2d_format_t format) {
    const uint32_t advertised = (formats >> shift) & RS_GA2D_FORMAT_CAPABILITY_MASK;
    const uint32_t format_bit = UINT32_C(1) << (uint32_t)format;

    return (advertised & format_bit) != 0U;
}

static rs_status_t rs_ga2d_validate_surface(const rs_ga2d_surface_t *surface, uint16_t width,
                                            uint16_t height, bool write) {
    const uint32_t bytes_per_pixel = rs_ga2d_bytes_per_pixel(surface->format);
    const uint32_t alignment = rs_ga2d_pixel_alignment(surface->format);
    const uint64_t base = (uint64_t)surface->address;
    const uint64_t row_bytes = (uint64_t)width * (uint64_t)bytes_per_pixel;
    uint64_t end;

#if UINTPTR_MAX > UINT32_MAX
    if (surface->address > (uintptr_t)UINT32_MAX) {
        return RS_EINVAL;
    }
#endif
    if (((base % (uint64_t)alignment) != 0U) ||
        (((uint64_t)surface->pitch % (uint64_t)alignment) != 0U)) {
        return RS_EINVAL;
    }
    if ((uint64_t)surface->pitch < row_bytes) {
        return RS_EINVAL;
    }
    end = base + ((uint64_t)(height - 1U) * (uint64_t)surface->pitch) + row_bytes;
    if (end > RS_GA2D_ADDRESS_LIMIT) {
        return RS_EINVAL;
    }
    return rs_ga2d_interval_mapped(base, end, write) ? RS_OK : RS_EINVAL;
}

static rs_status_t rs_ga2d_validate_operation(const rs_ga2d_job_t *job,
                                              const rs_ga2d_capability_t *capability) {
    uint32_t operation_capability;

    switch (job->operation) {
    case RS_GA2D_OP_FILL:
        operation_capability = RS_GA2D_CAPABILITY_FILL;
        break;
    case RS_GA2D_OP_COPY:
        operation_capability = RS_GA2D_CAPABILITY_COPY;
        break;
    case RS_GA2D_OP_CONVERT:
    case RS_GA2D_OP_BLEND:
        return RS_ENOTSUP;
    default:
        return RS_EINVAL;
    }
    return ((capability->features & (operation_capability | RS_GA2D_CAPABILITY_PRIVATE_DMA)) ==
            (operation_capability | RS_GA2D_CAPABILITY_PRIVATE_DMA))
               ? RS_OK
               : RS_ENOTSUP;
}

static rs_status_t rs_ga2d_validate_used_format(const rs_ga2d_surface_t *surface,
                                                const rs_ga2d_capability_t *capability,
                                                uint32_t shift) {
    if (!rs_ga2d_format_known(surface->format)) {
        return RS_EINVAL;
    }
    if (!rs_ga2d_color_format(surface->format) ||
        !rs_ga2d_format_advertised(capability->formats, shift, surface->format)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

static bool rs_ga2d_intervals_overlap(const rs_ga2d_surface_t *first,
                                      const rs_ga2d_surface_t *second, uint16_t width,
                                      uint16_t height) {
    const uint64_t first_base = (uint64_t)first->address;
    const uint64_t second_base = (uint64_t)second->address;
    const uint64_t first_end = first_base + ((uint64_t)(height - 1U) * (uint64_t)first->pitch) +
                               ((uint64_t)width * (uint64_t)rs_ga2d_bytes_per_pixel(first->format));
    const uint64_t second_end =
        second_base + ((uint64_t)(height - 1U) * (uint64_t)second->pitch) +
        ((uint64_t)width * (uint64_t)rs_ga2d_bytes_per_pixel(second->format));

    return (first_base < second_end) && (second_base < first_end);
}

rs_status_t rs_ga2d_job_validate_capability(const rs_ga2d_job_t *job,
                                            const rs_ga2d_capability_t *capability) {
    rs_status_t status;

    if ((job == NULL) || (capability == NULL)) {
        return RS_EINVAL;
    }
    status = rs_ga2d_validate_operation(job, capability);
    if (status != RS_OK) {
        return status;
    }
    if ((job->width == 0U) || (job->height == 0U)) {
        return RS_EINVAL;
    }
    status = rs_ga2d_validate_used_format(&job->destination, capability,
                                          RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT);
    if (status != RS_OK) {
        return status;
    }
    if (job->operation == RS_GA2D_OP_COPY) {
        status = rs_ga2d_validate_used_format(&job->foreground, capability,
                                              RS_GA2D_FORMAT_CAPABILITY_FOREGROUND_SHIFT);
        if (status != RS_OK) {
            return status;
        }
        if (job->foreground.format != job->destination.format) {
            return RS_EINVAL;
        }
    }
    status = rs_ga2d_validate_surface(&job->destination, job->width, job->height, true);
    if (status != RS_OK) {
        return status;
    }
    if (job->operation == RS_GA2D_OP_COPY) {
        status = rs_ga2d_validate_surface(&job->foreground, job->width, job->height, false);
        if (status != RS_OK) {
            return status;
        }
        if (rs_ga2d_intervals_overlap(&job->foreground, &job->destination, job->width,
                                      job->height)) {
            return RS_EINVAL;
        }
    }
    return RS_OK;
}
