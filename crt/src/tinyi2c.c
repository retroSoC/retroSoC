#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>

void i2c0_init(uint8_t clkdiv) {
    // printf("[i2c0] clkdiv: %d\n", reg_i2c0_clkdiv);
    reg_i2c0_clkdiv = clkdiv;
    // printf("[i2c0] clkdiv: %d\n", reg_i2c0_clkdiv);
}

void i2c0_wr_nbyte(uint8_t dev_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    reg_i2c0_devaddr = dev_addr;
    reg_i2c0_cfg = type;
    for(int i = 0; i < num; ++i) {
        // HACK: just repeat it by using no-burst xfer
        reg_i2c0_regaddr = reg_addr + i;
        reg_i2c0_txdata = data[i];
        reg_i2c0_xfer = I2C0_XFER_WR;
        while(reg_i2c0_status != (uint32_t)1);
    }
}

void i2c0_rd_nbyte(uint8_t dev_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    reg_i2c0_devaddr = dev_addr;
    reg_i2c0_cfg = type;
    for(int i = 0; i < num; ++i) {
        // HACK: just repeat it by using no-burst xfer
        reg_i2c0_regaddr = reg_addr + i;
        reg_i2c0_xfer = I2C0_XFER_RD;
        while(reg_i2c0_status != (uint32_t)1);
        // printf("[i2c0] i: %d, rxdata: %x\n", i, reg_i2c0_rxdata);
        data[i] = reg_i2c0_rxdata;
    }
}
