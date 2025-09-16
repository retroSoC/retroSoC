#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>

void i2c_config() {
    reg_i2c1_ctrl = (uint32_t)0;
    reg_i2c1_pscr = (uint32_t)99;         // 50MHz / (5 * 100KHz) - 1
    printf("CTRL: %d PSCR: %d\n", reg_i2c1_ctrl, reg_i2c1_pscr);
    reg_i2c1_ctrl = (uint32_t)0b10000000; // core en
}

uint32_t i2c_get_ack() {
    while ((reg_i2c1_sr & I2C_STATUS_TIP) == 0); // need TIP go to 1
    while ((reg_i2c1_sr & I2C_STATUS_TIP) != 0); // and then go back to 0
    return !(reg_i2c1_sr & I2C_STATUS_RXACK);    // invert since signal is active low
}

uint32_t i2c_busy() {
    return ((reg_i2c1_sr & I2C_STATUS_BUSY) == I2C_STATUS_BUSY);
}

void i2c_wr_start(uint32_t slv_addr) {
    reg_i2c1_txr = slv_addr;
    reg_i2c1_cmd = I2C_TEST_START_WRITE;
    if (!i2c_get_ack()) printf("[wr start]no ack recv\n");
}

void i2c_rd_start(uint32_t slv_addr) {
    do {
        reg_i2c1_txr = slv_addr;
        reg_i2c1_cmd = I2C_TEST_START_WRITE;
    }while (!i2c_get_ack());
}

void i2c_write(uint8_t val) {
    reg_i2c1_txr = val;
    reg_i2c1_cmd = I2C_TEST_WRITE;
    if (!i2c_get_ack()) printf("[i2c write]no ack recv\n");
    // do {
    //     reg_i2c1_txr = val;
    //     reg_i2c1_cmd = I2C_TEST_WRITE;
    // } while(!i2c_get_ack());
}

uint32_t i2c_read(uint32_t cmd) {
    reg_i2c1_cmd = cmd;
    if (!i2c_get_ack()) printf("[i2c read]no ack recv\n");
    return reg_i2c1_rxr;
}

void i2c_stop() {
    reg_i2c1_cmd = I2C_TEST_STOP;
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