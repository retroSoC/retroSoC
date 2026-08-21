#ifndef RETROSOC_HAL_I2S_H
#define RETROSOC_HAL_I2S_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_I2S_INTERRUPT_TX_LOW      UINT32_C(0x00000001)
#define RS_I2S_INTERRUPT_RX_HIGH     UINT32_C(0x00000002)
#define RS_I2S_INTERRUPT_TX_UNDERRUN UINT32_C(0x00000004)
#define RS_I2S_INTERRUPT_RX_OVERRUN  UINT32_C(0x00000008)
#define RS_I2S_INTERRUPT_ALL         UINT32_C(0x0000000F)

#define RS_I2S_STATUS_TX_FULL        UINT32_C(0x00000001)
#define RS_I2S_STATUS_TX_EMPTY       UINT32_C(0x00000002)
#define RS_I2S_STATUS_RX_FULL        UINT32_C(0x00000004)
#define RS_I2S_STATUS_RX_EMPTY       UINT32_C(0x00000008)
#define RS_I2S_STATUS_TX_STALL       UINT32_C(0x00000010)
#define RS_I2S_STATUS_RX_STALL       UINT32_C(0x00000020)
#define RS_I2S_STATUS_ENABLE         UINT32_C(0x00000040)
#define RS_I2S_STATUS_BUSY           UINT32_C(0x00000080)
#define RS_I2S_STATUS_TX_FLUSH_BUSY  UINT32_C(0x01000000)
#define RS_I2S_STATUS_RX_FLUSH_BUSY  UINT32_C(0x02000000)

typedef enum {
    RS_I2S_PRESET_16B_48K = 0,
    RS_I2S_PRESET_16B_96K = 1,
    RS_I2S_PRESET_24B_48K = 2,
    RS_I2S_PRESET_24B_96K = 3,
} rs_i2s_preset_t;

typedef struct {
    bool loopback;
    bool stream_tx;
    bool stream_rx;
    bool clock_prog;
    rs_i2s_preset_t preset;
    bool bitmode_24;
    uint8_t sclk_div;
    uint8_t lrck_div;
    uint8_t mclk_div;
    uint8_t upbound;
    uint8_t lowbound;
} rs_i2s_config_t;

typedef struct {
    uint32_t status;
    uint8_t tx_level;
    uint8_t rx_level;
    uint32_t interrupt_state;
    bool enable;
    bool tx_full;
    bool tx_empty;
    bool rx_full;
    bool rx_empty;
} rs_i2s_status_t;

uint32_t rs_i2s_pack_stereo16(uint16_t first, uint16_t second);
void rs_i2s_unpack_stereo16(uint32_t word, uint16_t *first, uint16_t *second);
rs_status_t rs_i2s_div_from_hz(uint32_t audio_clock_hz, uint32_t sample_hz, uint32_t sample_bits,
                               uint8_t *sclk_div, uint8_t *lrck_div);
rs_status_t rs_i2s_probe(uint32_t *version, uint32_t *capability);
rs_status_t rs_i2s_configure(const rs_i2s_config_t *config);
rs_status_t rs_i2s_enable(bool tx, bool rx);
rs_status_t rs_i2s_disable(void);
rs_status_t rs_i2s_flush(bool tx, bool rx, rs_timeout_t timeout);
rs_status_t rs_i2s_write(uint32_t word, rs_timeout_t timeout);
rs_status_t rs_i2s_read(uint32_t *word, rs_timeout_t timeout);
uintptr_t rs_i2s_txdata_address(void);
uintptr_t rs_i2s_rxdata_address(void);
rs_status_t rs_i2s_get_status(rs_i2s_status_t *status);
rs_status_t rs_i2s_interrupt_enable(uint32_t mask);
rs_status_t rs_i2s_interrupt_clear(uint32_t mask);
rs_status_t rs_i2s_interrupt_test(uint32_t mask);
void ip_i2s_test(int argc, char **argv);
void ip_i2s_player(int argc, char **argv);

#endif
