#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clint.h>

#define RS_CLINT_MSIP_OFFSET          UINT32_C(0x0000)
#define RS_CLINT_MTIMECMP_OFFSET      UINT32_C(0x4000)
#define RS_CLINT_MTIME_OFFSET         UINT32_C(0xBFF8)
#define RS_CLINT_MSIP_STRIDE          UINT32_C(4)
#define RS_CLINT_MTIMECMP_STRIDE      UINT32_C(8)
#define RS_CLINT_HIGH_WORD_OFFSET     UINT32_C(4)
#define RS_CLINT_SNAPSHOT_ATTEMPTS    UINT32_C(4)
#define RS_CLINT_SOFTWARE_IRQ_PENDING UINT32_C(1)

static volatile uint32_t *rs_clint_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_CLINT_BASE + offset);
}

static bool rs_clint_hart_valid(uint32_t hart) {
    return hart < RS_CLINT_HART_COUNT;
}

static rs_status_t rs_clint_read64(uint32_t offset, uint64_t *value) {
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    if (value == NULL) {
        return RS_EINVAL;
    }
    for (uint32_t attempt = 0U; attempt < RS_CLINT_SNAPSHOT_ATTEMPTS; ++attempt) {
        high_before = *rs_clint_register(offset + RS_CLINT_HIGH_WORD_OFFSET);
        low = *rs_clint_register(offset);
        high_after = *rs_clint_register(offset + RS_CLINT_HIGH_WORD_OFFSET);
        if (high_before == high_after) {
            *value = ((uint64_t)high_after << 32U) | (uint64_t)low;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_clint_get_time(uint64_t *time) {
    return rs_clint_read64(RS_CLINT_MTIME_OFFSET, time);
}

rs_status_t rs_clint_set_time(uint64_t time) {
    *rs_clint_register(RS_CLINT_MTIME_OFFSET + RS_CLINT_HIGH_WORD_OFFSET) = (uint32_t)(time >> 32U);
    *rs_clint_register(RS_CLINT_MTIME_OFFSET) = (uint32_t)time;
    return RS_OK;
}

rs_status_t rs_clint_get_compare(uint32_t hart, uint64_t *compare) {
    if (!rs_clint_hart_valid(hart)) {
        return RS_EINVAL;
    }
    return rs_clint_read64(RS_CLINT_MTIMECMP_OFFSET + (hart * RS_CLINT_MTIMECMP_STRIDE), compare);
}

rs_status_t rs_clint_set_compare(uint32_t hart, uint64_t compare) {
    uint32_t offset;

    if (!rs_clint_hart_valid(hart)) {
        return RS_EINVAL;
    }
    offset = RS_CLINT_MTIMECMP_OFFSET + (hart * RS_CLINT_MTIMECMP_STRIDE);
    *rs_clint_register(offset) = UINT32_MAX;
    *rs_clint_register(offset + RS_CLINT_HIGH_WORD_OFFSET) = (uint32_t)(compare >> 32U);
    *rs_clint_register(offset) = (uint32_t)compare;
    return RS_OK;
}

rs_status_t rs_clint_get_software_interrupt(uint32_t hart, bool *pending) {
    uint32_t offset;

    if (!rs_clint_hart_valid(hart) || (pending == NULL)) {
        return RS_EINVAL;
    }
    offset = RS_CLINT_MSIP_OFFSET + (hart * RS_CLINT_MSIP_STRIDE);
    *pending = (*rs_clint_register(offset) & RS_CLINT_SOFTWARE_IRQ_PENDING) != 0U;
    return RS_OK;
}

rs_status_t rs_clint_set_software_interrupt(uint32_t hart, bool pending) {
    uint32_t offset;

    if (!rs_clint_hart_valid(hart)) {
        return RS_EINVAL;
    }
    offset = RS_CLINT_MSIP_OFFSET + (hart * RS_CLINT_MSIP_STRIDE);
    *rs_clint_register(offset) = pending ? RS_CLINT_SOFTWARE_IRQ_PENDING : 0U;
    return RS_OK;
}
