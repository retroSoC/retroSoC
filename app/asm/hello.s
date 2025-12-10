.global _start
_start:
UART_INIT:
    lui a4, 0x10001
    li a5, 625
    sw a5, 0(a4)
HELLO_INIT:
    la s0, msg_hello
    li a0, 72
HELLO_LOOP:
    addi s0, s0, 1
    jal ra, PUTC
    lbu a0, 0(s0)
    bnez a0, HELLO_LOOP

APP_INIT:
    li t1, 1
    li t2, 6
APP_LOOP:
    la s0, msg_luck
    li a0, 72
INTER_LOOP:
    addi s0, s0, 1
    jal ra, PUTC
    lbu a0, 0(s0)
    bnez a0, INTER_LOOP
CHECK:
    addi t1, t1, 1
    ble t1, t2, APP_LOOP
END:
    j END

PUTC:
    lui a4, 0x10001
    sw a0, 4(a4)
    ret

.section .data
msg_hello: .string "Hello retroSoC!\n"
msg_luck: .string "Have a good luck!\n"
