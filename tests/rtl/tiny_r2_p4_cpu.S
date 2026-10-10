.section .text
.global _start
.option norvc
_start:
    li sp, 0x3001f000
    la t0, trap
    csrw mtvec, t0
    li s0, 0
    # A C.NOP, followed by a 32-bit ADDI crossing the group boundary, C.RET.
    li s1, 0x30007ffc
    li s2, 3
1:  li t0, 0x05130001
    sw t0, 0(s1)
    li t0, 0x80820090
    sw t0, 4(s1)
    fence.i
    jalr ra, s1, 0
    li t0, 9
    bne a0, t0, fail
    li t0, 0x8000
    add s1, s1, t0
    addi s2, s2, -1
    bnez s2, 1b
    # Instruction-side failure returns to RA via the trap handler.
    li t0, 0x10001000
    jalr ra, t0, 0
    li t0, 1
    bne s0, t0, fail
    # A debugger will patch this code and release the SRAM flag while halted.
    li t0, 0x30000080
    li t1, 0x00100513
    sw t1, 0(t0)
    li t1, 0x00008067
    sw t1, 4(t0)
    li t1, 0x3001ffe0
    sw zero, 0(t1)
    fence.i
    jalr ra, t0, 0
    li t0, 1
    bne a0, t0, fail
    li t0, 0x1000b084
    li t1, 1
    sw t1, 0(t0)
    li t0, 0x3001ffe0
2:  lw t1, 0(t0)
    beqz t1, 2b
    fence.i
    li t0, 0x30000080
    jalr ra, t0, 0
    li t0, 2
    bne a0, t0, fail
    li t0, 0x1000b084
    li t1, 0x80000001
    sw t1, 0(t0)
3:  j 3b
trap:
    csrr t2, mcause
    li t3, 1
    bne t2, t3, fail
    addi s0, s0, 1
    csrw mepc, ra
    mret
fail:
    li t0, 0x1000b084
    li t1, 0x80000000
    sw t1, 0(t0)
4:  j 4b
