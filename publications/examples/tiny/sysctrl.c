#include <retrosoc/hal/sysctrl.h>
rs_status_t tiny_fault(rs_sysctrl_fault_status_t *status) {
    return rs_sysctrl_get_fault_status(status);
}
