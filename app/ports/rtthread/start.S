    .section .text.start
    .global _start
_start:
    csrw mie, zero
    csrw satp, zero
    li t0, 0x6000
    csrw mstatus, t0
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __rt_rvstack
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    la t0, trap_entry
    csrw mtvec, t0
    csrw mscratch, sp
    call rs_rtt_start
3:
    wfi
    j 3b

    .section .text
    .global rs_rtt_context_probe
rs_rtt_context_probe:
    addi sp, sp, -48
    sd ra, 0(sp)
    sd s0, 8(sp)
    sd s1, 16(sp)
    sd s2, 24(sp)
    sd s3, 32(sp)
    sd a0, 40(sp)
    mv s0, a0
    mv s2, a0
    not s3, a0
    li s1, 8
1:
    li a0, 1
    call rt_thread_delay
    # Compare against memory, so identical truncation of saved registers cannot
    # accidentally satisfy a register-to-register comparison.
    ld t1, 40(sp)
    bne s0, t1, 2f
    bne s2, t1, 2f
    not t0, t1
    bne t0, s3, 2f
    addi s1, s1, -1
    bnez s1, 1b
    li a0, 0
    j 3f
2:
    li a0, 1
3:
    ld ra, 0(sp)
    ld s0, 8(sp)
    ld s1, 16(sp)
    ld s2, 24(sp)
    ld s3, 32(sp)
    addi sp, sp, 48
    ret
