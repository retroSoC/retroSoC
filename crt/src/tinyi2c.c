#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>

void i2c_config() {
    reg_cust_i2c_ctrl = (uint32_t)0;
    reg_cust_i2c_pscr = (uint32_t)99;         // 50MHz / (5 * 100KHz) - 1
    printf("CTRL: %d PSCR: %d\n", reg_cust_i2c_ctrl, reg_cust_i2c_pscr);
    reg_cust_i2c_ctrl = (uint32_t)0b10000000; // core en
}

uint32_t i2c_get_ack() {
    while ((reg_cust_i2c_sr & I2C_STATUS_TIP) == 0); // need TIP go to 1
    while ((reg_cust_i2c_sr & I2C_STATUS_TIP) != 0); // and then go back to 0
    return !(reg_cust_i2c_sr & I2C_STATUS_RXACK);    // invert since signal is active low
}

uint32_t i2c_busy() {
    return ((reg_cust_i2c_sr & I2C_STATUS_BUSY) == I2C_STATUS_BUSY);
}

void i2c_wr_start(uint32_t slv_addr) {
    reg_cust_i2c_txr = slv_addr;
    reg_cust_i2c_cmd = I2C_TEST_START_WRITE;
    if (!i2c_get_ack()) printf("[wr start]no ack recv\n");
}

void i2c_rd_start(uint32_t slv_addr) {
    do {
        reg_cust_i2c_txr = slv_addr;
        reg_cust_i2c_cmd = I2C_TEST_START_WRITE;
    }while (!i2c_get_ack());
}

void i2c_write(uint8_t val) {
    reg_cust_i2c_txr = val;
    reg_cust_i2c_cmd = I2C_TEST_WRITE;
    if (!i2c_get_ack()) printf("[i2c write]no ack recv\n");
    // do {
    //     reg_cust_i2c_txr = val;
    //     reg_cust_i2c_cmd = I2C_TEST_WRITE;
    // } while(!i2c_get_ack());
}

uint32_t i2c_read(uint32_t cmd) {
    reg_cust_i2c_cmd = cmd;
    if (!i2c_get_ack()) printf("[i2c read]no ack recv\n");
    return reg_cust_i2c_rxr;
}

void i2c_stop() {
    reg_cust_i2c_cmd = I2C_TEST_STOP;
    while(i2c_busy());
}

void i2c_wr_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    // i2c_wr_start(slv_addr);
    i2c_rd_start(slv_addr);
    if(type == I2C_DEV_ADDR_16BIT) {
        i2c_write((uint8_t)((reg_addr >> 8) & 0xFF));
        i2c_write((uint8_t)(reg_addr & 0xFF));
    } else {
        i2c_write((uint8_t)(reg_addr & 0xFF));
    }
    for(int i = 0; i < num; ++i) {
        i2c_write(*data);
        ++data;
    }
    i2c_stop();
}

void i2c_rd_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    i2c_rd_start(slv_addr);
    if(type == I2C_DEV_ADDR_16BIT) {
        i2c_write((uint8_t)((reg_addr >> 8) & 0xFF));
        i2c_write((uint8_t)(reg_addr & 0xFF));
    } else {
        i2c_write((uint8_t)(reg_addr & 0xFF));
    }
    i2c_stop();

    i2c_wr_start(slv_addr + 1);
    for (int i = 0; i < num; ++i) {
        if (i == num - 1) data[i] = i2c_read(I2C_TEST_STOP_READ);
        else data[i] = i2c_read(I2C_TEST_READ);
    }
}

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
    i2c_wr_nbyte(PCF8563B_SLV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, wr_data);
}

PCF8563B_info_t PCF8563B_rd_reg() {
    uint8_t rd_data[7] = {0};
    PCF8563B_info_t info = {0};
    i2c_rd_nbyte(PCF8563B_SLV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, rd_data);
    info.time.second  = PCF8563B_bcd2bin(rd_data[0], SECOND_MINUTE_REG_WIDTH);
    info.time.minute  = PCF8563B_bcd2bin(rd_data[1], SECOND_MINUTE_REG_WIDTH);
    info.time.hour    = PCF8563B_bcd2bin(rd_data[2], HOUR_DAY_REG_WIDTH);
    info.date.day     = PCF8563B_bcd2bin(rd_data[3], HOUR_DAY_REG_WIDTH);
    info.date.weekday = PCF8563B_bcd2bin(rd_data[4], WEEKDAY_REG_WIDTH);
    info.date.month   = PCF8563B_bcd2bin(rd_data[5], MONTH_REG_WIDTH);
    info.date.year    = PCF8563B_bcd2bin(rd_data[6], YEAR_REG_WIDTH);
    return info;
}

void ip_i2c_test() {
    printf("i2c test\n");
    i2c_config();
    printf("AT24C64 wr/rd test\n");
    // prepare ref data
    // uint8_t ref_data[I2C_TEST_NUM], rd_data[I2C_TEST_NUM];
    // for(int i = 0; i < I2C_TEST_NUM; ++i) ref_data[i] = i;
    // // write AT24C64
    // i2c_wr_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);
    // // read AT24C64
    // i2c_rd_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, rd_data);
    // // check data
    // for(int i = 0; i < I2C_TEST_NUM; ++i) {
    //     printf("recv: %d expt: %d\n", rd_data[i], i);
    //     if (rd_data[i] != i) printf("test fail\n");
    // }

    // i2c_wr_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);

    printf("AT24C64 wr/rd test done\n");
    printf("PCF8563B test\n");
    PCF8563B_info_t init1_info = {
        .time.second  = 51,
        .time.minute  = 30,
        .time.hour    = 18,
        .date.weekday = 3,
        .date.day     = 7,
        .date.month   = 8,
        .date.year    = 24
    };
    PCF8563B_wr_reg(&init1_info);

    PCF8563B_info_t rd_info = {0};
    for(int i = 0; i < 100; ++i) {
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
    for(int i = 0; i < 100; ++i) {
        rd_info = PCF8563B_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
                                                    rd_info.date.day, rd_info.date.weekday,
                                                    rd_info.time.hour, rd_info.time.minute,
                                                    rd_info.time.second);
    }

    printf("PCF8563B test done\n");
    printf("test done\n");
}
