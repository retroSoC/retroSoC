#ifndef RETROSOC_HAL_I2C_H
#define RETROSOC_HAL_I2C_H

#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_I2C_XFER_WRITE           0x2U
#define RS_I2C_XFER_READ            0x3U
#define RS_I2C_DEVICE_ADDRESS_8BIT  0U
#define RS_I2C_DEVICE_ADDRESS_16BIT 1U

rs_status_t rs_i2c0_init(uint8_t clock_divider);
rs_status_t rs_i2c0_write(uint8_t device_address, uint16_t register_address, uint8_t address_width,
                          uint8_t count, const uint8_t *data, rs_timeout_t timeout);
rs_status_t rs_i2c0_read(uint8_t device_address, uint16_t register_address, uint8_t address_width,
                         uint8_t count, uint8_t *data, rs_timeout_t timeout);

#endif
