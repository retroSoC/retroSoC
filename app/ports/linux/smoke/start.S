    .section .text.start
    .global _start
    .type _start, @function

    .equ UART1_BASE,       0x10018000
    .equ UART_BAUD_INT,    0x00
    .equ UART_BAUD_FRAC,   0x04
    .equ UART_LINE_CTRL,   0x08
    .equ UART_CTRL,        0x0c
    .equ UART_TXDATA,      0x10
    .equ UART_STATUS,      0x18
    .equ UART_FIFO_CTRL,   0x20
    .equ UART_ERROR,       0x30
    .equ UART_INTR_ENABLE, 0x38
    .equ UART_TX_FULL,     0x20

    .equ MAILBOX_BASE,     0x10019000
    .equ HP_EVENT,         0x20
    .equ HP_ARG0,          0x24
    .equ HP_SEQUENCE,      0x28
    .equ HP_DOORBELL,      0x2c
    .equ HP_READY_ARG,     0x4c4e5801
    .equ LP_COMMAND,       0x10
    .equ LP_ARG0,          0x14
    .equ LP_SEQUENCE,      0x18
    .equ HP_GA2D_START,    0x47413250
    .equ HP_GA2D_ARG,      0x47413244
    .equ HP_GA2D_PASS,     2
    .equ HP_GA2D_FAIL,     3
    .equ HP_GA2D_CACHE,    4
    .equ HP_GA2D_CACHE_ARG, 0x43424f4b

    .equ GA2D_BASE,        0x10012000
    .equ GA2D_COMMAND,     0x10
    .equ GA2D_STATUS,      0x14
    .equ GA2D_IRQ_STATE,   0x18
    .equ GA2D_ERROR_STATUS, 0x24
    .equ GA2D_JOB_CONFIG,  0x30
    .equ GA2D_GLOBAL_ALPHA, 0x34
    .equ GA2D_COLOR,       0x38
    .equ GA2D_SIZE,        0x3c
    .equ GA2D_FG_ADDRESS,  0x40
    .equ GA2D_FG_PITCH,    0x44
    .equ GA2D_FG_FORMAT,   0x48
    .equ GA2D_BG_ADDRESS,  0x4c
    .equ GA2D_BG_PITCH,    0x50
    .equ GA2D_BG_FORMAT,   0x54
    .equ GA2D_DST_ADDRESS, 0x58
    .equ GA2D_DST_PITCH,   0x5c
    .equ GA2D_DST_FORMAT,  0x60

    .equ RESOURCE_CTRL_BASE, 0x2000a000
    .equ RESOURCE_CACHE_CONTROL, 0x10
    .equ GA2D_WIDTH,       8
    .equ GA2D_PITCH,       64
    .equ GA2D_SIZE_VALUE,  0x00010008
    .equ GA2D_XRGB8888,    2
    .equ GA2D_WAIT_POLLS,  0x00100000

_start:
    li      t0, UART1_BASE
    sw      zero, UART_CTRL(t0)
    li      t1, 3
    sw      t1, UART_FIFO_CTRL(t0)
    li      t1, 0x7f
    sw      t1, UART_ERROR(t0)
    sw      zero, UART_INTR_ENABLE(t0)
    li      t1, 78
    sw      t1, UART_BAUD_INT(t0)
    li      t1, 32
    sw      t1, UART_BAUD_FRAC(t0)
    li      t1, 3
    sw      t1, UART_LINE_CTRL(t0)
    sw      t1, UART_CTRL(t0)

    la      a0, hp_message
write_character:
    lbu     a1, 0(a0)
    beqz    a1, publish_ready
wait_tx_space:
    lw      a2, UART_STATUS(t0)
    andi    a2, a2, UART_TX_FULL
    bnez    a2, wait_tx_space
    sw      a1, UART_TXDATA(t0)
    addi    a0, a0, 1
    j       write_character

publish_ready:
    li      t0, MAILBOX_BASE
    li      t1, 1
    sw      t1, HP_EVENT(t0)
    li      t1, HP_READY_ARG
    sw      t1, HP_ARG0(t0)
    li      t1, 1
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)

wait_start_command:
    li      s1, GA2D_WAIT_POLLS
wait_start_command_loop:
    li      t0, MAILBOX_BASE
    lw      t1, LP_SEQUENCE(t0)
    li      t2, 1
    bne     t1, t2, wait_start_command_next
    lw      t1, LP_COMMAND(t0)
    li      t2, HP_GA2D_START
    bne     t1, t2, wait_start_command_next
    lw      t1, LP_ARG0(t0)
    li      t2, HP_GA2D_ARG
    beq     t1, t2, start_ga2d
wait_start_command_next:
    addi    s1, s1, -1
    bnez    s1, wait_start_command_loop
    j       publish_ga2d_fail

start_ga2d:
    jal     ra, prepare_shared_lines
    jal     ra, clean_shared_lines
    jal     ra, ga2d_fill
    beqz    a0, publish_ga2d_fail
    jal     ra, invalidate_shared_lines
    jal     ra, check_fill
    beqz    a0, publish_ga2d_fail

    la      a0, hp_destination_line
    li      a1, 0xc7c7c7c7
    li      a2, 16
    jal     ra, fill_words
    jal     ra, clean_shared_lines
    jal     ra, ga2d_copy
    beqz    a0, publish_ga2d_fail
    jal     ra, invalidate_shared_lines
    jal     ra, check_copy
    beqz    a0, publish_ga2d_fail

publish_ga2d_pass:
    li      t0, MAILBOX_BASE
    li      t1, HP_GA2D_PASS
    sw      t1, HP_EVENT(t0)
    li      t1, HP_GA2D_ARG
    sw      t1, HP_ARG0(t0)
    li      t1, 2
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)

wait_cache_request:
    li      s1, GA2D_WAIT_POLLS
wait_cache_request_loop:
    li      t0, RESOURCE_CTRL_BASE
    lw      t1, RESOURCE_CACHE_CONTROL(t0)
    andi    t1, t1, 2
    bnez    t1, clean_cache_request
    addi    s1, s1, -1
    bnez    s1, wait_cache_request_loop
    j       publish_cache_fail

clean_cache_request:
    jal     ra, clean_invalidate_shared_lines
    li      t0, MAILBOX_BASE
    li      t1, HP_GA2D_CACHE
    sw      t1, HP_EVENT(t0)
    li      t1, HP_GA2D_CACHE_ARG
    sw      t1, HP_ARG0(t0)
    li      t1, 3
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)
    j       halt

publish_cache_fail:
    li      t0, MAILBOX_BASE
    li      t1, HP_GA2D_FAIL
    sw      t1, HP_EVENT(t0)
    li      t1, 0xdead0002
    sw      t1, HP_ARG0(t0)
    li      t1, 3
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)
    j       halt

publish_ga2d_fail:
    li      t0, MAILBOX_BASE
    li      t1, HP_GA2D_FAIL
    sw      t1, HP_EVENT(t0)
    li      t1, 0xdead0001
    sw      t1, HP_ARG0(t0)
    li      t1, 2
    sw      t1, HP_SEQUENCE(t0)
    fence   w, w
    sw      t1, HP_DOORBELL(t0)

halt:
    j       halt

fill_words:
    sw      a1, 0(a0)
    addi    a0, a0, 4
    addi    a2, a2, -1
    bnez    a2, fill_words
    ret

prepare_shared_lines:
    mv      s0, ra
    la      a0, hp_source_guard
    li      a1, 0xa5a5a5a5
    li      a2, 16
    jal     ra, fill_words
    la      a0, hp_destination_guard
    li      a1, 0xd3d3d3d3
    li      a2, 16
    jal     ra, fill_words
    la      a0, hp_source_line
    li      a1, 0xa5a5a5a5
    li      a2, 16
    jal     ra, fill_words
    la      a0, hp_destination_line
    li      a1, 0xc7c7c7c7
    li      a2, 16
    jal     ra, fill_words
    la      t0, hp_source_line
    li      t1, 0x10203040
    li      t2, 0x01020304
    li      t3, 8
prepare_source_data:
    sw      t1, 0(t0)
    add     t1, t1, t2
    addi    t0, t0, 4
    addi    t3, t3, -1
    bnez    t3, prepare_source_data
    mv      ra, s0
    ret

clean_shared_lines:
    la      a0, hp_source_guard
    cbo.clean 0(a0)
    la      a0, hp_source_line
    cbo.clean 0(a0)
    la      a0, hp_destination_line
    cbo.clean 0(a0)
    la      a0, hp_destination_guard
    cbo.clean 0(a0)
    fence   rw, rw
    ret

invalidate_shared_lines:
    la      a0, hp_source_guard
    cbo.inval 0(a0)
    la      a0, hp_source_line
    cbo.inval 0(a0)
    la      a0, hp_destination_line
    cbo.inval 0(a0)
    la      a0, hp_destination_guard
    cbo.inval 0(a0)
    fence   r, r
    ret

clean_invalidate_shared_lines:
    mv      s0, ra
    jal     ra, clean_shared_lines
    jal     ra, invalidate_shared_lines
    mv      ra, s0
    ret

ga2d_fill:
    li      t0, GA2D_BASE
    li      t1, 7
    sw      t1, GA2D_IRQ_STATE(t0)
    li      t1, 1
    sw      t1, GA2D_ERROR_STATUS(t0)
    sw      zero, GA2D_JOB_CONFIG(t0)
    sw      zero, GA2D_GLOBAL_ALPHA(t0)
    li      t1, 0x80123456
    sw      t1, GA2D_COLOR(t0)
    li      t1, GA2D_SIZE_VALUE
    sw      t1, GA2D_SIZE(t0)
    sw      zero, GA2D_FG_ADDRESS(t0)
    sw      zero, GA2D_FG_PITCH(t0)
    sw      zero, GA2D_FG_FORMAT(t0)
    sw      zero, GA2D_BG_ADDRESS(t0)
    sw      zero, GA2D_BG_PITCH(t0)
    sw      zero, GA2D_BG_FORMAT(t0)
    la      t1, hp_destination_line
    sw      t1, GA2D_DST_ADDRESS(t0)
    li      t1, GA2D_PITCH
    sw      t1, GA2D_DST_PITCH(t0)
    li      t1, GA2D_XRGB8888
    sw      t1, GA2D_DST_FORMAT(t0)
    fence   rw, rw
    li      t1, 1
    sw      t1, GA2D_COMMAND(t0)
    j       ga2d_wait

ga2d_copy:
    li      t0, GA2D_BASE
    li      t1, 7
    sw      t1, GA2D_IRQ_STATE(t0)
    li      t1, 1
    sw      t1, GA2D_ERROR_STATUS(t0)
    li      t1, 1
    sw      t1, GA2D_JOB_CONFIG(t0)
    sw      zero, GA2D_GLOBAL_ALPHA(t0)
    sw      zero, GA2D_COLOR(t0)
    li      t1, GA2D_SIZE_VALUE
    sw      t1, GA2D_SIZE(t0)
    la      t1, hp_source_line
    sw      t1, GA2D_FG_ADDRESS(t0)
    li      t1, GA2D_PITCH
    sw      t1, GA2D_FG_PITCH(t0)
    li      t1, GA2D_XRGB8888
    sw      t1, GA2D_FG_FORMAT(t0)
    sw      zero, GA2D_BG_ADDRESS(t0)
    sw      zero, GA2D_BG_PITCH(t0)
    sw      zero, GA2D_BG_FORMAT(t0)
    la      t1, hp_destination_line
    sw      t1, GA2D_DST_ADDRESS(t0)
    li      t1, GA2D_PITCH
    sw      t1, GA2D_DST_PITCH(t0)
    li      t1, GA2D_XRGB8888
    sw      t1, GA2D_DST_FORMAT(t0)
    fence   rw, rw
    li      t1, 1
    sw      t1, GA2D_COMMAND(t0)

ga2d_wait:
    li      t1, GA2D_WAIT_POLLS
ga2d_wait_loop:
    lw      t2, GA2D_STATUS(t0)
    andi    t3, t2, 0x60
    bnez    t3, ga2d_wait_failed
    andi    t3, t2, 0x10
    beqz    t3, ga2d_wait_next
    andi    t3, t2, 0x03
    bnez    t3, ga2d_wait_next
    li      a0, 1
    ret
ga2d_wait_next:
    addi    t1, t1, -1
    bnez    t1, ga2d_wait_loop
ga2d_wait_failed:
    li      a0, 0
    ret

check_fill:
    la      t0, hp_destination_line
    li      t1, 0xff123456
    li      t2, 8
check_fill_pixels:
    lw      t3, 0(t0)
    bne     t3, t1, check_failed
    addi    t0, t0, 4
    addi    t2, t2, -1
    bnez    t2, check_fill_pixels
    lw      t3, 0(t0)
    li      t1, 0xc7c7c7c7
    bne     t3, t1, check_failed
    la      t0, hp_destination_guard
    lw      t3, 0(t0)
    li      t1, 0xd3d3d3d3
    bne     t3, t1, check_failed
    li      a0, 1
    ret

check_copy:
    la      t0, hp_source_line
    la      t1, hp_destination_line
    li      t2, 8
check_copy_pixels:
    lw      t3, 0(t0)
    lw      t4, 0(t1)
    bne     t3, t4, check_failed
    addi    t0, t0, 4
    addi    t1, t1, 4
    addi    t2, t2, -1
    bnez    t2, check_copy_pixels
    lw      t3, 0(t1)
    li      t4, 0xc7c7c7c7
    bne     t3, t4, check_failed
    la      t0, hp_source_guard
    lw      t3, 0(t0)
    li      t4, 0xa5a5a5a5
    bne     t3, t4, check_failed
    la      t0, hp_destination_guard
    lw      t3, 0(t0)
    li      t4, 0xd3d3d3d3
    bne     t3, t4, check_failed
    li      a0, 1
    ret

check_failed:
    li      a0, 0
    ret

    .section .rodata
hp_message:
    .asciz "HP_SMOKE_READY\n"

    .balign 64
hp_source_guard:
    .space 64
    .balign 64
hp_source_line:
    .space 64
    .balign 64
hp_destination_line:
    .space 64
    .balign 64
hp_destination_guard:
    .space 64
