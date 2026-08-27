    .section .text.start
    .global _start
    .type _start, @function

    .equ UART1_BASE,       0x10018000
    .equ UART_BAUD_INT,    0x00
    .equ UART_BAUD_FRAC,   0x04
    .equ UART_LINE_CTRL,   0x08
    .equ UART_CTRL,        0x0c
    .equ UART_TXDATA,      0x10
    .equ UART_STATUS,      0x18
    .equ UART_FIFO_CTRL,   0x20
    .equ UART_ERROR,       0x30
    .equ UART_INTR_ENABLE, 0x38
    .equ UART_TX_FULL,     0x20

    .equ MAILBOX_BASE,     0x10019000
    .equ HP_EVENT,         0x20
    .equ HP_ARG0,          0x24
    .equ HP_SEQUENCE,      0x28
    .equ HP_DOORBELL,      0x2c
    .equ HP_READY_ARG,     0x4c4e5801

_start:
    li      t0, UART1_BASE
    sw      zero, UART_CTRL(t0)
    li      t1, 3
    sw      t1, UART_FIFO_CTRL(t0)
    li      t1, 0x7f
    sw      t1, UART_ERROR(t0)
    sw      zero, UART_INTR_ENABLE(t0)
    li      t1, 78
    sw      t1, UART_BAUD_INT(t0)
    li      t1, 32
    sw      t1, UART_BAUD_FRAC(t0)
    li      t1, 3
    sw      t1, UART_LINE_CTRL(t0)
    sw      t1, UART_CTRL(t0)

    la      a0, hp_message
write_character:
    lbu     a1, 0(a0)
    beqz    a1, publish_ready
wait_tx_space:
    lw      a2, UART_STATUS(t0)
    andi    a2, a2, UART_TX_FULL
    bnez    a2, wait_tx_space
    sw      a1, UART_TXDATA(t0)
    addi    a0, a0, 1
    j       write_character

publish_ready:
    li      t0, MAILBOX_BASE
    li      t1, 1
    sw      t1, HP_EVENT(t0)
    li      t1, HP_READY_ARG
    sw      t1, HP_ARG0(t0)
    li      t1, 1
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)

halt:
    j       halt

    .section .rodata
hp_message:
    .asciz "HP_SMOKE_READY\n"
