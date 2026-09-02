#ifndef RETROSOC_HAL_APU_H
#define RETROSOC_HAL_APU_H

#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/apu_regs.h>

typedef struct {
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability0;
    uint32_t capability1;
    uint32_t abi_digest;
} rs_apu_info_t;

rs_status_t rs_apu_probe(rs_apu_info_t *info);

#endif
