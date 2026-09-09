#include <retrosoc/hal/user_ip.h>

/* MPW only: slot 1, DIV at 0x04 and live COUNT at 0x08. */
rs_status_t rs_example_mpw_timer(uint32_t divider, uint32_t *count)
{
    uint32_t identifier;
    rs_status_t status;
    if (divider > 255U) {
        return RS_EINVAL;
    }
    status = rs_user_ip_probe(1U, &identifier);
    if (status != RS_OK) {
        return status;
    }
    if (identifier != 1U) {
        return RS_EFORMAT;
    }
    status = rs_user_ip_write(0x04U, divider);
    if (status == RS_OK) {
        status = rs_user_ip_write(0x08U, 0U);
    }
    return status == RS_OK ? rs_user_ip_read(0x08U, count) : status;
}
