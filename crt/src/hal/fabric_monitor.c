#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/fabric_monitor.h>

#define RS_FABRIC_CONTROL_OFFSET     UINT32_C(0x00C)
#define RS_FABRIC_STATUS_OFFSET      UINT32_C(0x010)
#define RS_FABRIC_FAULT_OFFSET       UINT32_C(0x014)
#define RS_FABRIC_FAULT_ADDR_OFFSET  UINT32_C(0x018)
#define RS_FABRIC_FLUSH_COUNT_OFFSET UINT32_C(0x01C)
#define RS_FABRIC_FAULT_COUNT_OFFSET UINT32_C(0x020)
#define RS_FABRIC_MASTER_BASE        UINT32_C(0x100)
#define RS_FABRIC_TARGET_BASE        UINT32_C(0x300)
#define RS_FABRIC_ENTRY_STRIDE       UINT32_C(0x020)
#define RS_FABRIC_CONTROL_ENABLE     UINT32_C(0x00000001)
#define RS_FABRIC_CONTROL_FREEZE     UINT32_C(0x00000002)
#define RS_FABRIC_CONTROL_CLEAR      UINT32_C(0x00000004)
#define RS_FABRIC_CONTROL_SNAPSHOT   UINT32_C(0x00000008)
#define RS_FABRIC_STATUS_IDLE        UINT32_C(0x00000001)
#define RS_FABRIC_STATUS_RECOVERY    UINT32_C(0x00000002)
#define RS_FABRIC_STATUS_FLUSH_BUSY  UINT32_C(0x00000004)
#define RS_FABRIC_STATUS_READ_SHIFT  8U
#define RS_FABRIC_STATUS_WRITE_SHIFT 16U
#define RS_FABRIC_HIGH_WATER_MASK    UINT32_C(0x00000007)
#define RS_FABRIC_WRITE_HIGH_SHIFT   3U
#define RS_FABRIC_FAULT_WRITE        UINT32_C(0x00000002)
#define RS_FABRIC_FAULT_MASTER_SHIFT 2U
#define RS_FABRIC_FAULT_TARGET_SHIFT 5U
#define RS_FABRIC_FAULT_REASON_SHIFT 8U
#define RS_FABRIC_FAULT_FIELD_MASK   UINT32_C(0x00000007)
#define RS_FABRIC_FAULT_REASON_MASK  UINT32_C(0x0000000F)

static volatile uint32_t *rs_fabric_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_APB4_FABRIC_MONITOR_BASE + (uintptr_t)offset);
}

static uint32_t rs_fabric_control_value(bool enable, bool freeze) {
    uint32_t value = 0U;

    if (enable) {
        value |= RS_FABRIC_CONTROL_ENABLE;
    }
    if (freeze) {
        value |= RS_FABRIC_CONTROL_FREEZE;
    }
    return value;
}

rs_status_t rs_fabric_monitor_configure(bool enable, bool freeze) {
    *rs_fabric_register(RS_FABRIC_CONTROL_OFFSET) = rs_fabric_control_value(enable, freeze);
    return RS_OK;
}

rs_status_t rs_fabric_monitor_clear(void) {
    uint32_t value = *rs_fabric_register(RS_FABRIC_CONTROL_OFFSET);

    value &= RS_FABRIC_CONTROL_ENABLE | RS_FABRIC_CONTROL_FREEZE;
    *rs_fabric_register(RS_FABRIC_CONTROL_OFFSET) = value | RS_FABRIC_CONTROL_CLEAR;
    return RS_OK;
}

rs_status_t rs_fabric_monitor_snapshot(void) {
    uint32_t value = *rs_fabric_register(RS_FABRIC_CONTROL_OFFSET);

    value &= RS_FABRIC_CONTROL_ENABLE | RS_FABRIC_CONTROL_FREEZE;
    *rs_fabric_register(RS_FABRIC_CONTROL_OFFSET) = value | RS_FABRIC_CONTROL_SNAPSHOT;
    return RS_OK;
}

rs_status_t rs_fabric_monitor_get_status(rs_fabric_monitor_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = *rs_fabric_register(RS_FABRIC_STATUS_OFFSET);
    status->outstanding_reads = (uint8_t)(value >> RS_FABRIC_STATUS_READ_SHIFT);
    status->outstanding_writes = (uint8_t)(value >> RS_FABRIC_STATUS_WRITE_SHIFT);
    status->idle = (value & RS_FABRIC_STATUS_IDLE) != 0U;
    status->recovery = (value & RS_FABRIC_STATUS_RECOVERY) != 0U;
    status->flush_busy = (value & RS_FABRIC_STATUS_FLUSH_BUSY) != 0U;
    return RS_OK;
}

rs_status_t rs_fabric_monitor_get_flush_count(uint32_t *count) {
    if (count == NULL) {
        return RS_EINVAL;
    }
    *count = *rs_fabric_register(RS_FABRIC_FLUSH_COUNT_OFFSET);
    return RS_OK;
}

rs_status_t rs_fabric_monitor_read_fault(rs_fabric_fault_t *fault) {
    uint32_t value;

    if (fault == NULL) {
        return RS_EINVAL;
    }
    value = *rs_fabric_register(RS_FABRIC_FAULT_OFFSET);
    fault->address = *rs_fabric_register(RS_FABRIC_FAULT_ADDR_OFFSET);
    fault->count = *rs_fabric_register(RS_FABRIC_FAULT_COUNT_OFFSET);
    fault->master = (uint8_t)((value >> RS_FABRIC_FAULT_MASTER_SHIFT) & RS_FABRIC_FAULT_FIELD_MASK);
    fault->target = (uint8_t)((value >> RS_FABRIC_FAULT_TARGET_SHIFT) & RS_FABRIC_FAULT_FIELD_MASK);
    fault->reason =
        (uint8_t)((value >> RS_FABRIC_FAULT_REASON_SHIFT) & RS_FABRIC_FAULT_REASON_MASK);
    fault->valid = (value & UINT32_C(1)) != 0U;
    fault->write = (value & RS_FABRIC_FAULT_WRITE) != 0U;
    return RS_OK;
}

rs_status_t rs_fabric_monitor_read_master(rs_fabric_master_t master,
                                          rs_fabric_master_stats_t *stats) {
    uint32_t base;
    uint32_t high_water;

    if ((stats == NULL) || ((uint32_t)master >= (uint32_t)RS_FABRIC_MASTER_COUNT)) {
        return RS_EINVAL;
    }
    base = RS_FABRIC_MASTER_BASE + ((uint32_t)master * RS_FABRIC_ENTRY_STRIDE);
    stats->read_requests = *rs_fabric_register(base);
    stats->write_requests = *rs_fabric_register(base + UINT32_C(0x004));
    stats->read_beats = *rs_fabric_register(base + UINT32_C(0x008));
    stats->write_beats = *rs_fabric_register(base + UINT32_C(0x00C));
    stats->wait_cycles = *rs_fabric_register(base + UINT32_C(0x010));
    stats->max_wait_cycles = *rs_fabric_register(base + UINT32_C(0x014));
    stats->starvation_promotions = *rs_fabric_register(base + UINT32_C(0x018));
    high_water = *rs_fabric_register(base + UINT32_C(0x01C));
    stats->read_high_water = (uint8_t)(high_water & RS_FABRIC_HIGH_WATER_MASK);
    stats->write_high_water =
        (uint8_t)((high_water >> RS_FABRIC_WRITE_HIGH_SHIFT) & RS_FABRIC_HIGH_WATER_MASK);
    return RS_OK;
}

rs_status_t rs_fabric_monitor_read_target(rs_fabric_target_t target,
                                          rs_fabric_target_stats_t *stats) {
    uint32_t base;
    uint32_t high_water;

    if ((stats == NULL) || ((uint32_t)target >= (uint32_t)RS_FABRIC_TARGET_COUNT)) {
        return RS_EINVAL;
    }
    base = RS_FABRIC_TARGET_BASE + ((uint32_t)target * RS_FABRIC_ENTRY_STRIDE);
    stats->read_requests = *rs_fabric_register(base);
    stats->write_requests = *rs_fabric_register(base + UINT32_C(0x004));
    stats->read_beats = *rs_fabric_register(base + UINT32_C(0x008));
    stats->write_beats = *rs_fabric_register(base + UINT32_C(0x00C));
    stats->wait_cycles = *rs_fabric_register(base + UINT32_C(0x010));
    stats->timeout_count = *rs_fabric_register(base + UINT32_C(0x014));
    stats->isolated = (*rs_fabric_register(base + UINT32_C(0x018)) & UINT32_C(1)) != 0U;
    high_water = *rs_fabric_register(base + UINT32_C(0x01C));
    stats->read_high_water = (uint8_t)(high_water & RS_FABRIC_HIGH_WATER_MASK);
    stats->write_high_water =
        (uint8_t)((high_water >> RS_FABRIC_WRITE_HIGH_SHIFT) & RS_FABRIC_HIGH_WATER_MASK);
    return RS_OK;
}
