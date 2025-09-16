#ifndef TINYI2C_H__
#define TINYI2C_H__

#define I2C_TEST_START       ((uint32_t)0x80)
#define I2C_TEST_STOP        ((uint32_t)0x40)
#define I2C_TEST_READ        ((uint32_t)0x20)
#define I2C_TEST_WRITE       ((uint32_t)0x10)
#define I2C_TEST_START_READ  ((uint32_t)0xA0)
#define I2C_TEST_START_WRITE ((uint32_t)0x90)
#define I2C_TEST_STOP_READ   ((uint32_t)0x60)
#define I2C_TEST_STOP_WRITE  ((uint32_t)0x50)

#define I2C_STATUS_RXACK     ((uint32_t)0x80) // (1 << 7)
#define I2C_STATUS_BUSY      ((uint32_t)0x40) // (1 << 6)
#define I2C_STATUS_AL        ((uint32_t)0x20) // (1 << 5)
#define I2C_STATUS_TIP       ((uint32_t)0x02) // (1 << 1)
#define I2C_STATUS_IF        ((uint32_t)0x01) // (1 << 0)

#define I2C_DEV_ADDR_16BIT   0
#define I2C_DEV_ADDR_8BIT    1

void     i2c_config();
uint32_t i2c_get_ack();
uint32_t i2c_busy();
void     i2c_wr_start(uint32_t slv_addr);
void     i2c_rd_start(uint32_t slv_addr);
void     i2c_write(uint8_t val);
uint32_t i2c_read(uint32_t cmd);
void     i2c_wr_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);
void     i2c_rd_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);

#endif