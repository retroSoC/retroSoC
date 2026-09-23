#ifndef RETROSOC_HAL_GA2D_MATH_H
#define RETROSOC_HAL_GA2D_MATH_H

#include <retrosoc/hal/ga2d.h>

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    uint8_t alpha;
} rs_ga2d_pixel_t;

typedef enum {
    RS_GA2D_PLANE_DESTINATION = 0,
    RS_GA2D_PLANE_FOREGROUND = 1,
    RS_GA2D_PLANE_BACKGROUND = 2,
    RS_GA2D_PLANE_NONE = 3,
} rs_ga2d_plane_t;

typedef enum {
    RS_GA2D_VALIDATION_CATEGORY_NONE = 0,
    RS_GA2D_VALIDATION_CATEGORY_OPERATION = 1,
    RS_GA2D_VALIDATION_CATEGORY_SIZE = 2,
    RS_GA2D_VALIDATION_CATEGORY_FORMAT = 3,
    RS_GA2D_VALIDATION_CATEGORY_ALIGNMENT = 4,
    RS_GA2D_VALIDATION_CATEGORY_PITCH = 5,
    RS_GA2D_VALIDATION_CATEGORY_OVERFLOW = 6,
    RS_GA2D_VALIDATION_CATEGORY_RANGE = 7,
    RS_GA2D_VALIDATION_CATEGORY_OVERLAP = 8,
} rs_ga2d_validation_category_t;

typedef struct {
    rs_status_t status;
    rs_ga2d_validation_category_t category;
    rs_ga2d_plane_t plane;
} rs_ga2d_validation_result_t;

rs_ga2d_validation_result_t
rs_ga2d_job_validate_capability_result(const rs_ga2d_job_t *job,
                                       const rs_ga2d_capability_t *capability);
rs_status_t rs_ga2d_job_validate_capability(const rs_ga2d_job_t *job,
                                            const rs_ga2d_capability_t *capability);
uint8_t rs_ga2d_alpha_round(uint8_t pixel_alpha, uint8_t global_alpha);
uint8_t rs_ga2d_blend_channel_round(uint8_t foreground, uint8_t background, uint8_t alpha);
rs_status_t rs_ga2d_unpack_pixel(const uint8_t *source, rs_ga2d_format_t format,
                                 rs_ga2d_pixel_t *pixel);
rs_status_t rs_ga2d_pack_pixel(uint8_t *destination, rs_ga2d_format_t format,
                               const rs_ga2d_pixel_t *pixel);
rs_status_t rs_ga2d_convert_pixel(const uint8_t *source, rs_ga2d_format_t source_format,
                                  uint8_t *destination, rs_ga2d_format_t destination_format);
rs_status_t rs_ga2d_blend_pixel(const uint8_t *foreground, rs_ga2d_format_t foreground_format,
                                const uint8_t *background, rs_ga2d_format_t background_format,
                                uint8_t *destination, rs_ga2d_format_t destination_format,
                                uint32_t color, uint8_t global_alpha);

#endif
