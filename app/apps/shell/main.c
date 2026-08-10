#include <retrosoc/board/pcf8563b.h>
#include <retrosoc/board/w25q128jvxim.h>
#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/crc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/hpuart.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/ws2812.h>
#include <retrosoc/hal/ps2.h>
#include <retrosoc/hal/pwm.h>
#include <retrosoc/hal/qspi.h>
#include <retrosoc/hal/rng.h>
#include <retrosoc/hal/rtc.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/watchdog.h>
#include <retrosoc/media/donut.h>
#include <retrosoc/service/booter.h>
#include <retrosoc/service/shell.h>

static void rs_app_info_command(int argc, char **argv) {
    (void)argc;
    (void)argv;
    rs_app_info();
}

int main(void) {
    if (rs_uart_init(CPU_FREQ * UINT32_C(1000000), UART_BPS) != RS_OK) {
        return 1;
    }
    rs_booter();
    if (rs_i2c_init(RS_I2C_BUS_0, CPU_FREQ * UINT32_C(1000000), UINT32_C(400000)) != RS_OK) {
        return 1;
    }
    qspi_dev_init();
    lcd_init();

    // lv_init();
    // lv_tick_set_cb(my_get_millis);

    // lv_port_disp_init();

    // lv_obj_t *label = lv_label_create(lv_scr_act());
    // lv_label_set_text(label,"Hello maksyuki!!!");
    // lv_obj_center(label);

    // while(1) {
    //     lv_timer_handler();
    //     printf("hello\n");
    // }

    rs_shell_init();
    (void)rs_shell_register("app", "app info", true, rs_app_info_command);
    (void)rs_shell_register("arch", "archinfo test", true, ip_archinfo_test);
    (void)rs_shell_register("ws2812", "ws2812 test", true, ip_ws2812_test);
    (void)rs_shell_register("tim", "timer test", true, rs_timer_shell_test);
    (void)rs_shell_register("gpio", "gpio test", true, rs_gpio_shell_test);
    (void)rs_shell_register("pwm", "pwm test", true, rs_pwm_shell_test);
    (void)rs_shell_register("rtc", "rtc test", true, rs_rtc_shell_test);
    (void)rs_shell_register("wdg", "wdg test", true, ip_wdg_test);
    (void)rs_shell_register("rng", "rng test", true, rs_rng_shell_test);
    (void)rs_shell_register("crc", "crc test", true, rs_crc_shell_test);
    (void)rs_shell_register("ps2", "ps2 test", false, rs_ps2_shell_test);
    (void)rs_shell_register("lcd", "lcd test", true, ip_lcd_test);
    (void)rs_shell_register("i2s", "i2s test", false, ip_i2s_test);
    (void)rs_shell_register("nor", "nor flash test", false, ip_norflash_test);
    (void)rs_shell_register("uart1", "uart1 test", false, ip_hpuart_test);
    (void)rs_shell_register("pcf", "pcf8563b test", true, pcf8563b_test);
#ifdef CSR_ENABLE
    (void)rs_shell_register("irq", "tmr/sw irq test", true, irq_test);
#endif
    (void)rs_shell_register("donut", "donut test", false, donut_test);
    rs_shell_batch_run();
    rs_shell_launch();
    // video_show(0x60000000);
    // ip_norflash_test();
    // ip_lcd_test(0, NULL);

    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    // ip_dma_test(0, NULL);
    // rs_bench(true, 0);
    return 0;
}
