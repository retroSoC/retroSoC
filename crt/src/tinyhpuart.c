#include <firmware.h>
#include <tinyprintf.h>
#include <tinyhpuart.h>

void ip_hpuart_test()
{
    printf("[CUST IP] uart test\n");

    printf("[UART DIV] %x\n", reg_cust_uart_div);
    printf("[UART LCR] %x\n", reg_cust_uart_lcr);

    reg_cust_uart_div = (uint32_t)434;    // 50x10^6 / 115200
    reg_cust_uart_fcr = (uint32_t)0b1111; // clear tx and rx fifo
    reg_cust_uart_fcr = (uint32_t)0b1100;
    reg_cust_uart_lcr = (uint32_t)0b00011111; // 8N1, en all irq

    printf("[UART DIV] %x\n", reg_cust_uart_div);
    printf("[UART LCR] %x\n", reg_cust_uart_lcr);

    printf("uart tx test\n");
    uint32_t val = (uint32_t)0x41;
    for (int i = 0; i < 30; ++i)
    {
        while (((reg_cust_uart_lsr & 0x100) >> 8) == 1)
            ;
        reg_cust_uart_trx = (uint32_t)(val + i);
    }

    printf("uart tx test done\n");
    printf("uart rx test\n");
    // uint32_t rx_val = 0;
    // for (int i = 0; i < 36; ++i)
    // {
    //     while (((reg_cust_uart_lsr & 0x080) >> 7) == 1)
    //         ;
    //     rx_val = reg_cust_uart_trx;
    //     printf("[UART TRX] %x\n", rx_val);
    // }

    // printf("uart rx test done\n");
    printf("uart done\n");
}
