#ifndef RETROSOC_CORE_IRQ_H
#define RETROSOC_CORE_IRQ_H

#include <stdint.h>

#include <retrosoc/core/status.h>

typedef void (*rs_trap_handler_t)(uintptr_t mcause, uintptr_t stack_pointer);

rs_status_t rs_irq_register_exception(uint32_t id, rs_trap_handler_t handler);
rs_status_t rs_irq_register_core(uint32_t id, rs_trap_handler_t handler);
rs_status_t rs_irq_register_external(uint32_t id, rs_trap_handler_t handler);
rs_status_t rs_irq_enable_core(uint32_t id, rs_trap_handler_t handler);

void irq_test(int argc, char **argv);
uint32_t system_trap_handler(uintptr_t mcause, uintptr_t stack_pointer);
void _premain_init(void);

#endif
