#ifndef RETROSOC_HAL_DVP_H
#define RETROSOC_HAL_DVP_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_DVP_INTERRUPT_FRAME_START UINT32_C(0x00000001)
#define RS_DVP_INTERRUPT_LINE_DONE   UINT32_C(0x00000002)
#define RS_DVP_INTERRUPT_FRAME_DONE  UINT32_C(0x00000004)
#define RS_DVP_INTERRUPT_OVERFLOW    UINT32_C(0x00000008)
#define RS_DVP_INTERRUPT_SYNC_ERROR  UINT32_C(0x00000010)
#define RS_DVP_INTERRUPT_CONFIG      UINT32_C(0x00000020)
#define RS_DVP_INTERRUPT_ABORTED     UINT32_C(0x00000040)
#define RS_DVP_INTERRUPT_ALL         UINT32_C(0x0000007F)

#define RS_DVP_ERROR_OVERFLOW        UINT32_C(0x00000001)
#define RS_DVP_ERROR_SYNC            UINT32_C(0x00000002)
#define RS_DVP_ERROR_SIZE            UINT32_C(0x00000004)
#define RS_DVP_ERROR_PARTIAL         UINT32_C(0x00000008)
#define RS_DVP_ERROR_CONFIG          UINT32_C(0x00000010)
#define RS_DVP_ERROR_ABORT           UINT32_C(0x00000020)

typedef enum {
    RS_DVP_FORMAT_RGB565 = 0,
    RS_DVP_FORMAT_YUV422 = 1,
} rs_dvp_format_t;

typedef struct {
    rs_dvp_format_t format;
    uint16_t frame_width;
    uint16_t frame_height;
    uint16_t crop_x;
    uint16_t crop_y;
    uint16_t crop_width;
    uint16_t crop_height;
    bool crop_enable;
    bool snapshot;
    bool stream_enable;
    bool byte_swap;
    bool pixel_swap;
    bool vsync_active_low;
    bool href_active_low;
    bool pclk_falling;
} rs_dvp_config_t;

typedef struct {
    uint32_t status;
    uint32_t frame_count;
    uint32_t line_count;
    uint32_t pixel_count;
    uint32_t word_count;
    uint32_t drop_count;
    uint32_t error_status;
    uint32_t interrupt_state;
    bool active;
} rs_dvp_status_t;

rs_status_t rs_dvp_probe(uint32_t *version, uint32_t *capability);
rs_status_t rs_dvp_configure(const rs_dvp_config_t *config);
rs_status_t rs_dvp_start(void);
rs_status_t rs_dvp_abort(void);
rs_status_t rs_dvp_flush(void);
rs_status_t rs_dvp_get_status(rs_dvp_status_t *status);
rs_status_t rs_dvp_interrupt_enable(uint32_t mask);
rs_status_t rs_dvp_interrupt_clear(uint32_t mask);
rs_status_t rs_dvp_interrupt_test(uint32_t mask);
rs_status_t rs_dvp_capture_dma(uintptr_t destination, uint32_t word_capacity, rs_timeout_t timeout);
void ip_dvp_test(void);

#endif
