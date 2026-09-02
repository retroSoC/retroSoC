#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/extension.h>
#include <retrosoc/hal/resource.h>

#define RS_EXTENSION_IDENTIFICATION_OFFSET  UINT32_C(0x000)
#define RS_EXTENSION_VERSION_OFFSET         UINT32_C(0x004)
#define RS_EXTENSION_CAPABILITY_OFFSET      UINT32_C(0x008)
#define RS_EXTENSION_OWNER_OFFSET           UINT32_C(0x00C)
#define RS_EXTENSION_COMMAND_OFFSET         UINT32_C(0x010)
#define RS_EXTENSION_STATUS_OFFSET          UINT32_C(0x014)
#define RS_EXTENSION_READ_BASE_OFFSET       UINT32_C(0x018)
#define RS_EXTENSION_READ_LIMIT_OFFSET      UINT32_C(0x01C)
#define RS_EXTENSION_WRITE_BASE_OFFSET      UINT32_C(0x020)
#define RS_EXTENSION_WRITE_LIMIT_OFFSET     UINT32_C(0x024)
#define RS_EXTENSION_TIMEOUT_OFFSET         UINT32_C(0x028)
#define RS_EXTENSION_DMA_SOURCE_OFFSET      UINT32_C(0x100)
#define RS_EXTENSION_DMA_DESTINATION_OFFSET UINT32_C(0x104)
#define RS_EXTENSION_DMA_LENGTH_OFFSET      UINT32_C(0x108)
#define RS_EXTENSION_DMA_COMMAND_OFFSET     UINT32_C(0x10C)
#define RS_EXTENSION_DMA_STATUS_OFFSET      UINT32_C(0x110)

#define RS_EXTENSION_REGISTER_SIZE          UINT32_C(4)
#define RS_EXTENSION_OWNER_LOCK             UINT32_C(0x00000100)
#define RS_EXTENSION_COMMAND_QUIESCE        UINT32_C(0x00000001)
#define RS_EXTENSION_COMMAND_RESET          UINT32_C(0x00000002)
#define RS_EXTENSION_COMMAND_CLEAR_FAULT    UINT32_C(0x00000004)
#define RS_EXTENSION_DMA_START              UINT32_C(0x00000001)
#define RS_EXTENSION_DMA_ABORT              UINT32_C(0x00000002)
#define RS_EXTENSION_DMA_STATUS_BUSY        UINT32_C(0x00000001)
#define RS_EXTENSION_DMA_STATUS_DONE        UINT32_C(0x00000002)
#define RS_EXTENSION_DMA_STATUS_FAULT       UINT32_C(0x00000004)

static bool rs_extension_slot_valid(rs_extension_slot_t slot) {
    return (slot == RS_EXTENSION_SLOT_L) || (slot == RS_EXTENSION_SLOT_H);
}

static bool rs_extension_offset_valid(uint32_t offset) {
    return ((offset & (RS_EXTENSION_REGISTER_SIZE - UINT32_C(1))) == 0U) &&
           (offset <= (RS_SOC_APB4_EXT_L_SIZE - RS_EXTENSION_REGISTER_SIZE));
}

static uintptr_t rs_extension_base(rs_extension_slot_t slot) {
    return (slot == RS_EXTENSION_SLOT_L) ? (uintptr_t)RS_SOC_APB4_EXT_L_BASE
                                         : (uintptr_t)RS_SOC_APB4_EXT_H_BASE;
}

static volatile uint32_t *rs_extension_register(rs_extension_slot_t slot, uint32_t offset) {
    return (volatile uint32_t *)(rs_extension_base(slot) + (uintptr_t)offset);
}

static rs_status_t rs_extension_write(rs_extension_slot_t slot, uint32_t offset, uint32_t value) {
    if (!rs_extension_slot_valid(slot) || !rs_extension_offset_valid(offset)) {
        return RS_EINVAL;
    }
    *rs_extension_register(slot, offset) = value;
    return RS_OK;
}

rs_status_t rs_extension_read(rs_extension_slot_t slot, uint32_t offset, uint32_t *value) {
    if ((value == NULL) || !rs_extension_slot_valid(slot) || !rs_extension_offset_valid(offset)) {
        return RS_EINVAL;
    }
    *value = *rs_extension_register(slot, offset);
    return RS_OK;
}

rs_status_t rs_extension_probe(rs_extension_slot_t slot,
                               rs_extension_capabilities_t *capabilities) {
    uint32_t capability;

    if (capabilities == NULL) {
        return RS_EINVAL;
    }
    if ((rs_extension_read(slot, RS_EXTENSION_IDENTIFICATION_OFFSET,
                           &capabilities->identification) != RS_OK) ||
        (rs_extension_read(slot, RS_EXTENSION_VERSION_OFFSET, &capabilities->version) != RS_OK) ||
        (rs_extension_read(slot, RS_EXTENSION_CAPABILITY_OFFSET, &capability) != RS_OK)) {
        return RS_EINVAL;
    }
    capabilities->interrupt_count = (uint8_t)((capability >> 8U) & UINT32_C(0xFF));
    capabilities->data_master = (capability & UINT32_C(0x2)) != 0U;
    capabilities->stream = (capability & UINT32_C(0x4)) != 0U;
    capabilities->local_sram = (capability & UINT32_C(0x8)) != 0U;
    return RS_OK;
}

rs_status_t rs_extension_get_status(rs_extension_slot_t slot, rs_extension_status_t *status) {
    uint32_t owner;
    uint32_t lifecycle;

    if (status == NULL) {
        return RS_EINVAL;
    }
    if ((rs_extension_read(slot, RS_EXTENSION_OWNER_OFFSET, &owner) != RS_OK) ||
        (rs_extension_read(slot, RS_EXTENSION_STATUS_OFFSET, &lifecycle) != RS_OK)) {
        return RS_EINVAL;
    }
    status->owner = (rs_extension_owner_t)(owner & UINT32_C(0x3));
    status->owner_locked = (owner & RS_EXTENSION_OWNER_LOCK) != 0U;
    status->present = (lifecycle & UINT32_C(0x1)) != 0U;
    status->idle = (lifecycle & UINT32_C(0x2)) != 0U;
    status->quiesced = (lifecycle & UINT32_C(0x4)) != 0U;
    status->in_reset = (lifecycle & UINT32_C(0x8)) != 0U;
    status->fault = (lifecycle & UINT32_C(0x10)) != 0U;
    return RS_OK;
}

rs_status_t rs_extension_set_owner(rs_extension_slot_t slot, rs_extension_owner_t owner,
                                   bool lock) {
    uint32_t value;
    rs_status_t status;

    if ((owner != RS_EXTENSION_OWNER_LP) && (owner != RS_EXTENSION_OWNER_HP)) {
        return RS_EINVAL;
    }
    value = (uint32_t)owner;
    if (lock) {
        value |= RS_EXTENSION_OWNER_LOCK;
    }
    if (slot == RS_EXTENSION_SLOT_H) {
        status = rs_resource_set_owner(RS_RESOURCE_EXT_H, (rs_resource_owner_t)owner, lock);
        if (status != RS_OK) {
            return status;
        }
    }
    return rs_extension_write(slot, RS_EXTENSION_OWNER_OFFSET, value);
}

rs_status_t rs_extension_set_lifecycle(rs_extension_slot_t slot, bool quiesce, bool reset,
                                       bool clear_fault) {
    uint32_t command = 0U;
    rs_status_t status;

    if (quiesce) {
        command |= RS_EXTENSION_COMMAND_QUIESCE;
    }
    if (reset) {
        command |= RS_EXTENSION_COMMAND_RESET;
    }
    if (clear_fault) {
        command |= RS_EXTENSION_COMMAND_CLEAR_FAULT;
    }
    if (slot == RS_EXTENSION_SLOT_H) {
        status = rs_resource_set_lifecycle(RS_RESOURCE_EXT_H, quiesce, reset);
        if (status != RS_OK) {
            return status;
        }
        if (clear_fault && (rs_resource_clear_fault(RS_RESOURCE_EXT_H) != RS_OK)) {
            return RS_EIO;
        }
    }
    return rs_extension_write(slot, RS_EXTENSION_COMMAND_OFFSET, command);
}

rs_status_t rs_extension_configure_acl(rs_extension_slot_t slot,
                                       const rs_extension_acl_t *configuration) {
    if ((configuration == NULL) || !rs_extension_slot_valid(slot) ||
        (configuration->read_limit < configuration->read_base) ||
        (configuration->write_limit < configuration->write_base) ||
        (configuration->timeout_cycles == 0U)) {
        return RS_EINVAL;
    }
    if (slot != RS_EXTENSION_SLOT_H) {
        return RS_ENOTSUP;
    }
    if ((rs_extension_write(slot, RS_EXTENSION_READ_BASE_OFFSET, configuration->read_base) !=
         RS_OK) ||
        (rs_extension_write(slot, RS_EXTENSION_READ_LIMIT_OFFSET, configuration->read_limit) !=
         RS_OK) ||
        (rs_extension_write(slot, RS_EXTENSION_WRITE_BASE_OFFSET, configuration->write_base) !=
         RS_OK) ||
        (rs_extension_write(slot, RS_EXTENSION_WRITE_LIMIT_OFFSET, configuration->write_limit) !=
         RS_OK) ||
        (rs_extension_write(slot, RS_EXTENSION_TIMEOUT_OFFSET, configuration->timeout_cycles) !=
         RS_OK)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_extension_dma_start(uintptr_t source, uintptr_t destination, uint32_t byte_count) {
    if (((source | destination) & (uintptr_t)UINT32_C(0x7)) != (uintptr_t)0U ||
        (byte_count == 0U) || (source > (uintptr_t)UINT32_MAX) ||
        (destination > (uintptr_t)UINT32_MAX)) {
        return RS_EINVAL;
    }
    if ((rs_extension_write(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_SOURCE_OFFSET,
                            (uint32_t)source) != RS_OK) ||
        (rs_extension_write(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_DESTINATION_OFFSET,
                            (uint32_t)destination) != RS_OK) ||
        (rs_extension_write(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_LENGTH_OFFSET, byte_count) !=
         RS_OK) ||
        (rs_extension_write(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_COMMAND_OFFSET,
                            RS_EXTENSION_DMA_START) != RS_OK)) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_extension_dma_abort(void) {
    return rs_extension_write(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_COMMAND_OFFSET,
                              RS_EXTENSION_DMA_ABORT);
}

rs_status_t rs_extension_dma_get_status(rs_extension_dma_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    if (rs_extension_read(RS_EXTENSION_SLOT_H, RS_EXTENSION_DMA_STATUS_OFFSET, &value) != RS_OK) {
        return RS_EIO;
    }
    status->busy = (value & RS_EXTENSION_DMA_STATUS_BUSY) != 0U;
    status->done = (value & RS_EXTENSION_DMA_STATUS_DONE) != 0U;
    status->fault = (value & RS_EXTENSION_DMA_STATUS_FAULT) != 0U;
    return RS_OK;
}
