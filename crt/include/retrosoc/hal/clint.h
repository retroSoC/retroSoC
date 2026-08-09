#ifndef RETROSOC_HAL_CLINT_H
#define RETROSOC_HAL_CLINT_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_CLINT_HART_COUNT UINT32_C(1)

#ifndef RS_CLINT_TIMEBASE_HZ
#define RS_CLINT_TIMEBASE_HZ UINT32_C(1000000)
#endif

rs_status_t rs_clint_get_time(uint64_t *time);
rs_status_t rs_clint_set_time(uint64_t time);
rs_status_t rs_clint_get_compare(uint32_t hart, uint64_t *compare);
rs_status_t rs_clint_set_compare(uint32_t hart, uint64_t compare);
rs_status_t rs_clint_get_software_interrupt(uint32_t hart, bool *pending);
rs_status_t rs_clint_set_software_interrupt(uint32_t hart, bool pending);

#endif
