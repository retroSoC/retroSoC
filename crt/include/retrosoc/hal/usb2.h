#ifndef RETROSOC_HAL_USB2_H
#define RETROSOC_HAL_USB2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/usb2_regs.h>

typedef enum {
    RS_USB2_ROLE_IDLE = RS_USB2_ABI_ROLE_IDLE,
    RS_USB2_ROLE_DEVICE = RS_USB2_ABI_ROLE_DEVICE,
    RS_USB2_ROLE_HOST = RS_USB2_ABI_ROLE_HOST
} rs_usb2_role_t;

typedef enum {
    RS_USB2_SPEED_HIGH = 0,
    RS_USB2_SPEED_FULL = 1,
    RS_USB2_SPEED_LOW = 2
} rs_usb2_speed_t;

typedef enum {
    RS_USB2_TRANSFER_CONTROL = 0,
    RS_USB2_TRANSFER_ISOCHRONOUS = 1,
    RS_USB2_TRANSFER_BULK = 2,
    RS_USB2_TRANSFER_INTERRUPT = 3
} rs_usb2_transfer_type_t;

typedef enum { RS_USB2_DIRECTION_OUT = 0, RS_USB2_DIRECTION_IN = 1 } rs_usb2_direction_t;

typedef struct {
    rs_usb2_role_t role;
    uint32_t transaction_timeout;
    uint32_t irq_enable;
    bool auto_role;
    bool force_full_speed;
    bool release_phy_reset;
    bool enable_interrupts;
} rs_usb2_config_t;

typedef struct {
    uint8_t number;
    rs_usb2_transfer_type_t transfer_type;
    uint16_t max_packet;
    uint16_t ram_in_base;
    uint16_t ram_in_length;
    uint16_t ram_out_base;
    uint16_t ram_out_length;
    uintptr_t descriptor_in;
    uintptr_t descriptor_out;
    bool enable_in;
    bool enable_out;
    bool stall_in;
    bool stall_out;
} rs_usb2_endpoint_config_t;

typedef struct {
    uint8_t channel;
    uint8_t device_address;
    uint8_t endpoint;
    rs_usb2_direction_t direction;
    rs_usb2_transfer_type_t transfer_type;
    rs_usb2_speed_t speed;
    uint16_t max_packet;
    uint16_t interval;
    uint16_t ram_base;
    uint16_t ram_length;
    uintptr_t descriptor;
    bool setup;
    bool ping_enable;
    bool data_toggle;
} rs_usb2_channel_config_t;

typedef struct {
    uint32_t global;
    uint32_t role;
    uint32_t phy;
    uint32_t frame;
    uint32_t port;
    uint32_t irq_status;
    uint32_t error_status;
    uint32_t error_code;
    uint32_t error_info;
    uint32_t error_descriptor;
    uint32_t error_buffer;
    bool enabled;
    bool busy;
    bool link_ready;
} rs_usb2_status_t;

static inline void rs_usb2_memory_barrier(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
#endif
}

rs_status_t rs_usb2_validate_dma_buffer(const void *buffer, size_t byte_count);
rs_status_t rs_usb2_descriptor_prepare(rs_usb2_descriptor_t *descriptor, uintptr_t buffer,
                                       size_t byte_count, uintptr_t next, bool end, bool irq,
                                       bool short_ok, bool zero_packet, uint32_t frame);
rs_status_t rs_usb2_descriptor_validate(const rs_usb2_descriptor_t *descriptor);
rs_status_t rs_usb2_descriptor_chain_validate(const rs_usb2_descriptor_t *descriptors,
                                              uint16_t count, uint32_t total_bytes);
rs_status_t rs_usb2_descriptor_publish(rs_usb2_descriptor_t *descriptor);
rs_status_t rs_usb2_descriptor_publish_chain(rs_usb2_descriptor_t *descriptors, uint16_t count);

rs_status_t rs_usb2_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability0,
                          uint32_t *capability1);
rs_status_t rs_usb2_reset(rs_timeout_t timeout);
rs_status_t rs_usb2_configure(const rs_usb2_config_t *config);
rs_status_t rs_usb2_enable(bool enable);
rs_status_t rs_usb2_status_get(rs_usb2_status_t *status);
rs_status_t rs_usb2_device_address_set(uint8_t address);
rs_status_t rs_usb2_endpoint_configure(const rs_usb2_endpoint_config_t *config);
rs_status_t rs_usb2_endpoint_submit(uint8_t endpoint, rs_usb2_direction_t direction);
rs_status_t rs_usb2_endpoint_cancel(uint8_t endpoint);
rs_status_t rs_usb2_endpoint_completion(uint32_t *in_mask, uint32_t *out_mask);
rs_status_t rs_usb2_endpoint_completion_clear(uint32_t in_mask, uint32_t out_mask);
rs_status_t rs_usb2_channel_configure(const rs_usb2_channel_config_t *config);
rs_status_t rs_usb2_channel_start(uint8_t channel);
rs_status_t rs_usb2_channel_cancel(uint8_t channel);
rs_status_t rs_usb2_channel_status_get(uint8_t channel, uint32_t *status, uint32_t *bytes);
rs_status_t rs_usb2_irq_enable(uint32_t mask);
rs_status_t rs_usb2_irq_pending(uint32_t *mask);
rs_status_t rs_usb2_irq_clear(uint32_t mask);
rs_status_t rs_usb2_irq_test(uint32_t mask);
rs_status_t rs_usb2_ulpi_read(uint8_t address, uint8_t *data, rs_timeout_t timeout);
rs_status_t rs_usb2_ulpi_write(uint8_t address, uint8_t data, rs_timeout_t timeout);
rs_status_t rs_usb2_controller_selftest(void);

#endif
