#include <firmware.h>
#include <rs_printf.h>
#include <rs_spisd.h>
#include <rs_lcd.h>
#include <rs_dma.h>
#include <rs_qspi.h>
#include <video_player.h>


static VideoHeader_t video_header_parse(uint32_t addr) {
    VideoHeader_t videoHeader;
    spisd_mem_read((uint8_t *)&videoHeader, 1, sizeof(VideoHeader_t), addr);

    printf("================================\n");
    printf("       video bin file info      \n");
    printf("width:       %d\n", videoHeader.width);
    printf("height:      %d\n", videoHeader.height);
    printf("frame count: %d\n", videoHeader.frame_count);
    printf("================================\n");

    return videoHeader;
}


void video_show(uint32_t addr) {
    VideoHeader_t videoHeader = video_header_parse(addr);
    uint32_t* ptr = (uint32_t*)(addr + 16);
    uint32_t delta = videoHeader.width * videoHeader.height / 2;

    printf("addr: %x\n", addr);
    for(uint32_t i = 0; i < videoHeader.frame_count; ++i) {
        // lcd_addr_set(0, 0, 239, 134); // 240 - 1, 135 - 1
        // lcd_dc_set;
        // qspi0_dma_xfer(ptr, delta);
        lcd_fill_image(0, 0, videoHeader.width, videoHeader.height, ptr);
        ptr += delta;
    }
}
