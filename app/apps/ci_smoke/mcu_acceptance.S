/* Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0 */
    .section .text
    .balign 4
    .global rs_mcu_compressed_probe
    .type rs_mcu_compressed_probe,@function
rs_mcu_compressed_probe:
    .option push
    .option rvc
    c.li a0, 21
    c.slli a0, 1
    c.jr ra
    .option pop
    .size rs_mcu_compressed_probe, .-rs_mcu_compressed_probe

    .balign 4
    .global rs_mcu_atomic_probe
    .type rs_mcu_atomic_probe,@function
rs_mcu_atomic_probe:
    /* lr.w a0,(a0): must trap because the Tiny A extension is disabled. */
    .word 0x1005252f
    ret
    .size rs_mcu_atomic_probe, .-rs_mcu_atomic_probe

    .balign 4
    .global rs_mcu_unmapped_probe
    .type rs_mcu_unmapped_probe,@function
rs_mcu_unmapped_probe:
    li a0, 0x38000000
    lw a0, 0(a0)
    ret
    .size rs_mcu_unmapped_probe, .-rs_mcu_unmapped_probe
