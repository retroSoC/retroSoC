#include "retrosoc/generated/memory_map.h"

.global _start
_start:
UART_INIT:
    li a4, RS_SOC_RIBP_UART0_BASE
    li a5, 78 # 72 MHz / 921600 baud = 78.125 clocks
    sw a5, 0(a4)
    li a5, 32
    sw a5, 4(a4)
    li a5, 3 # 8 data bits, no parity, one stop bit
    sw a5, 8(a4)
    li a5, 3 # Enable TX and RX
    sw a5, 12(a4)
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
    li a0, 67
INTER_LOOP:
    addi s0, s0, 1
    jal ra, PUTC
    lbu a0, 0(s0)
    bnez a0, INTER_LOOP
CHECK:
    addi t1, t1, 1
    ble t1, t2, APP_LOOP


.equ GPIO_ALT_ENABLE, RS_SOC_RIBP_GPIO_ADMIN_BASE + 0x34
.equ GPIO_ALT_SELECT, RS_SOC_RIBP_GPIO_ADMIN_BASE + 0x38
.equ BIT_MASK,        0x3FE00000  # Bits 21 to 29 set to 1
.equ PSRAM_INIT,      RS_SOC_RIBP_PSRAM_BASE + 0x08
PINMUX_PSRAM:
    li t0, GPIO_ALT_ENABLE
    lw t1, 0(t0)
    li t2, BIT_MASK
    or t1, t1, t2
    sw t1, 0(t0)
    li t0, GPIO_ALT_SELECT
    lw t1, 0(t0)
    or t1, t1, t2
    sw t1, 0(t0)
PSRAM_INIT_TRG:
    li t0, PSRAM_INIT
    li t1, 1
    sw t1, 0(t0)

# NEW ===========================
    la a0, 0x0
    la a1, 2000
WAIT_PSRAM_RESET:
    lw   t0, 0(a0)
    addi a0, a0, 4
    blt  a0, a1, WAIT_PSRAM_RESET

LDSD_TEST:
    jal ra, WR_8B_TEST
    jal ra, RD_8B_TEST
    jal ra, WR_16B_TEST
    jal ra, RD_16B_TEST
    jal ra, WR_32B_TEST
    jal ra, RD_32B_TEST
    j TEST_SUCCESS

WR_8B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
WR_8B_LOOP:
    sb t2, 0(t0)
    addi t2, t2, 1
    addi t0, t0, 1
    blt t0, t1, WR_8B_LOOP
    ret

WR_16B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
WR_16B_LOOP:
    sh t2, 0(t0)
    addi t2, t2, 1
    addi t0, t0, 2
    blt t0, t1, WR_16B_LOOP
    ret

WR_32B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
WR_32B_LOOP:
    sw t2, 0(t0)
    addi t2, t2, 1
    addi t0, t0, 4
    blt t0, t1, WR_32B_LOOP
    ret


RD_8B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
RD_8B_LOOP:
    lb t3, 0(t0)
    bne t2, t3, TEST_FAIL
    addi t0, t0, 1
    addi t2, t2, 1
    blt t0, t1, RD_8B_LOOP
    ret

RD_16B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
RD_16B_LOOP:
    lh t3, 0(t0)
    bne t2, t3, TEST_FAIL
    addi t0, t0, 2
    addi t2, t2, 1
    blt t0, t1, RD_16B_LOOP
    ret

RD_32B_TEST:
    li t0, 0x40000000
    li t1, 0x40000010
    li t2, 1
RD_32B_LOOP:
    lw t3, 0(t0)
    bne t2, t3, TEST_FAIL
    addi t0, t0, 4
    addi t2, t2, 1
    blt t0, t1, RD_32B_LOOP
    ret


TEST_FAIL:
    la s0, msg_fail
    li a0, 77
TEST_FAIL_LOOP:
    addi s0, s0, 1
    jal ra, PUTC
    lbu a0, 0(s0)
    bnez a0, TEST_FAIL_LOOP
    li t0, 0x1000B084
    li t1, 0x80000100
    sw t1, 0(t0)
    j END


TEST_SUCCESS:
    la s0, msg_succ
    li a0, 77
TEST_SUCCESS_LOOP:
    addi s0, s0, 1
    jal ra, PUTC
    lbu a0, 0(s0)
    bnez a0, TEST_SUCCESS_LOOP
    li t0, 0x1000B084
    li t1, 0x80000001
    sw t1, 0(t0)

END:
    j END

PUTC:
    li a4, RS_SOC_RIBP_UART0_BASE
    sw a0, 16(a4)
    ret

.section .data
msg_hello: .string "Hello retroSoC!\n"
msg_luck: .string "Clock in luck, reset doubts\n"
msg_succ: .string "Mem wr/rd test success\n"
msg_fail: .string "Mem wr/rd test fail\n"
