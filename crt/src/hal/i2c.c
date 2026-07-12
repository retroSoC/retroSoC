#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/i2c.h>

static rs_status_t rs_i2c0_validate(uint8_t address_width, uint8_t count, const void *data) {
    if ((address_width > RS_I2C_DEVICE_ADDRESS_16BIT) || ((count != 0U) && (data == NULL))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_i2c0_init(uint8_t clock_divider) {
    reg_i2c0_clkdiv = clock_divider;
    return RS_OK;
}

rs_status_t rs_i2c0_write(uint8_t device_address, uint16_t register_address, uint8_t address_width,
                          uint8_t count, const uint8_t *data, rs_timeout_t timeout) {
    rs_status_t status = rs_i2c0_validate(address_width, count, data);

    if (status != RS_OK) {
        return status;
    }
    reg_i2c0_devaddr = device_address;
    reg_i2c0_cfg = address_width;
    for (uint8_t index = 0U; index < count; ++index) {
        reg_i2c0_regaddr = (uint32_t)register_address + index;
        reg_i2c0_txdata = data[index];
        reg_i2c0_xfer = RS_I2C_XFER_WRITE;
        status = rs_wait_mask(&reg_i2c0_status, UINT32_MAX, 1U, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    return RS_OK;
}

rs_status_t rs_i2c0_read(uint8_t device_address, uint16_t register_address, uint8_t address_width,
                         uint8_t count, uint8_t *data, rs_timeout_t timeout) {
    rs_status_t status = rs_i2c0_validate(address_width, count, data);

    if (status != RS_OK) {
        return status;
    }
    reg_i2c0_devaddr = device_address;
    reg_i2c0_cfg = address_width;
    for (uint8_t index = 0U; index < count; ++index) {
        reg_i2c0_regaddr = (uint32_t)register_address + index;
        reg_i2c0_xfer = RS_I2C_XFER_READ;
        status = rs_wait_mask(&reg_i2c0_status, UINT32_MAX, 1U, timeout);
        if (status != RS_OK) {
            return status;
        }
        data[index] = (uint8_t)reg_i2c0_rxdata;
    }
    return RS_OK;
}
