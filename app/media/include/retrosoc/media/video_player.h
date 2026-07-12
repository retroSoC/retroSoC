#ifndef RETROSOC_MEDIA_VIDEO_PLAYER_H
#define RETROSOC_MEDIA_VIDEO_PLAYER_H

#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t frame_count;
    uint32_t payload_offset;
    uint32_t frame_size;
} rs_video_info_t;

rs_status_t rs_video_parse(const void *data, size_t data_size, rs_video_info_t *info);
rs_status_t rs_video_show_spisd(uintptr_t start_address, uint32_t available_size);

#endif
