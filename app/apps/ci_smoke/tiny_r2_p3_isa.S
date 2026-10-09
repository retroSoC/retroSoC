/* Execute independent known-answer instructions and SRAM instruction visibility. */
    .text
    .balign 4
    .global rs_p3_isa_check
    .type rs_p3_isa_check,@function
rs_p3_isa_check:
    mv t6, ra
    li t0, 3
    li t1, 5
    mul t2, t0, t1
    li t3, 15
    bne t2, t3, isa_bad
    div t2, t2, t0
    bne t2, t1, isa_bad
#ifdef __riscv_zbb
    sh1add t2, t0, t1
    li t3, 11
    bne t2, t3, isa_bad
    clz t2, t0
    li t3, 30
    bne t2, t3, isa_bad
    clmul t2, t0, t1
    li t3, 15
    bne t2, t3, isa_bad
    pack t2, t0, t1
    li t3, 0x50003
    bne t2, t3, isa_bad
    bset t2, zero, t0
    li t3, 8
    bne t2, t3, isa_bad
    li t0, 0x76543210
    li t1, 0x10
    xperm4 t2, t0, t1
    bne t2, t1, isa_bad
    li a0, 0
    c.addi a0, 1
    li t3, 1
    bne a0, t3, isa_bad
#endif
    la t0, rs_p3_patch_target
    li t1, 0x00700513
    sw t1, 0(t0)
    .option push
    .option arch, +zifencei
    fence.i
    .option pop
    jalr ra, t0, 0
    li t3, 7
    bne a0, t3, isa_bad
    li a0, 0
    jr t6
isa_bad:
    li a0, 1
    jr t6
    .size rs_p3_isa_check, .-rs_p3_isa_check

    .balign 4
    .global rs_p3_patch_target
    .type rs_p3_patch_target,@function
rs_p3_patch_target:
    .word 0x00000513
    .word 0x00008067
    .size rs_p3_patch_target, .-rs_p3_patch_target
