    .section .init
    .globl _start
_start:
    la sp, _stack_point
    call main
1:
    j 1b
