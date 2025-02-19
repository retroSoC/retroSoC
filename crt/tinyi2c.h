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

#define I2C_TEST_NUM         24
#define AT24C64_SLV_ADDR     0xA0
#define PCF8563B_SLV_ADDR    0xA2

#define PCF8563B_CTL_STATUS1 ((uint8_t)0x00)
#define PCF8563B_CTL_STATUS2 ((uint8_t)0x01)
#define PCF8563B_SECOND_REG  ((uint8_t)0x02)
#define PCF8563B_MINUTE_REG  ((uint8_t)0x03)
#define PCF8563B_HOUR_REG    ((uint8_t)0x04)
#define PCF8563B_DAY_REG     ((uint8_t)0x05)
#define PCF8563B_WEEKDAY_REG ((uint8_t)0x06)
#define PCF8563B_MONTH_REG   ((uint8_t)0x07)
#define PCF8563B_YEAR_REG    ((uint8_t)0x08)

#define SECOND_MINUTE_REG_WIDTH ((uint8_t)0x7F)
#define HOUR_DAY_REG_WIDTH      ((uint8_t)0x3F)
#define WEEKDAY_REG_WIDTH       ((uint8_t)0x07)
#define MONTH_REG_WIDTH         ((uint8_t)0x1F)
#define YEAR_REG_WIDTH          ((uint8_t)0xFF)
#define BCD_Century             ((uint8_t)0x80)

typedef struct {
    struct {
        uint8_t second;
        uint8_t minute;
        uint8_t hour;
    } time;

    struct {
        uint8_t weekday;
        uint8_t day;
        uint8_t month;
        uint8_t year;
    } date;

} PCF8563B_info_t;


void     i2c_config();
uint32_t i2c_get_ack();
uint32_t i2c_busy();
void     i2c_wr_start(uint32_t slv_addr);
void     i2c_rd_start(uint32_t slv_addr);
void     i2c_write(uint8_t val);
uint32_t i2c_read(uint32_t cmd);
void     i2c_wr_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);
void     i2c_rd_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data);

uint8_t PCF8563B_bcd2bin(uint8_t val,uint8_t reg_width);
uint8_t PCF8563B_bin2bcd(uint8_t val);

void PCF8563B_wr_reg(PCF8563B_info_t *info);
PCF8563B_info_t PCF8563B_rd_reg();

void ip_i2c_test();

#endif