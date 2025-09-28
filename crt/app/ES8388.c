#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>
#include <ES8388.h>

#define ES8388_PHONE_VOLUME 20
#define ES8388_SPEAK_VOLUME 30

uint8_t es8388_init_cfg[] = {
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

void ES8388_init() {
    int init_cfg_len = sizeof(es8388_init_cfg)/sizeof(uint8_t);
    printf("[ES8388] init cfg len: %d\n", init_cfg_len);
    for(int i = 0; i < init_cfg_len; i += 2) {
        i2c0_wr_nbyte(ES8388_DEV_ADDR, (uint16_t)es8388_init_cfg[i], I2C_DEV_ADDR_8BIT, 1, es8388_init_cfg + i + 1);
    }

    uint8_t rxdata[60] = {0};
    i2c0_rd_nbyte(ES8388_DEV_ADDR, (uint16_t)0, I2C_DEV_ADDR_8BIT, 53, rxdata);
    for(int i = 0; i < 53; ++i) {
        printf("[ES8388] reg: %d val:%x\n", i, rxdata[i]);
    }
}