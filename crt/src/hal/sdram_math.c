#include <stddef.h>

#include <retrosoc/hal/sdram.h>

#define RS_NANOSECONDS_PER_SECOND UINT64_C(1000000000)
#define RS_SDRAM_TRP_NS           UINT32_C(20)
#define RS_SDRAM_TRCD_NS          UINT32_C(20)
#define RS_SDRAM_TRAS_NS          UINT32_C(44)
#define RS_SDRAM_TRC_NS           UINT32_C(66)
#define RS_SDRAM_TWR_NS           UINT32_C(15)
#define RS_SDRAM_TRFC_NS          UINT32_C(66)
#define RS_SDRAM_TXSR_NS          UINT32_C(66)
#define RS_SDRAM_TREFI_NS         UINT32_C(7800)
#define RS_SDRAM_POWERUP_NS       UINT32_C(100000)
#define RS_SDRAM_TRRD_TCK         UINT8_C(2)
#define RS_SDRAM_TWTR_TCK         UINT8_C(2)
#define RS_SDRAM_TRTP_TCK         UINT8_C(1)
#define RS_SDRAM_TMRD_TCK         UINT8_C(2)

static bool rs_sdram_ceil_cycles(uint32_t frequency_hz, uint32_t nanoseconds, uint32_t *cycles) {
    uint64_t numerator;
    uint64_t result;

    numerator = ((uint64_t)frequency_hz * (uint64_t)nanoseconds) +
                (RS_NANOSECONDS_PER_SECOND - UINT64_C(1));
    result = numerator / RS_NANOSECONDS_PER_SECOND;
    if ((result == UINT64_C(0)) || (result > UINT32_MAX)) {
        return false;
    }
    *cycles = (uint32_t)result;
    return true;
}

static rs_status_t rs_sdram_store_u8(uint32_t value, uint8_t *out) {
    if (value > UINT8_MAX) {
        return RS_EINVAL;
    }
    *out = (uint8_t)value;
    return RS_OK;
}

static rs_status_t rs_sdram_store_u16(uint32_t value, uint16_t *out) {
    if (value > UINT16_MAX) {
        return RS_EINVAL;
    }
    *out = (uint16_t)value;
    return RS_OK;
}

static uint32_t rs_sdram_max_u32(uint32_t left, uint32_t right) {
    return (left > right) ? left : right;
}

rs_status_t rs_sdram_timing_from_hz(uint32_t source_clock_hz, uint8_t clkdiv,
                                    rs_sdram_timing_t *timing) {
    uint32_t divider;
    uint32_t sdram_hz;
    uint32_t trp;
    uint32_t trcd;
    uint32_t tras;
    uint32_t trc;
    uint32_t twr;
    uint32_t trfc;
    uint32_t txsr;
    uint32_t trefi;
    uint32_t powerup;

    if ((source_clock_hz == 0U) || (clkdiv > 3U) || (timing == NULL)) {
        return RS_EINVAL;
    }

    divider = (uint32_t)clkdiv + 1U;
    if ((source_clock_hz / divider) < 2U) {
        return RS_EINVAL;
    }
    sdram_hz = source_clock_hz / (divider * 2U);
    if (sdram_hz == 0U) {
        return RS_EINVAL;
    }

    if (!rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TRP_NS, &trp) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TRCD_NS, &trcd) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TRAS_NS, &tras) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TRC_NS, &trc) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TWR_NS, &twr) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TRFC_NS, &trfc) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TXSR_NS, &txsr) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_TREFI_NS, &trefi) ||
        !rs_sdram_ceil_cycles(sdram_hz, RS_SDRAM_POWERUP_NS, &powerup)) {
        return RS_EINVAL;
    }

    if ((rs_sdram_store_u8(trp, &timing->trp_cycles) != RS_OK) ||
        (rs_sdram_store_u8(trcd, &timing->trcd_cycles) != RS_OK) ||
        (rs_sdram_store_u8(tras, &timing->tras_cycles) != RS_OK) ||
        (rs_sdram_store_u8(trc, &timing->trc_cycles) != RS_OK) ||
        (rs_sdram_store_u8(twr, &timing->twr_cycles) != RS_OK) ||
        (rs_sdram_store_u8(trfc, &timing->trfc_cycles) != RS_OK) ||
        (rs_sdram_store_u8(rs_sdram_max_u32((uint32_t)RS_SDRAM_TRRD_TCK, 1U),
                           &timing->trrd_cycles) != RS_OK) ||
        (rs_sdram_store_u8(rs_sdram_max_u32((uint32_t)RS_SDRAM_TWTR_TCK, 1U),
                           &timing->twtr_cycles) != RS_OK) ||
        (rs_sdram_store_u8(rs_sdram_max_u32((uint32_t)RS_SDRAM_TRTP_TCK, 1U),
                           &timing->trtp_cycles) != RS_OK) ||
        (rs_sdram_store_u8(rs_sdram_max_u32((uint32_t)RS_SDRAM_TMRD_TCK, 1U),
                           &timing->tmrd_cycles) != RS_OK) ||
        (rs_sdram_store_u8(txsr, &timing->txsr_cycles) != RS_OK) ||
        (rs_sdram_store_u16(trefi, &timing->trefi_cycles) != RS_OK) ||
        (rs_sdram_store_u16(powerup, &timing->powerup_cycles) != RS_OK)) {
        return RS_EINVAL;
    }
    timing->actual_sdram_hz = sdram_hz;
    return RS_OK;
}
