#include <retrosoc/core/soc.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/media/video_player.h>

#define RS_VIDEO_HEADER_SIZE 16U

static uint32_t rs_video_read_le32(const uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8U) | ((uint32_t)data[2] << 16U) |
           ((uint32_t)data[3] << 24U);
}

static rs_status_t rs_video_decode_header(const uint8_t *bytes, uint32_t available_size,
                                          rs_video_info_t *info) {
    uint32_t pixels;
    uint32_t frame_size;
    uint32_t payload_size;

    if ((bytes == NULL) || (info == NULL) || (available_size < RS_VIDEO_HEADER_SIZE)) {
        return RS_EINVAL;
    }
    *info = (rs_video_info_t){0};
    info->width = rs_video_read_le32(&bytes[0]);
    info->height = rs_video_read_le32(&bytes[4]);
    info->frame_count = rs_video_read_le32(&bytes[8]);
    if ((info->width == 0U) || (info->height == 0U) || (info->frame_count == 0U) ||
        (info->width > (UINT32_MAX / info->height))) {
        return RS_EFORMAT;
    }
    pixels = info->width * info->height;
    if (((pixels & 1U) != 0U) || (pixels > (UINT32_MAX / 2U))) {
        return RS_EFORMAT;
    }
    frame_size = pixels * 2U;
    if ((frame_size == 0U) ||
        (info->frame_count > ((UINT32_MAX - RS_VIDEO_HEADER_SIZE) / frame_size))) {
        return RS_EFORMAT;
    }
    payload_size = info->frame_count * frame_size;
    if (payload_size > (available_size - RS_VIDEO_HEADER_SIZE)) {
        return RS_EFORMAT;
    }
    info->payload_offset = RS_VIDEO_HEADER_SIZE;
    info->frame_size = frame_size;
    return RS_OK;
}

rs_status_t rs_video_parse(const void *data, size_t data_size, rs_video_info_t *info) {
    if ((data_size > UINT32_MAX) || (data == NULL)) {
        return RS_EINVAL;
    }
    return rs_video_decode_header((const uint8_t *)data, (uint32_t)data_size, info);
}

rs_status_t rs_video_show_spisd(uintptr_t start_address, uint32_t available_size) {
    uint8_t header[RS_VIDEO_HEADER_SIZE];
    rs_video_info_t info;
    rs_status_t status;

    status = rs_spisd_read_bytes(header, sizeof(header), start_address);
    if (status != RS_OK) {
        return status;
    }
    status = rs_video_decode_header(header, available_size, &info);
    if (status != RS_OK) {
        return status;
    }
    if ((info.width > LCD_W) || (info.height > LCD_H) || ((start_address & 3U) != 0U) ||
        ((uintptr_t)info.payload_offset > (UINTPTR_MAX - start_address))) {
        return RS_EINVAL;
    }

    for (uint32_t frame = 0U; frame < info.frame_count; ++frame) {
        const uint32_t frame_offset = frame * info.frame_size;
        const uintptr_t payload_address = start_address + info.payload_offset;

        if ((uintptr_t)frame_offset > (UINTPTR_MAX - payload_address)) {
            return RS_EINVAL;
        }
        const uintptr_t frame_address = payload_address + frame_offset;
        lcd_fill_image(0U, 0U, (uint16_t)info.width, (uint16_t)info.height,
                       (uint32_t *)frame_address);
    }
    return RS_OK;
}
