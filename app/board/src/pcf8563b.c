#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/board/pcf8563b.h>

static const rs_i2c_register_access_t pcf8563b_time_access = {
    .address = PCF8563B_DEV_ADDR,
    .ten_bit_address = false,
    .register_address = PCF8563B_SECOND_REG,
    .register_address_width = RS_I2C_REGISTER_ADDRESS_8_BIT,
};

uint8_t pcf8563b_bin2bcd(uint8_t val) {
    uint8_t bcdhigh = 0;
    while (val >= 10) {
        ++bcdhigh;
        val -= 10;
    }
    return ((uint8_t)(bcdhigh << 4) | val);
}

uint8_t pcf8563b_bcd2bin(uint8_t val, uint8_t reg_width) {
    uint8_t res = 0;
    res = (val & (reg_width & 0xF0)) >> 4;
    res = res * 10 + (val & (reg_width & 0x0F));
    return res;
}

void pcf8563b_wr_reg(PCF8563B_info_t *info) {
    uint8_t wr_data[7] = {0};

    if (info == NULL) {
        return;
    }
    *wr_data = pcf8563b_bin2bcd(info->time.second);
    *(wr_data + 1) = pcf8563b_bin2bcd(info->time.minute);
    *(wr_data + 2) = pcf8563b_bin2bcd(info->time.hour);
    *(wr_data + 3) = pcf8563b_bin2bcd(info->date.day);
    *(wr_data + 4) = pcf8563b_bin2bcd(info->date.weekday);
    *(wr_data + 5) = pcf8563b_bin2bcd(info->date.month);
    *(wr_data + 6) = pcf8563b_bin2bcd(info->date.year);
    if (rs_i2c_register_write(RS_I2C_BUS_0, &pcf8563b_time_access, wr_data, 7U,
                              RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("[PCF8563B] write failed\n");
    }
}

PCF8563B_info_t pcf8563b_rd_reg(void) {
    uint8_t rd_data[7] = {0};
    PCF8563B_info_t info = {0};

    if (rs_i2c_register_read(RS_I2C_BUS_0, &pcf8563b_time_access, rd_data, 7U,
                             RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("[PCF8563B] read failed\n");
        return info;
    }
    info.time.second = pcf8563b_bcd2bin(rd_data[0], SECOND_MINUTE_REG_WIDTH);
    info.time.minute = pcf8563b_bcd2bin(rd_data[1], SECOND_MINUTE_REG_WIDTH);
    info.time.hour = pcf8563b_bcd2bin(rd_data[2], HOUR_DAY_REG_WIDTH);
    info.date.day = pcf8563b_bcd2bin(rd_data[3], HOUR_DAY_REG_WIDTH);
    info.date.weekday = pcf8563b_bcd2bin(rd_data[4], WEEKDAY_REG_WIDTH);
    info.date.month = pcf8563b_bcd2bin(rd_data[5], MONTH_REG_WIDTH);
    info.date.year = pcf8563b_bcd2bin(rd_data[6], YEAR_REG_WIDTH);
    return info;
}

void pcf8563b_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("PCF8563B test\n");
    PCF8563B_info_t init1_info = {.time.second = 51,
                                  .time.minute = 30,
                                  .time.hour = 18,
                                  .date.weekday = 3,
                                  .date.day = 16,
                                  .date.month = 9,
                                  .date.year = 25};
    pcf8563b_wr_reg(&init1_info);

    PCF8563B_info_t rd_info = {0};
    for (int i = 0; i < 6; ++i) {
        rd_info = pcf8563b_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
               rd_info.date.day, rd_info.date.weekday, rd_info.time.hour, rd_info.time.minute,
               rd_info.time.second);
        if (rs_timer_delay_ms(RS_TIMER_0, 1000U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            printf("PCF8563B timer delay failed\n");
            return;
        }
    }

    PCF8563B_info_t init2_info = {.time.second = 23,
                                  .time.minute = 22,
                                  .time.hour = 12,
                                  .date.weekday = 1,
                                  .date.day = 19,
                                  .date.month = 8,
                                  .date.year = 24};
    pcf8563b_wr_reg(&init2_info);
    for (int i = 0; i < 6; ++i) {
        rd_info = pcf8563b_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
               rd_info.date.day, rd_info.date.weekday, rd_info.time.hour, rd_info.time.minute,
               rd_info.time.second);
        if (rs_timer_delay_ms(RS_TIMER_0, 1000U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            printf("PCF8563B timer delay failed\n");
            return;
        }
    }

    printf("PCF8563B test done\n");
}
