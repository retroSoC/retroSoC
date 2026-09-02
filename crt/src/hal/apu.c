#include <stddef.h>

#include <retrosoc/hal/apu.h>

rs_status_t rs_apu_probe(rs_apu_info_t *info) {
    if (info == NULL) {
        return RS_EINVAL;
    }

    info->ip_id = RS_APU_REG(RS_APU_REG_IP_ID);
    info->version = RS_APU_REG(RS_APU_REG_IP_VERSION);
    info->capability0 = RS_APU_REG(RS_APU_REG_CAPABILITY0);
    info->capability1 = RS_APU_REG(RS_APU_REG_CAPABILITY1);
    info->abi_digest = RS_APU_REG(RS_APU_REG_ABI_DIGEST);

    if ((info->ip_id != RS_APU_IP_ID_VALUE) ||
        ((info->version & RS_APU_IP_VERSION_MAJOR_MASK) != RS_APU_IP_VERSION_VALUE)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}
