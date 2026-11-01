#include <limits.h>
#include <stddef.h>

#include <retrosoc/hal/ppalite.h>

static bool rs_ppalite_step_valid(uint8_t step) {
    return (step == 1U) || (step == 2U) || (step == 4U);
}

rs_status_t rs_ppalite_layout(const rs_ppalite_config_t *config, uintptr_t destination,
                              uint32_t capacity_bytes, rs_ppalite_layout_t *layout) {
    uint32_t input_width;
    uint32_t input_height;
    uint32_t output_width;
    uint32_t output_height;
    uint32_t bytes_per_pixel;
    uint64_t row_bytes;
    uint64_t stride_bytes;
    uint64_t valid_bytes;
    uint64_t transport_bytes;
    uint64_t input_words;
    uint64_t input_pixels;
    rs_ppalite_layout_t result;

    if ((config == NULL) || (layout == NULL)) {
        return RS_EINVAL;
    }
    if ((uint32_t)config->input_format > (uint32_t)RS_PPALITE_INPUT_VYUY) {
        return RS_ENOTSUP;
    }
    if (((uint32_t)config->input_format < (uint32_t)RS_PPALITE_INPUT_YUYV) &&
        (config->output_gray8 || (config->source.format != RS_DVP_FORMAT_RGB565))) {
        return RS_ENOTSUP;
    }
    if (((uint32_t)config->input_format >= (uint32_t)RS_PPALITE_INPUT_YUYV) &&
        (config->rgb_swap || (config->source.format != RS_DVP_FORMAT_YUV422))) {
        return RS_ENOTSUP;
    }
    if ((config->output_gray8 && config->output_byte_swap) || !config->source.snapshot ||
        !config->source.stream_enable || config->source.byte_swap || config->source.pixel_swap) {
        return RS_ENOTSUP;
    }
    input_width =
        config->source.crop_enable ? config->source.crop_width : config->source.frame_width;
    input_height =
        config->source.crop_enable ? config->source.crop_height : config->source.frame_height;
    if ((input_width == 0U) || (input_height == 0U) ||
        (config->source.crop_enable &&
         ((config->source.crop_width == 0U) || (config->source.crop_height == 0U) ||
          ((uint32_t)config->source.crop_x + config->source.crop_width >
           config->source.frame_width) ||
          ((uint32_t)config->source.crop_y + config->source.crop_height >
           config->source.frame_height)))) {
        return RS_EINVAL;
    }
    if (!rs_ppalite_step_valid(config->step_x) || !rs_ppalite_step_valid(config->step_y) ||
        (config->phase_x >= config->step_x) || (config->phase_y >= config->step_y) ||
        (config->phase_x >= input_width) || (config->phase_y >= input_height)) {
        return RS_EINVAL;
    }
    output_width = (input_width - config->phase_x + config->step_x - 1U) / config->step_x;
    output_height = (input_height - config->phase_y + config->step_y - 1U) / config->step_y;
    if ((output_width == 0U) || (output_height == 0U) || (output_width > UINT16_MAX) ||
        (output_height > UINT16_MAX)) {
        return RS_EINVAL;
    }
    bytes_per_pixel = config->output_gray8 ? 1U : 2U;
    row_bytes = (uint64_t)output_width * bytes_per_pixel;
    if ((row_bytes == 0U) || (row_bytes > UINT32_MAX - 3U)) {
        return RS_EINVAL;
    }
    stride_bytes = (row_bytes + UINT64_C(3)) & ~UINT64_C(3);
    valid_bytes = row_bytes * output_height;
    transport_bytes = stride_bytes * output_height;
    input_words = (((uint64_t)input_width + 1U) / 2U) * input_height;
    input_pixels = (uint64_t)input_width * input_height;
    if ((valid_bytes > UINT32_MAX) || (transport_bytes == 0U) ||
        (transport_bytes > UINT64_C(0xFFFFFFFC)) || (input_words > UINT32_MAX) ||
        (input_pixels > UINT32_MAX) || (destination == 0U) ||
        ((destination & (sizeof(uint32_t) - 1U)) != 0U) ||
        ((uint64_t)destination + transport_bytes > UINT64_C(0x100000000)) ||
        (capacity_bytes < (uint32_t)transport_bytes)) {
        return RS_EINVAL;
    }
    result.width = (uint16_t)output_width;
    result.height = (uint16_t)output_height;
    result.row_bytes = (uint32_t)row_bytes;
    result.stride_bytes = (uint32_t)stride_bytes;
    result.valid_bytes = (uint32_t)valid_bytes;
    result.transport_bytes = (uint32_t)transport_bytes;
    result.expected_words = (uint32_t)transport_bytes / sizeof(uint32_t);
    *layout = result;
    return RS_OK;
}
