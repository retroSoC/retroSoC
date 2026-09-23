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

static bool rs_ga2d_plane_used(rs_ga2d_operation_t operation, rs_ga2d_plane_t plane) {
    switch (operation) {
    case RS_GA2D_OP_FILL:
        return plane == RS_GA2D_PLANE_DESTINATION;
    case RS_GA2D_OP_COPY:
    case RS_GA2D_OP_CONVERT:
        return plane != RS_GA2D_PLANE_BACKGROUND;
    case RS_GA2D_OP_BLEND:
        return true;
    default:
        return false;
    }
}

static const rs_ga2d_surface_t *rs_ga2d_plane_surface(const rs_ga2d_job_t *job,
                                                      rs_ga2d_plane_t plane) {
    const rs_ga2d_surface_t *surface = &job->destination;

    if (plane == RS_GA2D_PLANE_FOREGROUND) {
        surface = &job->foreground;
    } else if (plane == RS_GA2D_PLANE_BACKGROUND) {
        surface = &job->background;
    }
    return surface;
}

static uint32_t rs_ga2d_plane_format_shift(rs_ga2d_plane_t plane) {
    uint32_t shift = RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT;

    if (plane == RS_GA2D_PLANE_FOREGROUND) {
        shift = RS_GA2D_FORMAT_CAPABILITY_FOREGROUND_SHIFT;
    } else if (plane == RS_GA2D_PLANE_BACKGROUND) {
        shift = RS_GA2D_FORMAT_CAPABILITY_BACKGROUND_SHIFT;
    }
    return shift;
}

static bool rs_ga2d_plane_allows_a8(rs_ga2d_operation_t operation, rs_ga2d_plane_t plane) {
    return (operation == RS_GA2D_OP_BLEND) && (plane == RS_GA2D_PLANE_FOREGROUND);
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

static bool rs_ga2d_surface_aligned(const rs_ga2d_surface_t *surface) {
    const uint32_t alignment = rs_ga2d_pixel_alignment(surface->format);

#if UINTPTR_MAX > UINT32_MAX
    if (surface->address > (uintptr_t)UINT32_MAX) {
        return false;
    }
#endif
    return (((uint64_t)surface->address % (uint64_t)alignment) == 0U) &&
           (((uint64_t)surface->pitch % (uint64_t)alignment) == 0U);
}

static bool rs_ga2d_surface_pitch_valid(const rs_ga2d_surface_t *surface, uint16_t width) {
    const uint64_t row_bytes = (uint64_t)width * (uint64_t)rs_ga2d_bytes_per_pixel(surface->format);

    return (uint64_t)surface->pitch >= row_bytes;
}

static uint64_t rs_ga2d_surface_end(const rs_ga2d_surface_t *surface, uint16_t width,
                                    uint16_t height) {
    const uint64_t row_bytes = (uint64_t)width * (uint64_t)rs_ga2d_bytes_per_pixel(surface->format);

    return (uint64_t)surface->address + ((uint64_t)(height - 1U) * (uint64_t)surface->pitch) +
           row_bytes;
}

static bool rs_ga2d_surface_in_range(const rs_ga2d_surface_t *surface, uint64_t end, bool write) {
    return rs_ga2d_interval_mapped((uint64_t)surface->address, end, write);
}

static bool rs_ga2d_exact_surface_match(const rs_ga2d_surface_t *first,
                                        const rs_ga2d_surface_t *second) {
    return (first->address == second->address) && (first->pitch == second->pitch) &&
           (first->format == second->format);
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
        operation_capability = RS_GA2D_CAPABILITY_CONVERT;
        break;
    case RS_GA2D_OP_BLEND:
        operation_capability = RS_GA2D_CAPABILITY_BLEND;
        break;
    default:
        return RS_EINVAL;
    }
    return ((capability->features & (operation_capability | RS_GA2D_CAPABILITY_PRIVATE_DMA)) ==
            (operation_capability | RS_GA2D_CAPABILITY_PRIVATE_DMA))
               ? RS_OK
               : RS_ENOTSUP;
}

static rs_status_t rs_ga2d_validate_used_format(const rs_ga2d_job_t *job,
                                                const rs_ga2d_capability_t *capability,
                                                rs_ga2d_plane_t plane) {
    const rs_ga2d_surface_t *surface = rs_ga2d_plane_surface(job, plane);

    if (!rs_ga2d_format_known(surface->format)) {
        return RS_EINVAL;
    }
    if (surface->format == RS_GA2D_FORMAT_A8) {
        if (!rs_ga2d_plane_allows_a8(job->operation, plane)) {
            return RS_EINVAL;
        }
        if ((capability->features & RS_GA2D_CAPABILITY_A8_MASK) == 0U) {
            return RS_ENOTSUP;
        }
    } else if (!rs_ga2d_color_format(surface->format)) {
        return RS_EINVAL;
    }
    return rs_ga2d_format_advertised(capability->formats, rs_ga2d_plane_format_shift(plane),
                                     surface->format)
               ? RS_OK
               : RS_ENOTSUP;
}

static bool rs_ga2d_intervals_overlap(uint64_t first_base, uint64_t first_end, uint64_t second_base,
                                      uint64_t second_end) {
    return (first_base < second_end) && (second_base < first_end);
}

static rs_status_t rs_ga2d_validate_overlap(const rs_ga2d_job_t *job,
                                            const rs_ga2d_capability_t *capability,
                                            uint64_t destination_end, uint64_t foreground_end,
                                            uint64_t background_end) {
    const rs_ga2d_surface_t *destination = &job->destination;
    const uint64_t destination_base = (uint64_t)destination->address;

    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_FOREGROUND) &&
        rs_ga2d_intervals_overlap(destination_base, destination_end,
                                  (uint64_t)job->foreground.address, foreground_end)) {
        return RS_EINVAL;
    }
    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_BACKGROUND) &&
        rs_ga2d_intervals_overlap(destination_base, destination_end,
                                  (uint64_t)job->background.address, background_end)) {
        if (!rs_ga2d_exact_surface_match(&job->background, destination)) {
            return RS_EINVAL;
        }
        if ((capability->features & RS_GA2D_CAPABILITY_INPLACE_BACKGROUND) == 0U) {
            return RS_ENOTSUP;
        }
    }
    return RS_OK;
}

uint8_t rs_ga2d_alpha_round(uint8_t pixel_alpha, uint8_t global_alpha) {
    const uint16_t numerator = ((uint16_t)pixel_alpha * (uint16_t)global_alpha) + UINT16_C(127);

    return (uint8_t)(numerator / UINT16_C(255));
}

uint8_t rs_ga2d_blend_channel_round(uint8_t foreground, uint8_t background, uint8_t alpha) {
    const uint32_t numerator = ((uint32_t)foreground * (uint32_t)alpha) +
                               ((uint32_t)background * (UINT32_C(255) - (uint32_t)alpha)) +
                               UINT32_C(127);

    return (uint8_t)(numerator / UINT32_C(255));
}

rs_status_t rs_ga2d_unpack_pixel(const uint8_t *source, rs_ga2d_format_t format,
                                 rs_ga2d_pixel_t *pixel) {
    uint16_t packed;

    if ((source == NULL) || (pixel == NULL) || !rs_ga2d_format_known(format)) {
        return RS_EINVAL;
    }
    switch (format) {
    case RS_GA2D_FORMAT_RGB565:
        packed = (uint16_t)source[0] | ((uint16_t)source[1] << 8U);
        pixel->red = (uint8_t)(((packed >> 11U) & UINT16_C(0x1F)) * UINT16_C(8));
        pixel->red |= (uint8_t)((packed >> 13U) & UINT16_C(0x07));
        pixel->green = (uint8_t)(((packed >> 5U) & UINT16_C(0x3F)) * UINT16_C(4));
        pixel->green |= (uint8_t)((packed >> 9U) & UINT16_C(0x03));
        pixel->blue = (uint8_t)((packed & UINT16_C(0x1F)) * UINT16_C(8));
        pixel->blue |= (uint8_t)((packed >> 2U) & UINT16_C(0x07));
        pixel->alpha = UINT8_C(0xFF);
        break;
    case RS_GA2D_FORMAT_RGB888:
        pixel->red = source[0];
        pixel->green = source[1];
        pixel->blue = source[2];
        pixel->alpha = UINT8_C(0xFF);
        break;
    case RS_GA2D_FORMAT_XRGB8888:
        pixel->blue = source[0];
        pixel->green = source[1];
        pixel->red = source[2];
        pixel->alpha = UINT8_C(0xFF);
        break;
    case RS_GA2D_FORMAT_ARGB8888:
        pixel->blue = source[0];
        pixel->green = source[1];
        pixel->red = source[2];
        pixel->alpha = source[3];
        break;
    case RS_GA2D_FORMAT_A8:
        pixel->red = UINT8_C(0);
        pixel->green = UINT8_C(0);
        pixel->blue = UINT8_C(0);
        pixel->alpha = source[0];
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_ga2d_pack_pixel(uint8_t *destination, rs_ga2d_format_t format,
                               const rs_ga2d_pixel_t *pixel) {
    uint16_t packed;

    if ((destination == NULL) || (pixel == NULL) || !rs_ga2d_color_format(format)) {
        return RS_EINVAL;
    }
    switch (format) {
    case RS_GA2D_FORMAT_RGB565:
        packed = ((uint16_t)(pixel->red >> 3U) << 11U) | ((uint16_t)(pixel->green >> 2U) << 5U) |
                 (uint16_t)(pixel->blue >> 3U);
        destination[0] = (uint8_t)packed;
        destination[1] = (uint8_t)(packed >> 8U);
        break;
    case RS_GA2D_FORMAT_RGB888:
        destination[0] = pixel->red;
        destination[1] = pixel->green;
        destination[2] = pixel->blue;
        break;
    case RS_GA2D_FORMAT_XRGB8888:
        destination[0] = pixel->blue;
        destination[1] = pixel->green;
        destination[2] = pixel->red;
        destination[3] = UINT8_C(0xFF);
        break;
    case RS_GA2D_FORMAT_ARGB8888:
        destination[0] = pixel->blue;
        destination[1] = pixel->green;
        destination[2] = pixel->red;
        destination[3] = pixel->alpha;
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_ga2d_convert_pixel(const uint8_t *source, rs_ga2d_format_t source_format,
                                  uint8_t *destination, rs_ga2d_format_t destination_format) {
    rs_ga2d_pixel_t pixel;
    rs_status_t status;

    if (!rs_ga2d_color_format(source_format) || !rs_ga2d_color_format(destination_format)) {
        return RS_EINVAL;
    }
    status = rs_ga2d_unpack_pixel(source, source_format, &pixel);
    if (status != RS_OK) {
        return status;
    }
    if (source_format != RS_GA2D_FORMAT_ARGB8888) {
        pixel.alpha = UINT8_C(0xFF);
    }
    return rs_ga2d_pack_pixel(destination, destination_format, &pixel);
}

rs_status_t rs_ga2d_blend_pixel(const uint8_t *foreground, rs_ga2d_format_t foreground_format,
                                const uint8_t *background, rs_ga2d_format_t background_format,
                                uint8_t *destination, rs_ga2d_format_t destination_format,
                                uint32_t color, uint8_t global_alpha) {
    rs_ga2d_pixel_t foreground_pixel;
    rs_ga2d_pixel_t background_pixel;
    rs_status_t status;
    uint8_t alpha;

    if ((foreground == NULL) || (background == NULL) || (destination == NULL) ||
        (!rs_ga2d_color_format(foreground_format) && (foreground_format != RS_GA2D_FORMAT_A8)) ||
        !rs_ga2d_color_format(background_format) || !rs_ga2d_color_format(destination_format)) {
        return RS_EINVAL;
    }
    status = rs_ga2d_unpack_pixel(foreground, foreground_format, &foreground_pixel);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ga2d_unpack_pixel(background, background_format, &background_pixel);
    if (status != RS_OK) {
        return status;
    }
    if (foreground_format == RS_GA2D_FORMAT_A8) {
        foreground_pixel.red = (uint8_t)(color >> 16U);
        foreground_pixel.green = (uint8_t)(color >> 8U);
        foreground_pixel.blue = (uint8_t)color;
    }
    alpha = rs_ga2d_alpha_round(foreground_pixel.alpha, global_alpha);
    foreground_pixel.red =
        rs_ga2d_blend_channel_round(foreground_pixel.red, background_pixel.red, alpha);
    foreground_pixel.green =
        rs_ga2d_blend_channel_round(foreground_pixel.green, background_pixel.green, alpha);
    foreground_pixel.blue =
        rs_ga2d_blend_channel_round(foreground_pixel.blue, background_pixel.blue, alpha);
    foreground_pixel.alpha = UINT8_C(0xFF);
    return rs_ga2d_pack_pixel(destination, destination_format, &foreground_pixel);
}

static rs_ga2d_validation_result_t rs_ga2d_validation_result(rs_status_t status,
                                                             rs_ga2d_validation_category_t category,
                                                             rs_ga2d_plane_t plane) {
    rs_ga2d_validation_result_t result;

    result.status = status;
    result.category = category;
    result.plane = plane;
    return result;
}

rs_ga2d_validation_result_t
rs_ga2d_job_validate_capability_result(const rs_ga2d_job_t *job,
                                       const rs_ga2d_capability_t *capability) {
    const rs_ga2d_surface_t *destination;
    const rs_ga2d_surface_t *foreground;
    const rs_ga2d_surface_t *background;
    uint64_t destination_end = 0U;
    uint64_t foreground_end = 0U;
    uint64_t background_end = 0U;
    rs_status_t status;

    if ((job == NULL) || (capability == NULL)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_NONE,
                                         RS_GA2D_PLANE_NONE);
    }
    status = rs_ga2d_validate_operation(job, capability);
    if (status != RS_OK) {
        return rs_ga2d_validation_result(status, RS_GA2D_VALIDATION_CATEGORY_OPERATION,
                                         RS_GA2D_PLANE_NONE);
    }
    if ((job->width == 0U) || (job->height == 0U)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_SIZE,
                                         RS_GA2D_PLANE_NONE);
    }
    destination = rs_ga2d_plane_surface(job, RS_GA2D_PLANE_DESTINATION);
    foreground = rs_ga2d_plane_surface(job, RS_GA2D_PLANE_FOREGROUND);
    background = rs_ga2d_plane_surface(job, RS_GA2D_PLANE_BACKGROUND);

    for (rs_ga2d_plane_t plane = RS_GA2D_PLANE_DESTINATION; plane <= RS_GA2D_PLANE_BACKGROUND;
         ++plane) {
        if (!rs_ga2d_plane_used(job->operation, plane)) {
            continue;
        }
        status = rs_ga2d_validate_used_format(job, capability, plane);
        if (status != RS_OK) {
            return rs_ga2d_validation_result(status, RS_GA2D_VALIDATION_CATEGORY_FORMAT, plane);
        }
    }
    if ((job->operation == RS_GA2D_OP_COPY) && (foreground->format != destination->format)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_FORMAT,
                                         RS_GA2D_PLANE_FOREGROUND);
    }

    for (rs_ga2d_plane_t plane = RS_GA2D_PLANE_DESTINATION; plane <= RS_GA2D_PLANE_BACKGROUND;
         ++plane) {
        const rs_ga2d_surface_t *surface;

        if (!rs_ga2d_plane_used(job->operation, plane)) {
            continue;
        }
        surface = rs_ga2d_plane_surface(job, plane);
        if (!rs_ga2d_surface_aligned(surface)) {
            return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_ALIGNMENT,
                                             plane);
        }
    }

    for (rs_ga2d_plane_t plane = RS_GA2D_PLANE_DESTINATION; plane <= RS_GA2D_PLANE_BACKGROUND;
         ++plane) {
        const rs_ga2d_surface_t *surface;

        if (!rs_ga2d_plane_used(job->operation, plane)) {
            continue;
        }
        surface = rs_ga2d_plane_surface(job, plane);
        if (!rs_ga2d_surface_pitch_valid(surface, job->width)) {
            return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_PITCH, plane);
        }
    }

    destination_end = rs_ga2d_surface_end(destination, job->width, job->height);
    if (destination_end > RS_GA2D_ADDRESS_LIMIT) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_OVERFLOW,
                                         RS_GA2D_PLANE_DESTINATION);
    }
    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_FOREGROUND)) {
        foreground_end = rs_ga2d_surface_end(foreground, job->width, job->height);
        if (foreground_end > RS_GA2D_ADDRESS_LIMIT) {
            return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_OVERFLOW,
                                             RS_GA2D_PLANE_FOREGROUND);
        }
    }
    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_BACKGROUND)) {
        background_end = rs_ga2d_surface_end(background, job->width, job->height);
        if (background_end > RS_GA2D_ADDRESS_LIMIT) {
            return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_OVERFLOW,
                                             RS_GA2D_PLANE_BACKGROUND);
        }
    }

    if (!rs_ga2d_surface_in_range(destination, destination_end, true)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_RANGE,
                                         RS_GA2D_PLANE_DESTINATION);
    }
    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_FOREGROUND) &&
        !rs_ga2d_surface_in_range(foreground, foreground_end, false)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_RANGE,
                                         RS_GA2D_PLANE_FOREGROUND);
    }
    if (rs_ga2d_plane_used(job->operation, RS_GA2D_PLANE_BACKGROUND) &&
        !rs_ga2d_surface_in_range(background, background_end, false)) {
        return rs_ga2d_validation_result(RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_RANGE,
                                         RS_GA2D_PLANE_BACKGROUND);
    }
    status =
        rs_ga2d_validate_overlap(job, capability, destination_end, foreground_end, background_end);
    if (status != RS_OK) {
        return rs_ga2d_validation_result(status, RS_GA2D_VALIDATION_CATEGORY_OVERLAP,
                                         RS_GA2D_PLANE_DESTINATION);
    }
    return rs_ga2d_validation_result(RS_OK, RS_GA2D_VALIDATION_CATEGORY_NONE, RS_GA2D_PLANE_NONE);
}

rs_status_t rs_ga2d_job_validate_capability(const rs_ga2d_job_t *job,
                                            const rs_ga2d_capability_t *capability) {
    const rs_ga2d_validation_result_t result =
        rs_ga2d_job_validate_capability_result(job, capability);

    return result.status;
}
