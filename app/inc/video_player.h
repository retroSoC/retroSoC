#ifndef VIDEO_PLAYER_H__
#define VIDEO_PLAYER_H__

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t frame_count;
    uint32_t reserved;
} VideoHeader_t;


void video_show(uint32_t addr);

#endif