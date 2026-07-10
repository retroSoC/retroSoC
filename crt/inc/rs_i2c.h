#ifndef TINYI2C_H__
#define TINYI2C_H__

#define I2C0_XFER_WR       0b10
#define I2C0_XFER_RD       0b11

#define I2C_DEV_ADDR_8BIT  0
#define I2C_DEV_ADDR_16BIT 1

void     i2c0_init(uint8_t clkdiv);
void     i2c0_wr_nbyte(uint8_t dev_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);
void     i2c0_rd_nbyte(uint8_t dev_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);

#endif