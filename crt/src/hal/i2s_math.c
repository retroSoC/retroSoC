#include <stddef.h>

#include <retrosoc/generated/memory_map.h>
#include <retrosoc/hal/i2s.h>

#define RS_I2S_TXDATA_OFFSET UINT32_C(0x01C)
#define RS_I2S_RXDATA_OFFSET UINT32_C(0x020)

uint32_t rs_i2s_pack_stereo16(uint16_t first, uint16_t second) {
    return ((uint32_t)second << 16) | first;
}

void rs_i2s_unpack_stereo16(uint32_t word, uint16_t *first, uint16_t *second) {
    if (first != NULL)
        *first = (uint16_t)word;
    if (second != NULL)
        *second = (uint16_t)(word >> 16);
}

rs_status_t rs_i2s_div_from_hz(uint32_t audio_clock_hz, uint32_t sample_hz, uint32_t sample_bits,
                               uint8_t *sclk_div, uint8_t *lrck_div) {
    uint64_t sclk_hz;
    uint64_t period;

    if ((audio_clock_hz == 0U) || (sample_hz == 0U) || (sclk_div == NULL) || (lrck_div == NULL) ||
        ((sample_bits != 16U) && (sample_bits != 24U))) {
        return RS_EINVAL;
    }

    sclk_hz = (uint64_t)sample_hz * 2U * (uint64_t)sample_bits;
    if ((sclk_hz == 0U) || ((uint64_t)audio_clock_hz % (sclk_hz * 2U) != 0U))
        return RS_EINVAL;
    period = (uint64_t)audio_clock_hz / (sclk_hz * 2U);
    if ((period == 0U) || (period > 256U))
        return RS_EINVAL;
    *sclk_div = (uint8_t)(period - 1U);
    *lrck_div = (uint8_t)(sample_bits - 1U);
    return RS_OK;
}

uintptr_t rs_i2s_txdata_address(void) {
    return RS_SOC_APB4_I2S_BASE + (uintptr_t)RS_I2S_TXDATA_OFFSET;
}

uintptr_t rs_i2s_rxdata_address(void) {
    return RS_SOC_APB4_I2S_BASE + (uintptr_t)RS_I2S_RXDATA_OFFSET;
}
