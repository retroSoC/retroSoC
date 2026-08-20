    .section .init
    .globl _start
_start:
    la sp, _stack_point
    la a0, _sbss
    la a1, _ebss
1:
    bgeu a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b
2:
    call main
3:
    ebreak
    j 3b
