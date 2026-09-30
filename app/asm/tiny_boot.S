/* Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0 */
#include "retrosoc/generated/memory_map.h"

/* Small gate-level acceptance image. Executes through the real XPI pins,
 * checks both ends of SRAM and byte strobes, then checks APB/UART/SYSCTRL.
 * The full SDK/application acceptance runs separately in both RTL simulators. */
    .section .text
    .global _start
_start:
    li t0, RS_SOC_SRAM_BASE
    li t1, 0x12345678
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, failed
    li t0, RS_SOC_SRAM_END - 3
    sw t1, 0(t0)
    li t2, 0xab
    sb t2, 1(t0)
    lw t2, 0(t0)
    li t1, 0x1234ab78
    bne t1, t2, failed

    li s0, RS_SOC_APB4_UART0_BASE
    li t0, 26
    sw t0, 0(s0)
    li t0, 11
    sw t0, 4(s0)
    li t0, 3
    sw t0, 8(s0)
    sw t0, 12(s0)
    la s1, message
print_loop:
    lbu s2, 0(s1)
    beqz s2, passed
wait_uart:
    lw t0, 24(s0)
    andi t0, t0, 32
    bnez t0, wait_uart
    sw s2, 16(s0)
    addi s1, s1, 1
    j print_loop
passed:
    /* Let the serial output drain before setting the terminal verdict. */
    lw t0, 24(s0)
    andi t0, t0, 4
    bnez t0, passed
    li t0, RS_SOC_APB4_SYSCTRL_BASE
    li t1, 0x80000001
    sw t1, RS_SOC_SYSCTRL_TEST_STATUS_OFFSET(t0)
halt:
    j halt
failed:
    li t0, RS_SOC_APB4_SYSCTRL_BASE
    li t1, 0x80000100
    sw t1, RS_SOC_SYSCTRL_TEST_STATUS_OFFSET(t0)
    j halt
message:
    .asciz "Hello retroSoC! Tiny netlist boot\n"
