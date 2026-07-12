#include <stdbool.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/media/wav_audio.h>

static uint16_t rs_wav_read_le16(const uint8_t *data) {
    return (uint16_t)((uint16_t)data[0] | ((uint16_t)data[1] << 8U));
}

static uint32_t rs_wav_read_le32(const uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8U) | ((uint32_t)data[2] << 16U) |
           ((uint32_t)data[3] << 24U);
}

static bool rs_wav_tag_matches(const uint8_t *tag, const char *expected) {
    return (tag[0] == (uint8_t)expected[0]) && (tag[1] == (uint8_t)expected[1]) &&
           (tag[2] == (uint8_t)expected[2]) && (tag[3] == (uint8_t)expected[3]);
}

static rs_status_t rs_wav_read(const rs_wav_reader_t *reader, uint32_t offset, void *buffer,
                               size_t byte_count) {
    if ((reader == NULL) || (reader->read == NULL) || (buffer == NULL) || (offset > reader->size) ||
        (byte_count > ((size_t)reader->size - offset))) {
        return RS_EFORMAT;
    }
    return reader->read(reader->context, offset, buffer, byte_count);
}

rs_status_t rs_wav_parse(const rs_wav_reader_t *reader, rs_wav_info_t *info) {
    uint8_t riff[12];
    uint8_t chunk[8];
    uint8_t format[16];
    uint32_t offset = 12U;
    uint32_t limit;
    bool format_found = false;

    if ((reader == NULL) || (info == NULL) || (reader->size < sizeof(riff))) {
        return RS_EINVAL;
    }
    *info = (rs_wav_info_t){0};
    if (rs_wav_read(reader, 0U, riff, sizeof(riff)) != RS_OK) {
        return RS_EIO;
    }
    if (!rs_wav_tag_matches(riff, "RIFF") || !rs_wav_tag_matches(&riff[8], "WAVE")) {
        return RS_EFORMAT;
    }
    if (rs_wav_read_le32(&riff[4]) > (reader->size - 8U)) {
        return RS_EFORMAT;
    }
    limit = rs_wav_read_le32(&riff[4]) + 8U;

    while (offset < limit) {
        uint32_t payload_offset;
        uint32_t payload_size;
        uint32_t padded_size;

        if ((limit - offset) < sizeof(chunk)) {
            return RS_EFORMAT;
        }
        if (rs_wav_read(reader, offset, chunk, sizeof(chunk)) != RS_OK) {
            return RS_EIO;
        }
        payload_size = rs_wav_read_le32(&chunk[4]);
        payload_offset = offset + (uint32_t)sizeof(chunk);
        if ((payload_offset > limit) || (payload_size > (limit - payload_offset))) {
            return RS_EFORMAT;
        }
        padded_size = payload_size + (payload_size & 1U);
        if ((padded_size < payload_size) || (padded_size > (limit - payload_offset))) {
            return RS_EFORMAT;
        }

        if (rs_wav_tag_matches(chunk, "fmt ")) {
            uint32_t expected_block_align;

            if ((payload_size < sizeof(format)) ||
                (rs_wav_read(reader, payload_offset, format, sizeof(format)) != RS_OK)) {
                return RS_EFORMAT;
            }
            info->audio_format = rs_wav_read_le16(&format[0]);
            info->channel_count = rs_wav_read_le16(&format[2]);
            info->sample_rate = rs_wav_read_le32(&format[4]);
            info->byte_rate = rs_wav_read_le32(&format[8]);
            info->block_align = rs_wav_read_le16(&format[12]);
            info->bits_per_sample = rs_wav_read_le16(&format[14]);
            if ((info->audio_format != 1U) || (info->channel_count == 0U) ||
                ((info->bits_per_sample != 8U) && (info->bits_per_sample != 16U) &&
                 (info->bits_per_sample != 24U) && (info->bits_per_sample != 32U))) {
                return RS_ENOTSUP;
            }
            expected_block_align = (uint32_t)info->channel_count * info->bits_per_sample / 8U;
            if ((expected_block_align == 0U) || (expected_block_align > UINT16_MAX) ||
                (info->block_align != expected_block_align) ||
                (info->sample_rate > (UINT32_MAX / info->block_align)) ||
                (info->byte_rate != (info->sample_rate * info->block_align))) {
                return RS_EFORMAT;
            }
            format_found = true;
        } else if (rs_wav_tag_matches(chunk, "data")) {
            if (!format_found || ((payload_size % info->block_align) != 0U)) {
                return RS_EFORMAT;
            }
            info->data_offset = payload_offset;
            info->data_size = payload_size;
            return RS_OK;
        }
        offset = payload_offset + padded_size;
    }
    return RS_EFORMAT;
}

typedef struct {
    uintptr_t start_address;
} rs_wav_spisd_context_t;

static rs_status_t rs_wav_spisd_read(void *context, uint32_t offset, void *buffer,
                                     size_t byte_count) {
    const rs_wav_spisd_context_t *spisd = (const rs_wav_spisd_context_t *)context;

    if ((spisd == NULL) || (offset > (UINTPTR_MAX - spisd->start_address))) {
        return RS_EINVAL;
    }
    return rs_spisd_read_bytes(buffer, byte_count, spisd->start_address + offset);
}

rs_status_t rs_wav_parse_spisd(uintptr_t start_address, uint32_t available_size,
                               rs_wav_info_t *info) {
    rs_wav_spisd_context_t context = {start_address};
    const rs_wav_reader_t reader = {rs_wav_spisd_read, &context, available_size};

    return rs_wav_parse(&reader, info);
}
