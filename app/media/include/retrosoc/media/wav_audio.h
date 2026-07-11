#ifndef RETROSOC_MEDIA_WAV_AUDIO_H
#define RETROSOC_MEDIA_WAV_AUDIO_H

#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef rs_status_t (*rs_wav_read_fn)(void *context, uint32_t offset, void *buffer,
                                      size_t byte_count);

typedef struct {
    rs_wav_read_fn read;
    void *context;
    uint32_t size;
} rs_wav_reader_t;

typedef struct {
    uint16_t audio_format;
    uint16_t channel_count;
    uint32_t sample_rate;
    uint32_t byte_rate;
    uint16_t block_align;
    uint16_t bits_per_sample;
    uint32_t data_offset;
    uint32_t data_size;
} rs_wav_info_t;

rs_status_t rs_wav_parse(const rs_wav_reader_t *reader, rs_wav_info_t *info);
rs_status_t rs_wav_parse_spisd(uintptr_t start_address, uint32_t available_size,
                               rs_wav_info_t *info);

#endif
