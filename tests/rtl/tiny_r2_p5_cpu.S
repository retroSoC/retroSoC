.section .text
.global _start
.option norvc
_start:
    # Verification-only slow ROM. Copy this position-independent image to SRAM.
    la t0, _start
    la t1, image_end
    li t2, 0x30000000
1:  lw t3, 0(t0)
    sw t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    bltu t0, t1, 1b
    fence.i
    la t0, sram_main
    li t1, 0x30000000
    add t0, t0, t1
    jr t0
sram_main:
    li sp, 0x3001f000
    li s0, 0x1000a100
    li s1, 0x1000b000
    li s2, 0x3001ffe0
    lw t0, 0x40(s1)
    bnez t0, mapped_done
    li t0, 0x30010000
    li t1, 256
    li t2, 0x12345678
2:  sw t2, 0(t0)
    addi t0, t0, 4
    addi t2, t2, 1
    addi t1, t1, -1
    bnez t1, 2b
    li t0, 0xe0
    sw t0, 4(s0)
    li t0, 0x30010000
    sw t0, 8(s0)
    li t0, 0x30018000
    sw t0, 12(s0)
    li t0, 1024
    sw t0, 16(s0)
    sw zero, 20(s0)
    li t0, 16
    sw t0, 24(s0)
    li t0, 1
    sw t0, 0(s0)
    jal ra, wait_dma
    li t0, 0x30018000
    li t1, 256
    li t2, 0x12345678
3:  lw t3, 0(t0)
    bne t3, t2, fail
    addi t0, t0, 4
    addi t2, t2, 1
    addi t1, t1, -1
    bnez t1, 3b
    # Start an XPI read whose response is withheld by the boundary model.
    li t0, 0x50000000
    sw t0, 8(s0)
    li t0, 0x10009040
    sw t0, 12(s0)
    li t0, 0x60
    sw t0, 4(s0)
    li t0, 4
    sw t0, 16(s0)
    li t0, 1
    sw t0, 0(s0)
    li t0, 0x30008000
    li t1, 64
4:  sw t1, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 4b
    li t0, 1
    sw t0, 0x40(s1)
    lw t1, 0x40(s1)
    bne t0, t1, fail
    sw t0, 0(s2)
    # The debugger resets this hart while DMA/XPI stays owned. PERF_CTRL is
    # retained by SYSCTRL and selects the resume path after the ROM copy.
5:  lw t1, 0x40(s1)
    li t0, 1
    bne t0, t1, fail
    j 5b
mapped_done:
    jal ra, wait_dma
    li t0, 0x10009044
    lw t1, 0(t0)
    li t0, 0x40000000
    bne t0, t1, fail
    li t0, 0xe0
    sw t0, 4(s0)
    li t0, 0x30018000
    sw t0, 12(s0)
    li t0, 64
    sw t0, 16(s0)
    sw zero, 0x40(s1)
    li t0, 2
    sw t0, 0(s2)
    li t0, 0x50000100
    sw t0, 8(s0)
    li t0, 1
    sw t0, 0(s0)
    li t1, 128
7:  addi t1, t1, -1
    bnez t1, 7b
    li t0, 8
    sw t0, 0(s0)
    lw t1, 32(s0)
    andi t1, t1, 1
    beqz t1, fail
    li t0, 3
    sw t0, 0(s2)
    li t2, 100000
8:  lw t1, 32(s0)
    andi t0, t1, 1
    beqz t0, 9f
    addi t2, t2, -1
    bnez t2, 8b
    j fail
9:  andi t0, t1, 8
    beqz t0, fail
    li t0, 0x80000001
    sw t0, 0x84(s1)
10: j 10b
wait_dma:
    li t2, 100000
11: lw t1, 32(s0)
    andi t0, t1, 1
    beqz t0, 12f
    addi t2, t2, -1
    bnez t2, 11b
    j fail
12: andi t0, t1, 0x14
    li t1, 4
    bne t0, t1, fail
    ret
fail:
    li t0, 0x1000b084
    li t1, 0x80000000
    sw t1, 0(t0)
13: j 13b
.balign 4
image_end:
