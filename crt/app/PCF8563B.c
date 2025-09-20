#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>
#include <PCF8563B.h>

uint8_t PCF8563B_bin2bcd(uint8_t val) {
    uint8_t bcdhigh = 0;
    while (val >= 10) {
        ++bcdhigh;
        val -= 10;
    }
    return ((uint8_t)(bcdhigh << 4) | val);
}

uint8_t PCF8563B_bcd2bin(uint8_t val,uint8_t reg_width)
{
    uint8_t res = 0;
    res = (val & (reg_width & 0xF0)) >> 4;
    res = res * 10 + (val & (reg_width & 0x0F));
    return res;
}

void PCF8563B_wr_reg(PCF8563B_info_t *info) {
    uint8_t wr_data[7] = {0};
    *wr_data       = PCF8563B_bin2bcd(info->time.second);
    *(wr_data + 1) = PCF8563B_bin2bcd(info->time.minute);
    *(wr_data + 2) = PCF8563B_bin2bcd(info->time.hour);
    *(wr_data + 3) = PCF8563B_bin2bcd(info->date.day);
    *(wr_data + 4) = PCF8563B_bin2bcd(info->date.weekday);
    *(wr_data + 5) = PCF8563B_bin2bcd(info->date.month);
    *(wr_data + 6) = PCF8563B_bin2bcd(info->date.year);
    i2c0_wr_nbyte(PCF8563B_DEV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, wr_data);
}

PCF8563B_info_t PCF8563B_rd_reg() {
    uint8_t rd_data[7] = {0};
    PCF8563B_info_t info = {0};
    i2c0_rd_nbyte(PCF8563B_DEV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, rd_data);
    info.time.second  = PCF8563B_bcd2bin(rd_data[0], SECOND_MINUTE_REG_WIDTH);
    info.time.minute  = PCF8563B_bcd2bin(rd_data[1], SECOND_MINUTE_REG_WIDTH);
    info.time.hour    = PCF8563B_bcd2bin(rd_data[2], HOUR_DAY_REG_WIDTH);
    info.date.day     = PCF8563B_bcd2bin(rd_data[3], HOUR_DAY_REG_WIDTH);
    info.date.weekday = PCF8563B_bcd2bin(rd_data[4], WEEKDAY_REG_WIDTH);
    info.date.month   = PCF8563B_bcd2bin(rd_data[5], MONTH_REG_WIDTH);
    info.date.year    = PCF8563B_bcd2bin(rd_data[6], YEAR_REG_WIDTH);
    return info;
}

void PCF8563B_test() {
   printf("PCF8563B test\n");
    PCF8563B_info_t init1_info = {
        .time.second  = 51,
        .time.minute  = 30,
        .time.hour    = 18,
        .date.weekday = 3,
        .date.day     = 16,
        .date.month   = 9,
        .date.year    = 25
    };
    PCF8563B_wr_reg(&init1_info);

    PCF8563B_info_t rd_info = {0};
    for(int i = 0; i < 50; ++i) {
        rd_info = PCF8563B_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
                                                    rd_info.date.day, rd_info.date.weekday,
                                                    rd_info.time.hour, rd_info.time.minute,
                                                    rd_info.time.second);
    }

    PCF8563B_info_t init2_info = {
        .time.second  = 23,
        .time.minute  = 22,
        .time.hour    = 12,
        .date.weekday = 1,
        .date.day     = 19,
        .date.month   = 8,
        .date.year    = 24
    };
    PCF8563B_wr_reg(&init2_info);
    for(int i = 0; i < 50; ++i) {
        rd_info = PCF8563B_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
                                                    rd_info.date.day, rd_info.date.weekday,
                                                    rd_info.time.hour, rd_info.time.minute,
                                                    rd_info.time.second);
    }

    printf("PCF8563B test done\n");
}