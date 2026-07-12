#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/board/es8388.h>

#define ES8388_PHONE_VOLUME 3
#define ES8388_SPEAK_VOLUME 3

static const uint8_t es8388_init_cfg[] = {
    (uint8_t)0,  (uint8_t)0x80,
    (uint8_t)0,  (uint8_t)0x00,
    (uint8_t)1,  (uint8_t)0x58,
    (uint8_t)1,  (uint8_t)0x50,
    (uint8_t)2,  (uint8_t)0xf3,
    (uint8_t)2,  (uint8_t)0x00,
    (uint8_t)3,  (uint8_t)0x09,
    (uint8_t)0,  (uint8_t)0x06,
    (uint8_t)4,  (uint8_t)0x3c,
    (uint8_t)8,  (uint8_t)0x00,
    (uint8_t)9,  (uint8_t)0x66,
    (uint8_t)10, (uint8_t)0x50,
    (uint8_t)12, (uint8_t)0b01001100,
    (uint8_t)13, (uint8_t)0x0c,
    (uint8_t)16, (uint8_t)0x00,
    (uint8_t)17, (uint8_t)0x00,
    (uint8_t)18, (uint8_t)0xc0,
    (uint8_t)23, (uint8_t)0b00011000,
    (uint8_t)24, (uint8_t)0x0c,
    (uint8_t)26, (uint8_t)0x0a,
    (uint8_t)27, (uint8_t)0x0a,
    (uint8_t)29, (uint8_t)0x1c,
    (uint8_t)39, (uint8_t)0xf8,
    (uint8_t)42, (uint8_t)0xf8,
    (uint8_t)43, (uint8_t)0x80,
    (uint8_t)46, (uint8_t)ES8388_PHONE_VOLUME,
    (uint8_t)47, (uint8_t)ES8388_PHONE_VOLUME,
    (uint8_t)48, (uint8_t)ES8388_SPEAK_VOLUME,
    (uint8_t)49, (uint8_t)ES8388_SPEAK_VOLUME,
};

void es8388_init(void) {
    const uint32_t init_cfg_len = sizeof(es8388_init_cfg) / sizeof(es8388_init_cfg[0]);

    printf("[ES8388] init cfg len: %u\n", init_cfg_len);
    for (uint32_t i = 0U; i < init_cfg_len; i += 2U) {
        if (rs_i2c0_write(ES8388_DEV_ADDR, (uint16_t)es8388_init_cfg[i], RS_I2C_DEVICE_ADDRESS_8BIT,
                          1U, es8388_init_cfg + i + 1, RS_TIMEOUT_DEFAULT) != RS_OK) {
            printf("[ES8388] write failed at register %d\n", es8388_init_cfg[i]);
            return;
        }
    }

    uint8_t rxdata[60] = {0};
    if (rs_i2c0_read(ES8388_DEV_ADDR, 0U, RS_I2C_DEVICE_ADDRESS_8BIT, 53U, rxdata,
                     RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("[ES8388] read failed\n");
        return;
    }
    for (uint32_t i = 0U; i < 53U; ++i) {
        printf("[ES8388] reg: %d val:%x\n", i, rxdata[i]);
    }
}
