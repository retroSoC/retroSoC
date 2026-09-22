    .section .text.start
    .global _start
    .type _start, @function

_start:
    la      sp, __stack_top
    la      t0, hp_trap_handler
    csrw    mtvec, t0
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main
3:
    j       3b

    .align 2
    .global hp_trap_handler
    .type hp_trap_handler, @function

/* Minimal M-mode trap handler for the LP-only-register store probe. Records
 * mcause/mepc/mtval and bumps the observation count in hp_fault_record, then
 * redirects mepc to the hp_probe_recover landing pad instead of skipping the
 * faulting instruction: an imprecise store-fault mepc must not corrupt an
 * innocent later instruction. */
hp_trap_handler:
    csrw    mscratch, t0
    la      t0, hp_fault_record
    sw      t1, 16(t0)
    csrr    t1, mcause
    sw      t1, 0(t0)
    csrr    t1, mepc
    sw      t1, 4(t0)
    csrr    t1, mtval
    sw      t1, 8(t0)
    lw      t1, 12(t0)
    addi    t1, t1, 1
    sw      t1, 12(t0)
    la      t1, hp_probe_recover
    csrw    mepc, t1
    lw      t1, 16(t0)
    csrr    t0, mscratch
    mret
