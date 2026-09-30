#ifndef RETROSOC_RTTHREAD_BOARD_H
#define RETROSOC_RTTHREAD_BOARD_H

#include <stdint.h>
#include <rtthread.h>

void rs_rtt_start(void);
void rs_rtt_selftest_init(void);
void rs_rtt_fail(uint32_t code);
void rs_rtt_publish(uint32_t event, uint32_t argument, uint32_t sequence);
uint32_t rs_rtt_context_probe(uint64_t value);
rt_err_t rs_rtt_wait_mailbox(rt_int32_t timeout);
void handle_trap(rt_ubase_t cause, rt_ubase_t epc, void *frame);
void rt_trigger_software_interrupt(void);
void rt_hw_do_after_save_above(void);
void rt_hw_console_output(const char *text);
void rt_hw_board_init(void);
void rt_hw_cpu_shutdown(void);

#endif
