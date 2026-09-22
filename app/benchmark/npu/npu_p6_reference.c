#include "npu_p6_reference.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/npu_regs.h>

#define RS_NPU_P6_INT32_MIN (-INT32_C(2147483647) - INT32_C(1))
#define RS_NPU_P6_INT32_MAX INT32_C(2147483647)
#define RS_NPU_P6_DESCRIPTOR_WORD(index)                                                           \
    descriptors[(descriptor * RS_NPU_DESCRIPTOR_WORDS) + (index)]

static int32_t rs_npu_p6_mul_high(int32_t left, int32_t right) {
    int64_t product;
    int64_t nudge;
    int64_t adjusted;
    uint64_t magnitude;
    int32_t result;

    if ((left == RS_NPU_P6_INT32_MIN) && (right == RS_NPU_P6_INT32_MIN)) {
        return RS_NPU_P6_INT32_MAX;
    }
    product = (int64_t)left * (int64_t)right;
    nudge = product >= INT64_C(0) ? (INT64_C(1) << 30) : INT64_C(1) - (INT64_C(1) << 30);
    adjusted = product + nudge;
    magnitude = adjusted < INT64_C(0) ? UINT64_C(0) - (uint64_t)adjusted : (uint64_t)adjusted;
    result = (int32_t)(magnitude >> 31U);
    return adjusted < INT64_C(0) ? -result : result;
}

static int32_t rs_npu_p6_round_pot(int32_t value, uint32_t exponent) {
    int64_t magnitude;
    int64_t rounded;

    if (exponent == 0U) {
        return value;
    }
    magnitude = value < 0 ? -(int64_t)value : (int64_t)value;
    rounded = (magnitude + (INT64_C(1) << (exponent - 1U))) >> exponent;
    return value < 0 ? -(int32_t)rounded : (int32_t)rounded;
}

static rs_status_t rs_npu_p6_multiply(int32_t value, int32_t multiplier, int32_t shift,
                                      int32_t *result) {
    int64_t shifted = value;

    if ((result == NULL) || (multiplier < 0) || (shift < -31) || (shift > 30)) {
        return RS_EFORMAT;
    }
    if (shift > 0) {
        shifted *= INT64_C(1) << (uint32_t)shift;
        if ((shifted < RS_NPU_P6_INT32_MIN) || (shifted > RS_NPU_P6_INT32_MAX)) {
            return RS_EIO;
        }
    }
    *result = rs_npu_p6_mul_high((int32_t)shifted, multiplier);
    if (shift < 0) {
        *result = rs_npu_p6_round_pot(*result, (uint32_t)(-shift));
    }
    return RS_OK;
}

static int8_t rs_npu_p6_s8(uint32_t value) {
    return (int8_t)(uint8_t)value;
}

static uint32_t rs_npu_p6_low16(uint32_t value) {
    return value & UINT32_C(0xFFFF);
}

static uint32_t rs_npu_p6_high16(uint32_t value) {
    return value >> 16U;
}

static rs_status_t rs_npu_p6_map(const rs_npu_p6_region_t *region, uint32_t address, uint32_t bytes,
                                 uint8_t **pointer) {
    uint64_t offset;

    if ((region == NULL) || (pointer == NULL) || (region->data == NULL) ||
        (address < region->base)) {
        return RS_EINVAL;
    }
    offset = (uint64_t)address - region->base;
    if ((offset > region->bytes) || ((uint64_t)bytes > ((uint64_t)region->bytes - offset))) {
        return RS_EFORMAT;
    }
    *pointer = &region->data[(uint32_t)offset];
    return RS_OK;
}

static rs_status_t rs_npu_p6_map_const(const rs_npu_p6_const_region_t *region, uint32_t address,
                                       uint32_t bytes, const uint8_t **pointer) {
    uint64_t offset;

    if ((region == NULL) || (pointer == NULL) || (region->data == NULL) ||
        (address < region->base)) {
        return RS_EINVAL;
    }
    offset = (uint64_t)address - region->base;
    if ((offset > region->bytes) || ((uint64_t)bytes > ((uint64_t)region->bytes - offset))) {
        return RS_EFORMAT;
    }
    *pointer = &region->data[(uint32_t)offset];
    return RS_OK;
}

static rs_status_t rs_npu_p6_add(int32_t accumulator, int32_t term, int32_t *result) {
    int64_t total = (int64_t)accumulator + term;

    if ((result == NULL) || (total < RS_NPU_P6_INT32_MIN) || (total > RS_NPU_P6_INT32_MAX)) {
        return RS_EIO;
    }
    *result = (int32_t)total;
    return RS_OK;
}

static rs_status_t rs_npu_p6_params(const rs_npu_p6_memory_t *memory, uint32_t base,
                                    uint32_t channels, const uint8_t **params) {
    if (channels > (UINT32_MAX / RS_NPU_PARAM_RECORD_BYTES)) {
        return RS_EFORMAT;
    }
    return rs_npu_p6_map_const(&memory->params, base, channels * RS_NPU_PARAM_RECORD_BYTES, params);
}

static int32_t rs_npu_p6_param(const uint8_t *params, uint32_t channel, uint32_t word) {
    uint32_t offset = (channel * RS_NPU_PARAM_RECORD_BYTES) + (word * sizeof(uint32_t));
    uint32_t value = (uint32_t)params[offset] | ((uint32_t)params[offset + 1U] << 8U) |
                     ((uint32_t)params[offset + 2U] << 16U) |
                     ((uint32_t)params[offset + 3U] << 24U);

    return (int32_t)value;
}

static uint8_t rs_npu_p6_clamp(int64_t value, int8_t minimum, int8_t maximum) {
    if (value < minimum) {
        value = minimum;
    } else if (value > maximum) {
        value = maximum;
    }
    return (uint8_t)(int8_t)value;
}

static rs_status_t rs_npu_p6_dense(const uint32_t *words, const rs_npu_p6_memory_t *memory) {
    uint32_t h = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t w = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t cin = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_CHANNELS]);
    uint32_t cout = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_CHANNELS]);
    uint32_t oh = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_HW]);
    uint32_t ow = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_HW]);
    uint32_t opcode = words[RS_NPU_DESCRIPTOR_WORD_VERSION_OPCODE] & UINT32_C(0xFF);
    uint32_t kernel = words[RS_NPU_DESCRIPTOR_WORD_KERNEL_STRIDE];
    uint32_t padding = words[RS_NPU_DESCRIPTOR_WORD_PADDING];
    uint32_t kh = kernel & UINT32_C(0xFF);
    uint32_t kw = (kernel >> 8U) & UINT32_C(0xFF);
    uint32_t sh = (kernel >> 16U) & UINT32_C(0xFF);
    uint32_t sw = kernel >> 24U;
    uint32_t pad_top = padding & UINT32_C(0xFF);
    uint32_t pad_left = (padding >> 16U) & UINT32_C(0xFF);
    uint32_t input_row = words[RS_NPU_DESCRIPTOR_WORD_INPUT0_ROW_BYTES];
    uint32_t output_row = words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_ROW_BYTES];
    uint32_t full_k = opcode == RS_NPU_OPCODE_CONV2D ? kh * kw * cin : cin;
    int8_t input_zero = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_INPUT0_ZERO]);
    int8_t output_zero = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_ZERO]);
    int8_t act_min = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS]);
    int8_t act_max = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS] >> 8U);
    uint8_t *input = NULL;
    uint8_t *output = NULL;
    const uint8_t *weights = NULL;
    const uint8_t *params = NULL;
    rs_status_t status;

    if ((h == 0U) || (w == 0U) || (cin == 0U) || (cout == 0U) || (oh == 0U) || (ow == 0U) ||
        (kh == 0U) || (kw == 0U) || (sh == 0U) || (sw == 0U) || (act_min > act_max)) {
        return RS_EFORMAT;
    }

    status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BASE],
                           words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BYTES], &input);
    if (status == RS_OK) {
        status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BASE],
                               words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BYTES], &output);
    }
    if (status == RS_OK) {
        status = rs_npu_p6_map_const(&memory->weights, words[RS_NPU_DESCRIPTOR_WORD_WEIGHT_BASE],
                                     words[RS_NPU_DESCRIPTOR_WORD_WEIGHT_BYTES], &weights);
    }
    if (status == RS_OK) {
        status = rs_npu_p6_params(memory, words[RS_NPU_DESCRIPTOR_WORD_PARAM_BASE], cout, &params);
    }
    if (status != RS_OK) {
        return status;
    }
    for (uint32_t oy = 0U; oy < oh; ++oy) {
        for (uint32_t ox = 0U; ox < ow; ++ox) {
            for (uint32_t channel = 0U; channel < cout; ++channel) {
                uint32_t group = channel / UINT32_C(8);
                uint32_t lane = channel % UINT32_C(8);
                int32_t accumulator = rs_npu_p6_param(params, channel, 0U);

                for (uint32_t k = 0U; k < full_k; ++k) {
                    uint32_t ci = k % cin;
                    uint32_t kernel_index = k / cin;
                    int32_t iy = (int32_t)(oy * sh + (kernel_index / kw)) - (int32_t)pad_top;
                    int32_t ix = (int32_t)(ox * sw + (kernel_index % kw)) - (int32_t)pad_left;
                    int32_t activation = 0;
                    int32_t weight =
                        (int8_t)weights[(group * full_k * UINT32_C(8)) + (k * UINT32_C(8)) + lane];

                    if ((iy >= 0) && (iy < (int32_t)h) && (ix >= 0) && (ix < (int32_t)w)) {
                        activation =
                            (int8_t)input[((uint32_t)iy * input_row) + ((uint32_t)ix * cin) + ci] -
                            input_zero;
                    }
                    status = rs_npu_p6_add(accumulator, activation * weight, &accumulator);
                    if (status != RS_OK) {
                        return status;
                    }
                }
                status = rs_npu_p6_multiply(accumulator, rs_npu_p6_param(params, channel, 1U),
                                            rs_npu_p6_param(params, channel, 2U), &accumulator);
                if (status != RS_OK) {
                    return status;
                }
                output[(oy * output_row) + (ox * cout) + channel] =
                    rs_npu_p6_clamp((int64_t)accumulator + output_zero, act_min, act_max);
            }
        }
    }
    return RS_OK;
}

static rs_status_t rs_npu_p6_depthwise(const uint32_t *words, const rs_npu_p6_memory_t *memory) {
    uint32_t h = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t w = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t channels = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_CHANNELS]);
    uint32_t oh = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_HW]);
    uint32_t ow = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_HW]);
    uint32_t kernel = words[RS_NPU_DESCRIPTOR_WORD_KERNEL_STRIDE];
    uint32_t padding = words[RS_NPU_DESCRIPTOR_WORD_PADDING];
    uint32_t sh = (kernel >> 16U) & UINT32_C(0xFF);
    uint32_t sw = kernel >> 24U;
    uint32_t pad_top = padding & UINT32_C(0xFF);
    uint32_t pad_left = (padding >> 16U) & UINT32_C(0xFF);
    uint32_t input_row = words[RS_NPU_DESCRIPTOR_WORD_INPUT0_ROW_BYTES];
    uint32_t output_row = words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_ROW_BYTES];
    int8_t input_zero = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_INPUT0_ZERO]);
    int8_t output_zero = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_ZERO]);
    int8_t act_min = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS]);
    int8_t act_max = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS] >> 8U);
    uint8_t *input = NULL;
    uint8_t *output = NULL;
    const uint8_t *weights = NULL;
    const uint8_t *params = NULL;
    rs_status_t status;

    if ((h == 0U) || (w == 0U) || (channels == 0U) || (oh == 0U) || (ow == 0U) || (sh == 0U) ||
        (sw == 0U) || (act_min > act_max)) {
        return RS_EFORMAT;
    }

    status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BASE],
                           words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BYTES], &input);
    if (status == RS_OK) {
        status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BASE],
                               words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BYTES], &output);
    }
    if (status == RS_OK) {
        status = rs_npu_p6_map_const(&memory->weights, words[RS_NPU_DESCRIPTOR_WORD_WEIGHT_BASE],
                                     words[RS_NPU_DESCRIPTOR_WORD_WEIGHT_BYTES], &weights);
    }
    if (status == RS_OK) {
        status =
            rs_npu_p6_params(memory, words[RS_NPU_DESCRIPTOR_WORD_PARAM_BASE], channels, &params);
    }
    if (status != RS_OK) {
        return status;
    }
    for (uint32_t oy = 0U; oy < oh; ++oy) {
        for (uint32_t ox = 0U; ox < ow; ++ox) {
            for (uint32_t channel = 0U; channel < channels; ++channel) {
                uint32_t group = channel / UINT32_C(8);
                uint32_t lane = channel % UINT32_C(8);
                int32_t accumulator = rs_npu_p6_param(params, channel, 0U);

                for (uint32_t k = 0U; k < UINT32_C(9); ++k) {
                    int32_t iy = (int32_t)(oy * sh + (k / UINT32_C(3))) - (int32_t)pad_top;
                    int32_t ix = (int32_t)(ox * sw + (k % UINT32_C(3))) - (int32_t)pad_left;
                    int32_t activation = 0;
                    int32_t weight =
                        (int8_t)weights[(group * UINT32_C(72)) + (k * UINT32_C(8)) + lane];

                    if ((iy >= 0) && (iy < (int32_t)h) && (ix >= 0) && (ix < (int32_t)w)) {
                        activation = (int8_t)input[((uint32_t)iy * input_row) +
                                                   ((uint32_t)ix * channels) + channel] -
                                     input_zero;
                    }
                    status = rs_npu_p6_add(accumulator, activation * weight, &accumulator);
                    if (status != RS_OK) {
                        return status;
                    }
                }
                status = rs_npu_p6_multiply(accumulator, rs_npu_p6_param(params, channel, 1U),
                                            rs_npu_p6_param(params, channel, 2U), &accumulator);
                if (status != RS_OK) {
                    return status;
                }
                output[(oy * output_row) + (ox * channels) + channel] =
                    rs_npu_p6_clamp((int64_t)accumulator + output_zero, act_min, act_max);
            }
        }
    }
    return RS_OK;
}

static rs_status_t rs_npu_p6_global_average(const uint32_t *words,
                                            const rs_npu_p6_memory_t *memory) {
    uint32_t h = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t w = rs_npu_p6_high16(words[RS_NPU_DESCRIPTOR_WORD_INPUT_HW]);
    uint32_t channels = rs_npu_p6_low16(words[RS_NPU_DESCRIPTOR_WORD_CHANNELS]);
    uint32_t input_row = words[RS_NPU_DESCRIPTOR_WORD_INPUT0_ROW_BYTES];
    uint32_t count = h * w;
    int8_t act_min = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS]);
    int8_t act_max = rs_npu_p6_s8(words[RS_NPU_DESCRIPTOR_WORD_ACTIVATION_BOUNDS] >> 8U);
    uint8_t *input = NULL;
    uint8_t *output = NULL;
    rs_status_t status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BASE],
                                       words[RS_NPU_DESCRIPTOR_WORD_INPUT0_BYTES], &input);

    if ((h == 0U) || (w == 0U) || (channels == 0U) || (act_min > act_max)) {
        return RS_EFORMAT;
    }

    if (status == RS_OK) {
        status = rs_npu_p6_map(&memory->arena, words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BASE],
                               words[RS_NPU_DESCRIPTOR_WORD_OUTPUT_BYTES], &output);
    }
    if (status != RS_OK) {
        return status;
    }
    for (uint32_t channel = 0U; channel < channels; ++channel) {
        int32_t total = 0;
        for (uint32_t y = 0U; y < h; ++y) {
            for (uint32_t x = 0U; x < w; ++x) {
                status = rs_npu_p6_add(
                    total, (int8_t)input[(y * input_row) + (x * channels) + channel], &total);
                if (status != RS_OK) {
                    return status;
                }
            }
        }
        {
            uint32_t magnitude = total < 0 ? UINT32_C(0) - (uint32_t)total : (uint32_t)total;
            int32_t rounded = (int32_t)((magnitude + (count / 2U)) / count);

            output[channel] = rs_npu_p6_clamp(total < 0 ? -rounded : rounded, act_min, act_max);
        }
    }
    return RS_OK;
}

rs_status_t rs_npu_p6_reference_execute(const uint32_t *descriptors, uint32_t descriptor_count,
                                        const rs_npu_p6_memory_t *memory) {
    rs_status_t status = RS_OK;

    if ((descriptors == NULL) || (memory == NULL) || (descriptor_count == 0U) ||
        (descriptor_count > (UINT32_MAX / RS_NPU_DESCRIPTOR_WORDS))) {
        return RS_EINVAL;
    }
    for (uint32_t descriptor = 0U; descriptor < descriptor_count; ++descriptor) {
        const uint32_t *words = &RS_NPU_P6_DESCRIPTOR_WORD(0U);
        uint32_t version = words[RS_NPU_DESCRIPTOR_WORD_VERSION_OPCODE] >> 16U;
        uint32_t opcode = words[RS_NPU_DESCRIPTOR_WORD_VERSION_OPCODE] & UINT32_C(0xFF);

        if (version != RS_NPU_DESCRIPTOR_ABI_VERSION) {
            return RS_EFORMAT;
        }
        if ((opcode == RS_NPU_OPCODE_CONV2D) || (opcode == RS_NPU_OPCODE_FULLY_CONNECTED)) {
            status = rs_npu_p6_dense(words, memory);
        } else if (opcode == RS_NPU_OPCODE_DEPTHWISE3X3) {
            status = rs_npu_p6_depthwise(words, memory);
        } else if (opcode == RS_NPU_OPCODE_GLOBAL_AVERAGE_POOL) {
            status = rs_npu_p6_global_average(words, memory);
        } else {
            status = RS_ENOTSUP;
        }
        if (status != RS_OK) {
            return status;
        }
    }
    return RS_OK;
}
