#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/hpuart.h>

void ip_hpuart_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("[IP] uart test\n");

    printf("[UART DIV] %x\n", reg_uart1_div);
    printf("[UART LCR] %x\n", reg_uart1_lcr);

    reg_uart1_div = (uint32_t)434;    // 50x10^6 / 115200
    reg_uart1_fcr = (uint32_t)0b1111; // clear tx and rx fifo
    reg_uart1_fcr = (uint32_t)0b1100;
    reg_uart1_lcr = (uint32_t)0b00011111; // 8N1, en all irq

    printf("[UART DIV] %x\n", reg_uart1_div);
    printf("[UART LCR] %x\n", reg_uart1_lcr);

    printf("uart tx test\n");
    uint32_t val = (uint32_t)0x41;
    for (uint32_t i = 0U; i < 30U; ++i) {
        if (rs_wait_mask(&reg_uart1_lsr, 0x100U, 0U, RS_TIMEOUT_DEFAULT) != RS_OK) {
            printf("uart tx fifo timed out\n");
            return;
        }
        reg_uart1_trx = (uint32_t)(val + i);
    }

    printf("uart tx test done\n");
    printf("uart rx test\n");
    // uint32_t rx_val = 0;
    // for (int i = 0; i < 36; ++i)
    // {
    //     while (((reg_uart1_lsr & 0x080) >> 7) == 1)
    //         ;
    //     rx_val = reg_uart1_trx;
    //     printf("[UART TRX] %x\n", rx_val);
    // }

    // printf("uart rx test done\n");
    printf("uart done\n");
}
