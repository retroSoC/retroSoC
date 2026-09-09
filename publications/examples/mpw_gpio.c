#include <retrosoc/hal/user_ip.h>

/* MPW only: slot 2. Establish data while output enables are clear. */
rs_status_t rs_example_mpw_gpio(uint32_t mask, uint32_t value, uint32_t *input)
{
    uint32_t identifier;
    rs_status_t status = rs_user_ip_probe(2U, &identifier);
    if (status != RS_OK) {
        return status;
    }
    if (identifier != 2U) {
        return RS_EFORMAT;
    }
    status = rs_user_ip_write(0x04U, 0U);
    if (status == RS_OK) {
        status = rs_user_ip_write(0x08U, value);
    }
    if (status == RS_OK) {
        status = rs_user_ip_write(0x04U, mask);
    }
    return status == RS_OK ? rs_user_ip_read(0x0CU, input) : status;
}
