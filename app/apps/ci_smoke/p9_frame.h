#ifndef RS_P9_FRAME_H
#define RS_P9_FRAME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <retrosoc/core/status.h>

/* Application-only geometry; the sensor supplies two bytes per pixel. */
static inline rs_status_t rs_p9_frame_words(uint32_t width, uint32_t height, uint32_t *words) {
    if (words == NULL || width == 0U || width > UINT16_MAX || height == 0U || height > UINT16_MAX) {
        return RS_EINVAL;
    }
    const uint32_t row_words = (width + 1U) / 2U;
    if (height > (UINT32_MAX / sizeof(uint32_t)) / row_words) {
        return RS_ENOSPC;
    }
    *words = row_words * height;
    return RS_OK;
}

/* Independent firmware oracle for byte (column_byte + 3 * row) modulo 256. */
static inline uint32_t rs_p9_frame_word(uint32_t row, uint32_t column_word, bool partial) {
    const uint32_t first = (column_word * 4U + row * 3U) & UINT32_C(0xFF);
    uint32_t expected = (first << 8) | ((first + 1U) & UINT32_C(0xFF));
    if (!partial) {
        expected |=
            (((first + 2U) & UINT32_C(0xFF)) << 24) | (((first + 3U) & UINT32_C(0xFF)) << 16);
    }
    return expected;
}

#endif
