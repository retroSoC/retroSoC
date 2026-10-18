#ifndef RETROSOC_P10_FRAME_H
#define RETROSOC_P10_FRAME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

/* Application statistics only; these are not DVP or hardware counters. */
typedef struct {
    uint32_t red[32];
    uint32_t pixels;
    uint32_t checksum;
} rs_p10_statistics_t;

static inline rs_status_t rs_p10_accumulate(rs_p10_statistics_t *statistics, uint32_t word) {
    if (statistics == NULL || statistics->pixels > UINT32_MAX - 2U) {
        return RS_EINVAL;
    }
    const uint32_t first = (word >> 11U) & UINT32_C(31);
    const uint32_t second = word >> 27U;
    if (statistics->red[first] == UINT32_MAX || statistics->red[second] == UINT32_MAX ||
        (first == second && statistics->red[first] == UINT32_MAX - 1U)) {
        return RS_EINVAL;
    }
    statistics->red[first]++;
    statistics->red[second]++;
    statistics->pixels += 2U;
    statistics->checksum = (statistics->checksum ^ word) * UINT32_C(16777619);
    return RS_OK;
}

static inline rs_status_t rs_p10_chunk(uint32_t bytes, uint32_t index, uint32_t capacity_blocks,
                                       uint32_t *word_offset, uint32_t *block) {
    if (word_offset == NULL || block == NULL || bytes == 0U || bytes % 1024U != 0U ||
        index >= bytes / 1024U || capacity_blocks < 16U || bytes / 512U > capacity_blocks - 16U) {
        return RS_EINVAL;
    }
    *word_offset = index * 256U;
    *block = 16U + index * 2U;
    return RS_OK;
}

#endif
