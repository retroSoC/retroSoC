#include <firmware.h>
#include <tinyprintf.h>
#include <tinyuart.h>
#include <tinysh.h>
#include <tinylib.h>

char getchar_prompt(char *prompt)
{
    int32_t c = -1;
    uint32_t cycles_begin, cycles_now, cycles;
    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_begin));

    if (prompt)
        printf(prompt);

    while (c == -1)
    {
        __asm__ volatile("rdcycle %0"
                         : "=r"(cycles_now));
        cycles = cycles_now - cycles_begin;
        if (cycles > 12000000)
        {
            if (prompt)
                printf(prompt);
            cycles_begin = cycles_now;
        }
        c = reg_uart_data;
    }
    return c;
}

void tinysh_echo()
{
    printf("Return to menu by sending '!'\n\n");
    char c;
    while ((c = getchar_prompt(0)) != '!')
        putch(c);
}

void tinysh()
{
    while (getchar_prompt("Press ENTER to continue..\n") != '\r')
    {
    }

    while (1)
    {
        printf("\nSelect an action:\n\n");
        printf("   [t] run timer test\n");
        printf("   [g] run gpio test\n");
        printf("   [h] print housekeeping spi info\n");
        printf("   [a] run archinfo test\n");
        printf("   [r] run rng test\n");
        printf("   [u] run uart test\n");
        printf("   [p] run pwm test\n");
        printf("   [s] run ps2 test\n");
        printf("   [i] run i2c test\n");
        printf("   [l] run lcd test\n");
        printf("   [b] run tiny benchmark\n");
        printf("   [m] run Memtest\n");
        printf("   [e] echo uart\n\n");

        for (int rep = 10; rep > 0; rep--)
        {
            printf("tinysh> ");
            char cmd = getchar_prompt(0);
            if (cmd > 32 && cmd < 127)
                putch(cmd);
            printf("\n");

            switch (cmd)
            {
            case 't':
                ip_tim_test();
                break;
            case 'g':
                ip_gpio_test();
                break;
            case 'h':
                ip_hk_spi_test();
                break;
            case 'a':
                ip_archinfo_test();
                break;
            case 'r':
                ip_rng_test();
                break;
            case 'u':
                ip_hpuart_test();
                break;
            case 'p':
                ip_pwm_test();
                break;
            case 's':
                ip_ps2_test();
                break;
            case 'i':
                ip_i2c_test();
                break;
            case 'l':
                ip_lcd_test();
                break;
            case 'b':
                tinybench(true, 0);
                break;
            case 'm':
                break;
            case 'e':
                tinysh_echo();
                break;
            default:
                continue;
            }
            break;
        }
    }
}
