#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/user_ip.h>

#define RS_USER_IP_IDENTIFICATION_OFFSET UINT32_C(0x000)
#define RS_USER_IP_REGISTER_SIZE         UINT32_C(4)

static bool rs_user_ip_offset_valid(uint32_t offset) {
    return ((offset & (RS_USER_IP_REGISTER_SIZE - UINT32_C(1))) == 0U) &&
           (offset <= (RS_SOC_APB4_USER_IP_SIZE - RS_USER_IP_REGISTER_SIZE));
}

static volatile uint32_t *rs_user_ip_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_USER_IP_BASE + offset);
}

rs_status_t rs_user_ip_get_selected(uint8_t *ip_id) {
    return rs_sysctrl_get_ip_select(ip_id);
}

rs_status_t rs_user_ip_select(uint8_t ip_id) {
    return rs_sysctrl_set_ip_select(ip_id);
}

rs_status_t rs_user_ip_probe(uint8_t ip_id, uint32_t *identifier) {
    rs_status_t status;

    if (identifier == NULL) {
        return RS_EINVAL;
    }
    status = rs_user_ip_select(ip_id);
    if (status != RS_OK) {
        return status;
    }
    return rs_user_ip_read(RS_USER_IP_IDENTIFICATION_OFFSET, identifier);
}

rs_status_t rs_user_ip_read(uint32_t offset, uint32_t *value) {
    if ((value == NULL) || !rs_user_ip_offset_valid(offset)) {
        return RS_EINVAL;
    }
    *value = *rs_user_ip_register(offset);
    return RS_OK;
}

rs_status_t rs_user_ip_write(uint32_t offset, uint32_t value) {
    if (!rs_user_ip_offset_valid(offset)) {
        return RS_EINVAL;
    }
    *rs_user_ip_register(offset) = value;
    return RS_OK;
}
