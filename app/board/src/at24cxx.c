#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/board/at24cxx.h>

static const rs_i2c_register_access_t at24c64_test_access = {
    .address = AT24C64_DEV_ADDR,
    .ten_bit_address = false,
    .register_address = 0U,
    .register_address_width = RS_I2C_REGISTER_ADDRESS_16_BIT,
};

void at24cxx_test(void) {
    printf("AT24C64 wr/rd test\n");
    // prepare ref data
    uint8_t ref_data[I2C_TEST_NUM], rd_data[I2C_TEST_NUM];
    for (uint8_t i = 0U; i < I2C_TEST_NUM; ++i) {
        ref_data[i] = i;
    }
    // write AT24C64
    if (rs_i2c_register_write(RS_I2C_BUS_0, &at24c64_test_access, ref_data, I2C_TEST_NUM,
                              RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("AT24C64 write timed out\n");
        return;
    }
    // read AT24C64
    if (rs_i2c_register_read(RS_I2C_BUS_0, &at24c64_test_access, rd_data, I2C_TEST_NUM,
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

    (void)rs_i2c_register_write(RS_I2C_BUS_0, &at24c64_test_access, ref_data, I2C_TEST_NUM,
                                RS_TIMEOUT_DEFAULT);

    printf("AT24C64 wr/rd test done\n");
}
