#include <stdint.h>

#include <retrosoc/core/irq.h>

/* CSR-disabled firmware keeps polling support but has no interrupt backend. */
#ifndef CSR_ENABLE
rs_status_t rs_irq_enable_external(uint32_t id, rs_trap_handler_t handler) {
    (void)id;
    (void)handler;
    return RS_ENOTSUP;
}

rs_status_t rs_irq_disable_external(uint32_t id) {
    (void)id;
    return RS_ENOTSUP;
}

rs_status_t rs_irq_set_external_priority(uint32_t id, uint8_t priority) {
    (void)id;
    (void)priority;
    return RS_ENOTSUP;
}

rs_status_t rs_irq_register_external(uint32_t id, rs_trap_handler_t handler) {
    (void)id;
    (void)handler;
    return RS_ENOTSUP;
}
#endif
