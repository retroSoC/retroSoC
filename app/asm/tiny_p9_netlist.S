/* Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0 */
#include "retrosoc/generated/memory_map.h"

/* Compact gate-level DVP check. No hierarchical DUT access or C runtime.
 * Register offsets mirror the frozen GPIO admin and DVP V2 ABI. */
    .section .text
    .global _start
_start:
    li s0, RS_SOC_APB4_GPIO_ADMIN_BASE
    li t0, 0x007ff000
    sw t0, 0x038(s0) /* ALT_SELECT: camera data/clock/sync inputs. */
    sw t0, 0x034(s0) /* ALT_ENABLE */
    sw t0, 0x01c(s0) /* OE_CLEAR */
    li s1, RS_SOC_APB4_DVP_BASE
    lw t0, 0x0f8(s1)
    li t1, 0x00020000
    bne t0, t1, failed
    li t0, 0x00080010
    sw t0, 0x018(s1)
    sw zero, 0x00c(s1)
    li t0, 3
    sw t0, 0x000(s1)
    li s2, 20000
wait_frame:
    lw t0, 0x038(s1)
    bnez t0, failed
    lw t0, 0x024(s1)
    li t1, 1
    beq t0, t1, check_counts
    addi s2, s2, -1
    bnez s2, wait_frame
    j failed
check_counts:
    lw t0, 0x028(s1)
    li t1, 8
    bne t0, t1, failed
    lw t0, 0x02c(s1)
    li t1, 128
    bne t0, t1, failed
    lw t0, 0x030(s1)
    li t1, 64
    bne t0, t1, failed
    lw t0, 0x03c(s1)
    andi t0, t0, 4
    beqz t0, failed
    li a0, 0
read_word:
    lw t0, 0x008(s1)
    andi t0, t0, 4
    bnez t0, failed
    srli t0, a0, 3
    li t1, 3
    mul t0, t0, t1
    andi t1, a0, 7
    slli t1, t1, 2
    add t0, t0, t1
    andi t0, t0, 255
    addi t1, t0, 1
    andi t1, t1, 255
    addi t2, t0, 2
    andi t2, t2, 255
    addi t3, t0, 3
    andi t3, t3, 255
    slli t0, t0, 8
    or t0, t0, t1
    slli t2, t2, 24
    or t0, t0, t2
    slli t3, t3, 16
    or t0, t0, t3
    lw t1, 0x004(s1)
    bne t0, t1, failed
    addi a0, a0, 1
    li t0, 64
    bne a0, t0, read_word
    lw t0, 0x008(s1)
    andi t0, t0, 6
    li t1, 4
    bne t0, t1, failed
    li t1, 0x80000001
    j finish
failed:
    li t1, 0x80000900
finish:
    li t0, RS_SOC_APB4_SYSCTRL_BASE
    sw t1, RS_SOC_SYSCTRL_TEST_STATUS_OFFSET(t0)
halt:
    j halt
