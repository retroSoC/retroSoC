#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/board/at24cxx.h>

void at24cxx_test(void) {
    printf("AT24C64 wr/rd test\n");
    // prepare ref data
    uint8_t ref_data[I2C_TEST_NUM], rd_data[I2C_TEST_NUM];
    for (uint8_t i = 0U; i < I2C_TEST_NUM; ++i) {
        ref_data[i] = i;
    }
    // write AT24C64
    if (rs_i2c0_write(AT24C64_DEV_ADDR, 0U, RS_I2C_DEVICE_ADDRESS_16BIT, I2C_TEST_NUM, ref_data,
                      RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("AT24C64 write timed out\n");
        return;
    }
    // read AT24C64
    if (rs_i2c0_read(AT24C64_DEV_ADDR, 0U, RS_I2C_DEVICE_ADDRESS_16BIT, I2C_TEST_NUM, rd_data,
                     RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("AT24C64 read timed out\n");
        return;
    }
    // check data
    for (uint8_t i = 0U; i < I2C_TEST_NUM; ++i) {
        printf("recv: %d expt: %d\n", rd_data[i], i);
        if (rd_data[i] != i)
            printf("test fail\n");
    }

    (void)rs_i2c0_write(AT24C64_DEV_ADDR, 0U, RS_I2C_DEVICE_ADDRESS_16BIT, I2C_TEST_NUM, ref_data,
                        RS_TIMEOUT_DEFAULT);

    printf("AT24C64 wr/rd test done\n");
}
