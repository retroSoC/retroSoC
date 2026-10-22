#include <retrosoc/hal/spi.h>

rs_status_t rs_spi_divider_from_hz(uint32_t pclk_hz, uint32_t requested_sck_hz, uint32_t *divider,
                                   uint32_t *actual_sck_hz) {
    uint64_t denominator;
    uint32_t value;

    if ((divider == NULL) || (actual_sck_hz == NULL) || (pclk_hz == 0U) ||
        (requested_sck_hz == 0U)) {
        return RS_EINVAL;
    }
    denominator = (uint64_t)requested_sck_hz * UINT64_C(2);
    value = (uint32_t)(((uint64_t)pclk_hz + denominator - UINT64_C(1)) / denominator);
    if ((value == 0U) || (value > UINT32_C(65535))) {
        return RS_ENOTSUP;
    }
    *divider = value;
    *actual_sck_hz = pclk_hz / (value * UINT32_C(2));
    return RS_OK;
}
