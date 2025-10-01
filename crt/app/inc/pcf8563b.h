#ifndef PCF8563B_H__
#define PCF8563B_H__

#define PCF8563B_DEV_ADDR       0x51

#define PCF8563B_CTL_STATUS1    ((uint8_t)0x00)
#define PCF8563B_CTL_STATUS2    ((uint8_t)0x01)
#define PCF8563B_SECOND_REG     ((uint8_t)0x02)
#define PCF8563B_MINUTE_REG     ((uint8_t)0x03)
#define PCF8563B_HOUR_REG       ((uint8_t)0x04)
#define PCF8563B_DAY_REG        ((uint8_t)0x05)
#define PCF8563B_WEEKDAY_REG    ((uint8_t)0x06)
#define PCF8563B_MONTH_REG      ((uint8_t)0x07)
#define PCF8563B_YEAR_REG       ((uint8_t)0x08)

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

// helper functions
uint8_t pcf8563b_bcd2bin(uint8_t val,uint8_t reg_width);
uint8_t pcf8563b_bin2bcd(uint8_t val);

void pcf8563b_wr_reg(PCF8563B_info_t *info);
PCF8563B_info_t pcf8563b_rd_reg();

void pcf8563b_test();

#endif
