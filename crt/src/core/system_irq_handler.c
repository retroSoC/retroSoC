#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/arch/riscv/system_csr.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/generated/irq_metadata.h>
#include <retrosoc/lib/printf.h>

#define RS_EXCEPTION_COUNT    16U
#define RS_CORE_IRQ_COUNT     12U
#define RS_EXTERNAL_IRQ_COUNT RS_SOC_EXTERNAL_IRQ_COUNT

_Static_assert(RS_EXTERNAL_IRQ_COUNT == RS_SOC_EXTERNAL_IRQ_COUNT,
               "generated external IRQ count mismatch");

static rs_trap_handler_t exception_handlers[RS_EXCEPTION_COUNT];
static rs_trap_handler_t core_irq_handlers[RS_CORE_IRQ_COUNT];
static rs_trap_handler_t external_irq_handlers[RS_EXTERNAL_IRQ_COUNT];
static uint8_t external_irq_priorities[RS_EXTERNAL_IRQ_COUNT];

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
    for (uint32_t index = 0U; index < RS_EXTERNAL_IRQ_COUNT; ++index) {
        external_irq_handlers[index] = NULL;
        external_irq_priorities[index] = UINT8_MAX;
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

    external_irq_handlers[id] = handler;
    return RS_OK;
}

static uint32_t rs_irq_array_access(uint32_t index, uint32_t payload) {
    return (index & UINT32_C(0x7f)) | (payload << 16U);
}

rs_status_t rs_irq_enable_external(uint32_t id, rs_trap_handler_t handler) {
    rs_status_t status;

    status = rs_irq_register_external(id, handler);
    if (status != RS_OK) {
        return status;
    }
    if (external_irq_priorities[id] == UINT8_MAX) {
        status = rs_irq_set_external_priority(id, UINT8_C(1));
        if (status != RS_OK) {
            return status;
        }
    }
    (void)__RV_CSR_READ_SET(CSR_HAZARD3_MEIEA,
                            rs_irq_array_access(id >> 4U, UINT32_C(1) << (id & 0xfU)));
    __enable_ext_irq();
    return RS_OK;
}

rs_status_t rs_irq_disable_external(uint32_t id) {
    if (id >= RS_EXTERNAL_IRQ_COUNT) {
        return RS_EINVAL;
    }
    (void)__RV_CSR_READ_CLEAR(CSR_HAZARD3_MEIEA,
                              rs_irq_array_access(id >> 4U, UINT32_C(1) << (id & 0xfU)));
    return RS_OK;
}

rs_status_t rs_irq_set_external_priority(uint32_t id, uint8_t priority) {
    const uint32_t field = id & UINT32_C(0x3);
    const uint32_t field_shift = field * 4U;
    const uint32_t field_mask = UINT32_C(0xf) << field_shift;
    const uint32_t encoded = ((uint32_t)priority << 2U) << field_shift;

    if ((id >= RS_EXTERNAL_IRQ_COUNT) || (priority > UINT8_C(3))) {
        return RS_EINVAL;
    }
    (void)__RV_CSR_READ_CLEAR(CSR_HAZARD3_MEIPRA, rs_irq_array_access(id >> 2U, field_mask));
    (void)__RV_CSR_READ_SET(CSR_HAZARD3_MEIPRA, rs_irq_array_access(id >> 2U, encoded));
    external_irq_priorities[id] = priority;
    return RS_OK;
}

static void rs_irq_dispatch_external(uintptr_t mcause, uintptr_t stack_pointer) {
    const rv_csr_t saved_context = __RV_CSR_READ_SET(CSR_HAZARD3_MEICONTEXT, UINT32_C(0x2));
    const uint32_t next = (uint32_t)__RV_CSR_READ_SET(CSR_HAZARD3_MEINEXT, UINT32_C(0x1));
    const uint32_t id = (next >> 2U) & UINT32_C(0x1ff);

    if (((next & UINT32_C(0x80000000)) == 0U) && (id < RS_EXTERNAL_IRQ_COUNT)) {
        rs_trap_handler_t handler = external_irq_handlers[id];
        if (handler == NULL) {
            (void)__RV_CSR_READ_CLEAR(CSR_HAZARD3_MEIEA,
                                      rs_irq_array_access(id >> 4U, UINT32_C(1) << (id & 0xfU)));
        } else {
            handler(mcause, stack_pointer);
        }
    }
    __RV_CSR_WRITE(CSR_HAZARD3_MEICONTEXT, saved_context);
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
            rs_irq_dispatch_external(mcause, stack_pointer);
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
