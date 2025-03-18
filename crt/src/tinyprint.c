#include <firmware.h>
#include <tinyprint.h>

void putchar(char c)
{
    if (c == '\n')
        putchar('\r');
    reg_uart_data = c;
}

void print(const char *p)
{
    while (*p)
        putchar(*(p++));
}

void print_hex(uint32_t v, int digits)
{
    for (int i = 7; i >= 0; i--)
    {
        char c = "0123456789abcdef"[(v >> (4 * i)) & 15];
        if (c == '0' && i >= digits)
            continue;
        putchar(c);
        digits = i;
    }
}

void print_dec(uint32_t v)
{
    if (v >= 1000)
    {
        putstr(">=1000");
        return;
    }

    if (v >= 900)
    {
        putchar('9');
        v -= 900;
    }
    else if (v >= 800)
    {
        putchar('8');
        v -= 800;
    }
    else if (v >= 700)
    {
        putchar('7');
        v -= 700;
    }
    else if (v >= 600)
    {
        putchar('6');
        v -= 600;
    }
    else if (v >= 500)
    {
        putchar('5');
        v -= 500;
    }
    else if (v >= 400)
    {
        putchar('4');
        v -= 400;
    }
    else if (v >= 300)
    {
        putchar('3');
        v -= 300;
    }
    else if (v >= 200)
    {
        putchar('2');
        v -= 200;
    }
    else if (v >= 100)
    {
        putchar('1');
        v -= 100;
    }

    if (v >= 90)
    {
        putchar('9');
        v -= 90;
    }
    else if (v >= 80)
    {
        putchar('8');
        v -= 80;
    }
    else if (v >= 70)
    {
        putchar('7');
        v -= 70;
    }
    else if (v >= 60)
    {
        putchar('6');
        v -= 60;
    }
    else if (v >= 50)
    {
        putchar('5');
        v -= 50;
    }
    else if (v >= 40)
    {
        putchar('4');
        v -= 40;
    }
    else if (v >= 30)
    {
        putchar('3');
        v -= 30;
    }
    else if (v >= 20)
    {
        putchar('2');
        v -= 20;
    }
    else if (v >= 10)
    {
        putchar('1');
        v -= 10;
    }

    if (v >= 9)
    {
        putchar('9');
        v -= 9;
    }
    else if (v >= 8)
    {
        putchar('8');
        v -= 8;
    }
    else if (v >= 7)
    {
        putchar('7');
        v -= 7;
    }
    else if (v >= 6)
    {
        putchar('6');
        v -= 6;
    }
    else if (v >= 5)
    {
        putchar('5');
        v -= 5;
    }
    else if (v >= 4)
    {
        putchar('4');
        v -= 4;
    }
    else if (v >= 3)
    {
        putchar('3');
        v -= 3;
    }
    else if (v >= 2)
    {
        putchar('2');
        v -= 2;
    }
    else if (v >= 1)
    {
        putchar('1');
        v -= 1;
    }
    else
        putchar('0');
}

void print_reg_bit(int val, const char *name)
{
    for (int i = 0; i < 12; i++)
    {
        if (*name == 0)
            putchar(' ');
        else
            putchar(*(name++));
    }

    putchar(val ? '1' : '0');
    putchar('\n');
}

void print_reg(char *info, uint32_t val, int digits)
{
    putstr(info);
    print_hex(val, digits);
    putstr("\n");
}