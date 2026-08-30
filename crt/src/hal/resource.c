#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/resource.h>

#define RS_RESOURCE_CACHE_CONTROL_OFFSET UINT32_C(0x010)
#define RS_RESOURCE_BASE_OFFSET          UINT32_C(0x100)
#define RS_RESOURCE_STRIDE               UINT32_C(0x020)
#define RS_RESOURCE_OWNER_OFFSET         UINT32_C(0x000)
#define RS_RESOURCE_CONTROL_OFFSET       UINT32_C(0x004)
#define RS_RESOURCE_STATUS_OFFSET        UINT32_C(0x008)
#define RS_RESOURCE_FAULT_OFFSET         UINT32_C(0x00C)
#define RS_RESOURCE_HANDOFF_COUNT_OFFSET UINT32_C(0x010)

#define RS_RESOURCE_OWNER_MASK           UINT32_C(0x00000003)
#define RS_RESOURCE_OWNER_LOCK           UINT32_C(0x00000100)
#define RS_RESOURCE_CONTROL_QUIESCE      UINT32_C(0x00000001)
#define RS_RESOURCE_CONTROL_RESET        UINT32_C(0x00000002)
#define RS_RESOURCE_STATUS_IDLE          UINT32_C(0x00000010)
#define RS_RESOURCE_STATUS_FAULT         UINT32_C(0x00000020)
#define RS_RESOURCE_STATUS_IRQ           UINT32_C(0x00000040)
#define RS_RESOURCE_STATUS_BLOCKED       UINT32_C(0x00000080)
#define RS_RESOURCE_CACHE_CLEAN          UINT32_C(0x00000001)
#define RS_RESOURCE_CACHE_REQUEST        UINT32_C(0x00000002)

static bool rs_resource_valid(rs_resource_t resource) {
    return (uint32_t)resource < (uint32_t)RS_RESOURCE_COUNT;
}

static volatile uint32_t *rs_resource_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_APB4_RESOURCE_CTRL_BASE + (uintptr_t)offset);
}

static uint32_t rs_resource_offset(rs_resource_t resource, uint32_t offset) {
    return RS_RESOURCE_BASE_OFFSET + ((uint32_t)resource * RS_RESOURCE_STRIDE) + offset;
}

rs_status_t rs_resource_get_status(rs_resource_t resource, rs_resource_status_t *status) {
    uint32_t owner;
    uint32_t state;

    if ((status == NULL) || !rs_resource_valid(resource)) {
        return RS_EINVAL;
    }
    owner = *rs_resource_register(rs_resource_offset(resource, RS_RESOURCE_OWNER_OFFSET));
    state = *rs_resource_register(rs_resource_offset(resource, RS_RESOURCE_STATUS_OFFSET));
    status->handoff_count = (uint16_t)*rs_resource_register(
        rs_resource_offset(resource, RS_RESOURCE_HANDOFF_COUNT_OFFSET));
    status->owner = (rs_resource_owner_t)(owner & RS_RESOURCE_OWNER_MASK);
    status->owner_locked = (owner & RS_RESOURCE_OWNER_LOCK) != 0U;
    status->blocked = (state & RS_RESOURCE_STATUS_BLOCKED) != 0U;
    status->idle = (state & RS_RESOURCE_STATUS_IDLE) != 0U;
    status->quiesced = (state & RS_RESOURCE_CONTROL_QUIESCE) != 0U;
    status->in_reset = (state & RS_RESOURCE_CONTROL_RESET) != 0U;
    status->fault = (state & RS_RESOURCE_STATUS_FAULT) != 0U;
    status->irq_pending = (state & RS_RESOURCE_STATUS_IRQ) != 0U;
    return RS_OK;
}

rs_status_t rs_resource_set_owner(rs_resource_t resource, rs_resource_owner_t owner, bool lock) {
    rs_resource_status_t status;
    uint32_t value;
    uint32_t timeout;

    if (!rs_resource_valid(resource) ||
        ((owner != RS_RESOURCE_OWNER_LP) && (owner != RS_RESOURCE_OWNER_HP))) {
        return RS_EINVAL;
    }
    if ((rs_resource_get_status(resource, &status) != RS_OK) || status.owner_locked) {
        return RS_EIO;
    }
    if (rs_resource_set_lifecycle(resource, true, false) != RS_OK) {
        return RS_EIO;
    }
    for (timeout = 0U; timeout < RS_TIMEOUT_DEFAULT; ++timeout) {
        if ((rs_resource_get_status(resource, &status) == RS_OK) && status.blocked && status.idle) {
            break;
        }
    }
    if (!status.blocked || !status.idle) {
        (void)rs_resource_set_lifecycle(resource, false, false);
        return RS_ETIMEOUT;
    }
    value = (uint32_t)owner;
    if (lock) {
        value |= RS_RESOURCE_OWNER_LOCK;
    }
    *rs_resource_register(rs_resource_offset(resource, RS_RESOURCE_OWNER_OFFSET)) = value;
    if (rs_resource_get_status(resource, &status) != RS_OK) {
        (void)rs_resource_set_lifecycle(resource, false, false);
        return RS_EIO;
    }
    (void)rs_resource_set_lifecycle(resource, false, false);
    return ((status.owner == owner) && (status.owner_locked == lock)) ? RS_OK : RS_EIO;
}

rs_status_t rs_resource_set_lifecycle(rs_resource_t resource, bool quiesce, bool reset) {
    uint32_t value = 0U;

    if (!rs_resource_valid(resource)) {
        return RS_EINVAL;
    }
    if (quiesce) {
        value |= RS_RESOURCE_CONTROL_QUIESCE;
    }
    if (reset) {
        value |= RS_RESOURCE_CONTROL_RESET;
    }
    *rs_resource_register(rs_resource_offset(resource, RS_RESOURCE_CONTROL_OFFSET)) = value;
    return RS_OK;
}

rs_status_t rs_resource_clear_fault(rs_resource_t resource) {
    if (!rs_resource_valid(resource)) {
        return RS_EINVAL;
    }
    *rs_resource_register(rs_resource_offset(resource, RS_RESOURCE_FAULT_OFFSET)) = UINT32_C(1);
    return RS_OK;
}

rs_status_t rs_resource_get_cache_status(rs_resource_cache_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = *rs_resource_register(RS_RESOURCE_CACHE_CONTROL_OFFSET);
    status->request = (value & RS_RESOURCE_CACHE_REQUEST) != 0U;
    status->clean = (value & RS_RESOURCE_CACHE_CLEAN) != 0U;
    return RS_OK;
}

rs_status_t rs_resource_acknowledge_cache_clean(void) {
    rs_resource_cache_status_t status;

    if ((rs_resource_get_cache_status(&status) != RS_OK) || !status.request) {
        return RS_EIO;
    }
    *rs_resource_register(RS_RESOURCE_CACHE_CONTROL_OFFSET) = RS_RESOURCE_CACHE_CLEAN;
    return RS_OK;
}
