#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/usb2.h>

static bool rs_usb2_address_range_valid(uintptr_t address, size_t byte_count) {
    uintptr_t last;

    if ((address == (uintptr_t)0U) || (address > (uintptr_t)UINT32_MAX) || (byte_count == 0U) ||
        (byte_count > (size_t)UINT32_MAX)) {
        return false;
    }
    last = address + (uintptr_t)(byte_count - 1U);
    return (last >= address) && (last <= (uintptr_t)UINT32_MAX);
}

static bool rs_usb2_descriptor_address_valid(uintptr_t address) {
    return (address != (uintptr_t)0U) && (address <= (uintptr_t)UINT32_MAX) &&
           ((address % (uintptr_t)RS_USB2_DESCRIPTOR_ALIGNMENT) == (uintptr_t)0U) &&
           ((address & (uintptr_t)UINT32_C(0xFFF)) <= (uintptr_t)UINT32_C(0xFE0));
}

rs_status_t rs_usb2_validate_dma_buffer(const void *buffer, size_t byte_count) {
    uintptr_t address;

    if (buffer == NULL) {
        return RS_EINVAL;
    }
    address = (uintptr_t)buffer;
    if (((address % sizeof(uint32_t)) != 0U) || !rs_usb2_address_range_valid(address, byte_count)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_usb2_descriptor_prepare(rs_usb2_descriptor_t *descriptor, uintptr_t buffer,
                                       size_t byte_count, uintptr_t next, bool end, bool irq,
                                       bool short_ok, bool zero_packet, uint32_t frame) {
    uintptr_t descriptor_address;
    uint32_t control;

    if ((descriptor == NULL) || !rs_usb2_address_range_valid(buffer, byte_count) ||
        ((buffer % sizeof(uint32_t)) != 0U) || ((frame & RS_USB2_DESC_FRAME_RESERVED_MASK) != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_usb2_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    if (end) {
        if (next != (uintptr_t)0U) {
            return RS_EINVAL;
        }
        control = RS_USB2_DESC_END;
    } else {
        if (!rs_usb2_descriptor_address_valid(next)) {
            return RS_EINVAL;
        }
        control = RS_USB2_DESC_CHAIN;
    }
    if (irq) {
        control |= RS_USB2_DESC_IRQ;
    }
    if (short_ok) {
        control |= RS_USB2_DESC_SHORT_OK;
    }
    if (zero_packet) {
        control |= RS_USB2_DESC_ZERO_PACKET;
    }
    descriptor->buffer_addr = (uint32_t)buffer;
    descriptor->byte_length = (uint32_t)byte_count;
    descriptor->next_addr = (uint32_t)next;
    descriptor->control = control;
    descriptor->actual_length = 0U;
    descriptor->status = 0U;
    descriptor->frame = frame;
    descriptor->reserved = 0U;
    return RS_OK;
}

rs_status_t rs_usb2_descriptor_validate(const rs_usb2_descriptor_t *descriptor) {
    uintptr_t descriptor_address;
    bool chain;
    bool end;

    if ((descriptor == NULL) ||
        !rs_usb2_address_range_valid((uintptr_t)descriptor->buffer_addr,
                                     (size_t)descriptor->byte_length) ||
        ((descriptor->buffer_addr % sizeof(uint32_t)) != 0U) ||
        ((descriptor->control & RS_USB2_DESC_RESERVED_MASK) != 0U) ||
        ((descriptor->control & RS_USB2_DESC_WRITEBACK_MASK) != 0U) ||
        (descriptor->actual_length != 0U) || (descriptor->status != 0U) ||
        ((descriptor->frame & RS_USB2_DESC_FRAME_RESERVED_MASK) != 0U) ||
        (descriptor->reserved != 0U)) {
        return RS_EINVAL;
    }
    descriptor_address = (uintptr_t)descriptor;
    if ((descriptor_address <= (uintptr_t)UINT32_MAX) &&
        !rs_usb2_descriptor_address_valid(descriptor_address)) {
        return RS_EINVAL;
    }
    chain = (descriptor->control & RS_USB2_DESC_CHAIN) != 0U;
    end = (descriptor->control & RS_USB2_DESC_END) != 0U;
    if (end) {
        if (chain || (descriptor->next_addr != 0U)) {
            return RS_EINVAL;
        }
    } else if (!chain || !rs_usb2_descriptor_address_valid((uintptr_t)descriptor->next_addr)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_usb2_descriptor_chain_validate(const rs_usb2_descriptor_t *descriptors,
                                              uint16_t count, uint32_t total_bytes) {
    uint32_t total = 0U;
    uint16_t index;
    bool found_end = false;

    if ((descriptors == NULL) || (count == 0U) ||
        (count > (uint16_t)RS_USB2_MAX_DESCRIPTOR_COUNT) ||
        (((uintptr_t)descriptors % (uintptr_t)RS_USB2_DESCRIPTOR_ALIGNMENT) != (uintptr_t)0U)) {
        return RS_EINVAL;
    }
    for (index = 0U; index < count; index++) {
        const rs_usb2_descriptor_t *descriptor = &descriptors[index];
        bool end;

        if ((rs_usb2_descriptor_validate(descriptor) != RS_OK) ||
            (descriptor->byte_length > (UINT32_MAX - total))) {
            return RS_EINVAL;
        }
        total += descriptor->byte_length;
        end = (descriptor->control & RS_USB2_DESC_END) != 0U;
        if (end) {
            if ((index + 1U) != count) {
                return RS_EINVAL;
            }
            found_end = true;
        } else {
            uintptr_t next = (uintptr_t)&descriptors[index + 1U];

            if ((next <= (uintptr_t)UINT32_MAX) && (descriptor->next_addr != (uint32_t)next)) {
                return RS_EINVAL;
            }
        }
    }
    if (!found_end || ((total_bytes != 0U) && (total != total_bytes))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_usb2_descriptor_publish(rs_usb2_descriptor_t *descriptor) {
    if (rs_usb2_descriptor_validate(descriptor) != RS_OK) {
        return RS_EINVAL;
    }
    rs_usb2_memory_barrier();
    descriptor->control |= RS_USB2_DESC_OWN;
    rs_usb2_memory_barrier();
    return RS_OK;
}

rs_status_t rs_usb2_descriptor_publish_chain(rs_usb2_descriptor_t *descriptors, uint16_t count) {
    uint16_t remaining;

    if (rs_usb2_descriptor_chain_validate(descriptors, count, 0U) != RS_OK) {
        return RS_EINVAL;
    }
    remaining = count;
    while (remaining != 0U) {
        remaining--;
        if (rs_usb2_descriptor_publish(&descriptors[remaining]) != RS_OK) {
            return RS_EINVAL;
        }
    }
    return RS_OK;
}
