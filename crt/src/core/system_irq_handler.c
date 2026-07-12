#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/arch/riscv/system_csr.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/lib/printf.h>

#define RS_EXCEPTION_COUNT 16U
#define RS_CORE_IRQ_COUNT 12U
#define RS_EXTERNAL_IRQ_COUNT 30U

static rs_trap_handler_t exception_handlers[RS_EXCEPTION_COUNT];
static rs_trap_handler_t core_irq_handlers[RS_CORE_IRQ_COUNT];

static void rs_default_exception(uintptr_t mcause, uintptr_t stack_pointer) {
    printf("trap exception mcause=0x%lx sp=0x%lx\n", (unsigned long)mcause,
           (unsigned long)stack_pointer);
    for (;;) {
    }
}

static void rs_default_interrupt(uintptr_t mcause, uintptr_t stack_pointer) {
    printf("trap interrupt mcause=0x%lx sp=0x%lx\n", (unsigned long)mcause,
           (unsigned long)stack_pointer);
}

static void rs_irq_init_tables(void) {
    for (uint32_t index = 0U; index < RS_EXCEPTION_COUNT; ++index) {
        exception_handlers[index] = rs_default_exception;
    }
    for (uint32_t index = 0U; index < RS_CORE_IRQ_COUNT; ++index) {
        core_irq_handlers[index] = rs_default_interrupt;
    }
}

rs_status_t rs_irq_register_exception(uint32_t id, rs_trap_handler_t handler) {
    if ((id >= RS_EXCEPTION_COUNT) || (handler == NULL)) {
        return RS_EINVAL;
    }
    exception_handlers[id] = handler;
    return RS_OK;
}

rs_status_t rs_irq_register_core(uint32_t id, rs_trap_handler_t handler) {
    if ((id >= RS_CORE_IRQ_COUNT) || (handler == NULL)) {
        return RS_EINVAL;
    }
    core_irq_handlers[id] = handler;
    return RS_OK;
}

rs_status_t rs_irq_register_external(uint32_t id, rs_trap_handler_t handler) {
    if ((id >= RS_EXTERNAL_IRQ_COUNT) || (handler == NULL)) {
        return RS_EINVAL;
    }

    /* No PLIC claim/complete path is present in this SoC configuration. */
    return RS_ENOTSUP;
}

rs_status_t rs_irq_enable_core(uint32_t id, rs_trap_handler_t handler) {
    const rs_status_t status = rs_irq_register_core(id, handler);

    if (status != RS_OK) {
        return status;
    }
    switch (id) {
    case IRQ_M_SOFT:
        __enable_sw_irq();
        break;
    case IRQ_M_TIMER:
        __enable_timer_irq();
        break;
    default:
        return RS_ENOTSUP;
    }
    return RS_OK;
}

uint32_t system_trap_handler(uintptr_t mcause, uintptr_t stack_pointer) {
    const uint32_t id = (uint32_t)(mcause & 0x00000fffU);

    if ((mcause & (uintptr_t)MCAUSE_INTERRUPT) != 0U) {
        if (id == IRQ_M_EXT) {
            rs_default_interrupt(mcause, stack_pointer);
        } else if (id < RS_CORE_IRQ_COUNT) {
            core_irq_handlers[id](mcause, stack_pointer);
        } else {
            rs_default_interrupt(mcause, stack_pointer);
        }
    } else if (id < RS_EXCEPTION_COUNT) {
        exception_handlers[id](mcause, stack_pointer);
    } else {
        rs_default_exception(mcause, stack_pointer);
    }
    return 0U;
}

void _premain_init(void) {
    rs_irq_init_tables();
    __enable_all_counter();
}
