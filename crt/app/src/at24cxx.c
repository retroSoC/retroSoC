#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2c.h>
#include <at24cxx.h>

void at24cxx_test() {
    printf("AT24C64 wr/rd test\n");
    // prepare ref data
    uint8_t ref_data[I2C_TEST_NUM], rd_data[I2C_TEST_NUM];
    for(int i = 0; i < I2C_TEST_NUM; ++i) ref_data[i] = i;
    // write AT24C64
    i2c0_wr_nbyte(AT24C64_DEV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);
    // read AT24C64
    i2c0_rd_nbyte(AT24C64_DEV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, rd_data);
    // check data
    for(int i = 0; i < I2C_TEST_NUM; ++i) {
        printf("recv: %d expt: %d\n", rd_data[i], i);
        if (rd_data[i] != i) printf("test fail\n");
    }

    i2c0_wr_nbyte(AT24C64_DEV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);

    printf("AT24C64 wr/rd test done\n");
}