#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/usb2.h>

static volatile uint32_t *rs_usb2_reg(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)((uintptr_t)RS_SOC_APB4_USB2_BASE + (uintptr_t)offset);
}

static uint32_t rs_usb2_read(uint32_t offset) {
    return *rs_usb2_reg(offset);
}

static void rs_usb2_write(uint32_t offset, uint32_t value) {
    *rs_usb2_reg(offset) = value;
}

static bool rs_usb2_role_valid(rs_usb2_role_t role) {
    return (role == RS_USB2_ROLE_IDLE) || (role == RS_USB2_ROLE_DEVICE) ||
           (role == RS_USB2_ROLE_HOST);
}

static bool rs_usb2_transfer_type_valid(rs_usb2_transfer_type_t transfer_type) {
    return (transfer_type == RS_USB2_TRANSFER_CONTROL) ||
           (transfer_type == RS_USB2_TRANSFER_ISOCHRONOUS) ||
           (transfer_type == RS_USB2_TRANSFER_BULK) ||
           (transfer_type == RS_USB2_TRANSFER_INTERRUPT);
}

static bool rs_usb2_direction_valid(rs_usb2_direction_t direction) {
    return (direction == RS_USB2_DIRECTION_OUT) || (direction == RS_USB2_DIRECTION_IN);
}

static bool rs_usb2_speed_valid(rs_usb2_speed_t speed) {
    return (speed == RS_USB2_SPEED_HIGH) || (speed == RS_USB2_SPEED_FULL) ||
           (speed == RS_USB2_SPEED_LOW);
}

static bool rs_usb2_descriptor_pointer_valid(uintptr_t address) {
    return (address != (uintptr_t)0U) && (address <= (uintptr_t)UINT32_MAX) &&
           ((address % (uintptr_t)RS_USB2_DESCRIPTOR_ALIGNMENT) == (uintptr_t)0U) &&
           ((address & (uintptr_t)UINT32_C(0xFFF)) <= (uintptr_t)UINT32_C(0xFE0));
}

static bool rs_usb2_packet_region_valid(uint16_t base, uint16_t length) {
    uint32_t end = (uint32_t)base + (uint32_t)length;

    return ((base % sizeof(uint32_t)) == 0U) && (length != 0U) &&
           ((uint32_t)length <= RS_USB2_MAX_TRANSFER_BYTES) && (end <= RS_USB2_PACKET_RAM_BYTES);
}

static uint32_t rs_usb2_packet_region(uint16_t base, uint16_t length) {
    return ((uint32_t)base >> RS_USB2_ABI_RAM_REGION_BASE_LSB) |
           ((uint32_t)length << RS_USB2_ABI_RAM_REGION_LENGTH_LSB);
}

static uint32_t rs_usb2_endpoint_offset(uint8_t endpoint, uint32_t reg) {
    return RS_USB2_ABI_ENDPOINT_BASE + ((uint32_t)endpoint * RS_USB2_ABI_ENDPOINT_STRIDE) + reg;
}

static uint32_t rs_usb2_channel_offset(uint8_t channel, uint32_t reg) {
    return RS_USB2_ABI_CHANNEL_BASE + ((uint32_t)channel * RS_USB2_ABI_CHANNEL_STRIDE) + reg;
}

static bool rs_usb2_configuration_writable(void) {
    uint32_t status = rs_usb2_read(RS_USB2_REG_GLOBAL_STATUS);

    return (status & (RS_USB2_GLOBAL_STATUS_ENABLED | RS_USB2_GLOBAL_STATUS_BUSY)) == 0U;
}

static bool rs_usb2_role_active(rs_usb2_role_t role) {
    uint32_t status = rs_usb2_read(RS_USB2_REG_GLOBAL_STATUS);
    uint32_t active = (status & RS_USB2_GLOBAL_STATUS_ROLE_MASK) >> 2U;

    return ((status & RS_USB2_GLOBAL_STATUS_ENABLED) != 0U) && (active == (uint32_t)role);
}

static bool rs_usb2_host_packet_valid(const rs_usb2_channel_config_t *config) {
    if ((config->max_packet == 0U) || (config->max_packet > 1024U)) {
        return false;
    }
    if (config->speed == RS_USB2_SPEED_LOW) {
        return ((config->transfer_type == RS_USB2_TRANSFER_CONTROL) ||
                (config->transfer_type == RS_USB2_TRANSFER_INTERRUPT)) &&
               (config->max_packet <= 8U);
    }
    if (config->speed == RS_USB2_SPEED_FULL) {
        if (config->transfer_type == RS_USB2_TRANSFER_ISOCHRONOUS) {
            return config->max_packet <= 1023U;
        }
        return config->max_packet <= 64U;
    }
    if ((config->transfer_type == RS_USB2_TRANSFER_CONTROL) && (config->max_packet > 64U)) {
        return false;
    }
    if ((config->transfer_type == RS_USB2_TRANSFER_BULK) && (config->max_packet > 512U)) {
        return false;
    }
    return true;
}

static rs_status_t rs_usb2_viewport_wait(rs_timeout_t timeout, uint32_t *viewport) {
    uint32_t value;

    if ((timeout == 0U) || (viewport == NULL)) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        value = rs_usb2_read(RS_USB2_REG_ULPI_VIEWPORT);
        if ((value & RS_USB2_VIEWPORT_START) == 0U) {
            *viewport = value;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_usb2_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability0,
                          uint32_t *capability1) {
    if ((ip_id == NULL) || (version == NULL) || (capability0 == NULL) || (capability1 == NULL)) {
        return RS_EINVAL;
    }
    *ip_id = rs_usb2_read(RS_USB2_REG_IP_ID);
    *version = rs_usb2_read(RS_USB2_REG_IP_VERSION);
    *capability0 = rs_usb2_read(RS_USB2_REG_CAPABILITY0);
    *capability1 = rs_usb2_read(RS_USB2_REG_CAPABILITY1);
    if ((*ip_id != RS_USB2_IP_ID_VALUE) || (*version != RS_USB2_IP_VERSION_VALUE) ||
        ((*capability0 & RS_USB2_CAPABILITY0_REQUIRED) != RS_USB2_CAPABILITY0_REQUIRED) ||
        (*capability1 != RS_USB2_CAPABILITY1_VALUE)) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_usb2_reset(rs_timeout_t timeout) {
    uint32_t control;

    if (timeout == 0U) {
        return RS_EINVAL;
    }
    control = rs_usb2_read(RS_USB2_REG_GLOBAL_CTRL) & RS_USB2_GLOBAL_CTRL_IRQ_ENABLE;
    rs_usb2_write(RS_USB2_REG_GLOBAL_CTRL, control | RS_USB2_GLOBAL_CTRL_ABORT);
    while (timeout-- != 0U) {
        if ((rs_usb2_read(RS_USB2_REG_GLOBAL_STATUS) & RS_USB2_GLOBAL_STATUS_BUSY) == 0U) {
            rs_usb2_write(RS_USB2_REG_GLOBAL_CTRL, control | RS_USB2_GLOBAL_CTRL_SOFT_RESET);
            rs_usb2_write(RS_USB2_REG_IRQ_STATUS, RS_USB2_IRQ_ALL);
            rs_usb2_write(RS_USB2_REG_ERROR_STATUS, UINT32_MAX);
            rs_usb2_write(RS_USB2_REG_ENDPOINT_COMPLETE_IN, UINT32_MAX);
            rs_usb2_write(RS_USB2_REG_ENDPOINT_COMPLETE_OUT, UINT32_MAX);
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_usb2_configure(const rs_usb2_config_t *config) {
    uint32_t role;
    uint32_t phy = 0U;
    uint32_t global = 0U;

    if ((config == NULL) || !rs_usb2_role_valid(config->role) ||
        (config->transaction_timeout == 0U) || ((config->irq_enable & ~RS_USB2_IRQ_ALL) != 0U) ||
        !rs_usb2_configuration_writable()) {
        return RS_EINVAL;
    }
    role = (uint32_t)config->role << RS_USB2_ABI_ROLE_CTRL_FORCE_LSB;
    if (config->auto_role) {
        role |= RS_USB2_ROLE_CTRL_AUTO;
    }
    if (config->release_phy_reset) {
        phy |= RS_USB2_PHY_CTRL_RESET_N;
    }
    if (config->enable_interrupts) {
        global |= RS_USB2_GLOBAL_CTRL_IRQ_ENABLE;
    }
    rs_usb2_write(RS_USB2_REG_ROLE_CTRL, role);
    rs_usb2_write(RS_USB2_REG_PHY_CTRL, phy);
    rs_usb2_write(RS_USB2_REG_PORT_CTRL,
                  config->force_full_speed ? RS_USB2_PORT_CTRL_FORCE_FULL_SPEED : 0U);
    rs_usb2_write(RS_USB2_REG_TIMEOUT, config->transaction_timeout);
    rs_usb2_write(RS_USB2_REG_IRQ_STATUS, RS_USB2_IRQ_ALL);
    rs_usb2_write(RS_USB2_REG_IRQ_ENABLE, config->irq_enable);
    rs_usb2_write(RS_USB2_REG_GLOBAL_CTRL, global);
    return RS_OK;
}

rs_status_t rs_usb2_enable(bool enable) {
    uint32_t control = rs_usb2_read(RS_USB2_REG_GLOBAL_CTRL);

    if (enable) {
        control |= RS_USB2_GLOBAL_CTRL_ENABLE;
    } else {
        control &= ~RS_USB2_GLOBAL_CTRL_ENABLE;
    }
    rs_usb2_write(RS_USB2_REG_GLOBAL_CTRL, control);
    return RS_OK;
}

rs_status_t rs_usb2_status_get(rs_usb2_status_t *status) {
    if (status == NULL) {
        return RS_EINVAL;
    }
    status->global = rs_usb2_read(RS_USB2_REG_GLOBAL_STATUS);
    status->role = rs_usb2_read(RS_USB2_REG_ROLE_STATUS);
    status->phy = rs_usb2_read(RS_USB2_REG_PHY_STATUS);
    status->frame = rs_usb2_read(RS_USB2_REG_FRAME);
    status->port = rs_usb2_read(RS_USB2_REG_PORT_STATUS);
    status->irq_status = rs_usb2_read(RS_USB2_REG_IRQ_STATUS);
    status->error_status = rs_usb2_read(RS_USB2_REG_ERROR_STATUS);
    status->error_code = rs_usb2_read(RS_USB2_ABI_ERROR_CODE);
    status->error_info = rs_usb2_read(RS_USB2_ABI_ERROR_INFO);
    status->error_descriptor = rs_usb2_read(RS_USB2_ABI_ERROR_DESC_ADDR);
    status->error_buffer = rs_usb2_read(RS_USB2_ABI_ERROR_BUFFER_ADDR);
    status->enabled = (status->global & RS_USB2_GLOBAL_STATUS_ENABLED) != 0U;
    status->busy = (status->global & RS_USB2_GLOBAL_STATUS_BUSY) != 0U;
    status->link_ready = (status->global & RS_USB2_GLOBAL_STATUS_LINK_READY) != 0U;
    return RS_OK;
}

rs_status_t rs_usb2_device_address_set(uint8_t address) {
    if (address > UINT8_C(127)) {
        return RS_EINVAL;
    }
    rs_usb2_write(RS_USB2_REG_DEVICE_ADDR, (uint32_t)address);
    return RS_OK;
}

rs_status_t rs_usb2_endpoint_configure(const rs_usb2_endpoint_config_t *config) {
    uint32_t cfg;

    if ((config == NULL) || ((uint32_t)config->number >= RS_USB2_NUM_ENDPOINTS) ||
        !rs_usb2_transfer_type_valid(config->transfer_type) || (config->max_packet == 0U) ||
        (config->max_packet > 1024U) || !rs_usb2_configuration_writable() ||
        (config->enable_in &&
         (!rs_usb2_packet_region_valid(config->ram_in_base, config->ram_in_length) ||
          !rs_usb2_descriptor_pointer_valid(config->descriptor_in))) ||
        (config->enable_out &&
         (!rs_usb2_packet_region_valid(config->ram_out_base, config->ram_out_length) ||
          !rs_usb2_descriptor_pointer_valid(config->descriptor_out)))) {
        return RS_EINVAL;
    }
    cfg = (uint32_t)config->transfer_type << RS_USB2_ABI_ENDPOINT_CFG_TYPE_LSB;
    cfg |= (uint32_t)config->max_packet << RS_USB2_ABI_ENDPOINT_CFG_MAX_PACKET_LSB;
    if (config->enable_in) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_ENDPOINT_CFG_IN_ENABLE;
    }
    if (config->enable_out) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_ENDPOINT_CFG_OUT_ENABLE;
    }
    if (config->stall_in) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_ENDPOINT_CFG_IN_STALL;
    }
    if (config->stall_out) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_ENDPOINT_CFG_OUT_STALL;
    }
    rs_usb2_write(rs_usb2_endpoint_offset(config->number, RS_USB2_ABI_ENDPOINT_CFG), cfg);
    rs_usb2_write(
        rs_usb2_endpoint_offset(config->number, RS_USB2_ABI_ENDPOINT_RAM_IN),
        config->enable_in ? rs_usb2_packet_region(config->ram_in_base, config->ram_in_length) : 0U);
    rs_usb2_write(rs_usb2_endpoint_offset(config->number, RS_USB2_ABI_ENDPOINT_RAM_OUT),
                  config->enable_out
                      ? rs_usb2_packet_region(config->ram_out_base, config->ram_out_length)
                      : 0U);
    rs_usb2_write(rs_usb2_endpoint_offset(config->number, RS_USB2_ABI_ENDPOINT_DESC_IN),
                  config->enable_in ? (uint32_t)config->descriptor_in : 0U);
    rs_usb2_write(rs_usb2_endpoint_offset(config->number, RS_USB2_ABI_ENDPOINT_DESC_OUT),
                  config->enable_out ? (uint32_t)config->descriptor_out : 0U);
    return RS_OK;
}

rs_status_t rs_usb2_endpoint_submit(uint8_t endpoint, rs_usb2_direction_t direction) {
    uint32_t command;

    if (((uint32_t)endpoint >= RS_USB2_NUM_ENDPOINTS) || !rs_usb2_direction_valid(direction) ||
        !rs_usb2_role_active(RS_USB2_ROLE_DEVICE)) {
        return RS_EINVAL;
    }
    command = (direction == RS_USB2_DIRECTION_IN) ? RS_USB2_ENDPOINT_COMMAND_PRIME_IN
                                                  : RS_USB2_ENDPOINT_COMMAND_ARM_OUT;
    rs_usb2_memory_barrier();
    rs_usb2_write(rs_usb2_endpoint_offset(endpoint, RS_USB2_ABI_ENDPOINT_COMMAND), command);
    return RS_OK;
}

rs_status_t rs_usb2_endpoint_cancel(uint8_t endpoint) {
    if ((uint32_t)endpoint >= RS_USB2_NUM_ENDPOINTS) {
        return RS_EINVAL;
    }
    rs_usb2_write(rs_usb2_endpoint_offset(endpoint, RS_USB2_ABI_ENDPOINT_COMMAND),
                  RS_USB2_ENDPOINT_COMMAND_CANCEL);
    return RS_OK;
}

rs_status_t rs_usb2_endpoint_completion(uint32_t *in_mask, uint32_t *out_mask) {
    if ((in_mask == NULL) || (out_mask == NULL)) {
        return RS_EINVAL;
    }
    rs_usb2_memory_barrier();
    *in_mask = rs_usb2_read(RS_USB2_REG_ENDPOINT_COMPLETE_IN) & UINT32_C(0xFF);
    *out_mask = rs_usb2_read(RS_USB2_REG_ENDPOINT_COMPLETE_OUT) & UINT32_C(0xFF);
    return RS_OK;
}

rs_status_t rs_usb2_endpoint_completion_clear(uint32_t in_mask, uint32_t out_mask) {
    if (((in_mask | out_mask) & ~UINT32_C(0xFF)) != 0U) {
        return RS_EINVAL;
    }
    rs_usb2_write(RS_USB2_REG_ENDPOINT_COMPLETE_IN, in_mask);
    rs_usb2_write(RS_USB2_REG_ENDPOINT_COMPLETE_OUT, out_mask);
    return RS_OK;
}

rs_status_t rs_usb2_channel_configure(const rs_usb2_channel_config_t *config) {
    uint32_t cfg;
    uint32_t interval_ticks;
    uint32_t target;

    if ((config == NULL) || ((uint32_t)config->channel >= RS_USB2_NUM_CHANNELS) ||
        (config->device_address > UINT8_C(127)) || (config->endpoint > UINT8_C(15)) ||
        !rs_usb2_direction_valid(config->direction) ||
        !rs_usb2_transfer_type_valid(config->transfer_type) ||
        !rs_usb2_speed_valid(config->speed) || !rs_usb2_host_packet_valid(config) ||
        !rs_usb2_packet_region_valid(config->ram_base, config->ram_length) ||
        !rs_usb2_descriptor_pointer_valid(config->descriptor) ||
        (((config->transfer_type == RS_USB2_TRANSFER_ISOCHRONOUS) ||
          (config->transfer_type == RS_USB2_TRANSFER_INTERRUPT)) &&
         ((config->interval == 0U) ||
          ((config->speed == RS_USB2_SPEED_HIGH) ? (config->interval > 8191U)
                                                 : (config->interval > 1023U)))) ||
        (config->setup && ((config->direction != RS_USB2_DIRECTION_OUT) ||
                           (config->transfer_type != RS_USB2_TRANSFER_CONTROL))) ||
        (config->ping_enable &&
         ((config->speed != RS_USB2_SPEED_HIGH) || (config->direction != RS_USB2_DIRECTION_OUT) ||
          (config->transfer_type != RS_USB2_TRANSFER_BULK))) ||
        !rs_usb2_configuration_writable()) {
        return RS_EINVAL;
    }
    cfg = UINT32_C(1) << RS_USB2_ABI_CHANNEL_CFG_ENABLE;
    cfg |= (uint32_t)config->direction << RS_USB2_ABI_CHANNEL_CFG_DIRECTION_IN;
    cfg |= (uint32_t)config->transfer_type << RS_USB2_ABI_CHANNEL_CFG_TYPE_LSB;
    cfg |= (uint32_t)config->max_packet << RS_USB2_ABI_CHANNEL_CFG_MAX_PACKET_LSB;
    if (config->speed == RS_USB2_SPEED_LOW) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_CHANNEL_CFG_LOW_SPEED;
    }
    if (config->setup) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_CHANNEL_CFG_SETUP;
    }
    if (config->ping_enable) {
        cfg |= UINT32_C(1) << RS_USB2_ABI_CHANNEL_CFG_PING_ENABLE;
    }
    target = (uint32_t)config->device_address << RS_USB2_ABI_CHANNEL_TARGET_ADDR_LSB;
    target |= (uint32_t)config->endpoint << RS_USB2_ABI_CHANNEL_TARGET_ENDPOINT_LSB;
    if (config->data_toggle) {
        target |= UINT32_C(1) << RS_USB2_ABI_CHANNEL_TARGET_TOGGLE;
    }
    interval_ticks = (uint32_t)config->interval;
    if (config->speed != RS_USB2_SPEED_HIGH) {
        interval_ticks *= 8U;
    }
    rs_usb2_write(rs_usb2_channel_offset(config->channel, RS_USB2_ABI_CHANNEL_CFG), cfg);
    rs_usb2_write(rs_usb2_channel_offset(config->channel, RS_USB2_ABI_CHANNEL_TARGET), target);
    rs_usb2_write(rs_usb2_channel_offset(config->channel, RS_USB2_ABI_CHANNEL_INTERVAL),
                  interval_ticks);
    rs_usb2_write(rs_usb2_channel_offset(config->channel, RS_USB2_ABI_CHANNEL_RAM),
                  rs_usb2_packet_region(config->ram_base, config->ram_length));
    rs_usb2_write(rs_usb2_channel_offset(config->channel, RS_USB2_ABI_CHANNEL_DESC),
                  (uint32_t)config->descriptor);
    return RS_OK;
}

rs_status_t rs_usb2_channel_start(uint8_t channel) {
    if (((uint32_t)channel >= RS_USB2_NUM_CHANNELS) || !rs_usb2_role_active(RS_USB2_ROLE_HOST)) {
        return RS_EINVAL;
    }
    rs_usb2_memory_barrier();
    rs_usb2_write(rs_usb2_channel_offset(channel, RS_USB2_ABI_CHANNEL_COMMAND),
                  RS_USB2_CHANNEL_COMMAND_START);
    return RS_OK;
}

rs_status_t rs_usb2_channel_cancel(uint8_t channel) {
    if ((uint32_t)channel >= RS_USB2_NUM_CHANNELS) {
        return RS_EINVAL;
    }
    rs_usb2_write(rs_usb2_channel_offset(channel, RS_USB2_ABI_CHANNEL_COMMAND),
                  RS_USB2_CHANNEL_COMMAND_CANCEL);
    return RS_OK;
}

rs_status_t rs_usb2_channel_status_get(uint8_t channel, uint32_t *status, uint32_t *bytes) {
    if (((uint32_t)channel >= RS_USB2_NUM_CHANNELS) || (status == NULL) || (bytes == NULL)) {
        return RS_EINVAL;
    }
    *status = rs_usb2_read(rs_usb2_channel_offset(channel, RS_USB2_ABI_CHANNEL_STATUS));
    *bytes = rs_usb2_read(rs_usb2_channel_offset(channel, RS_USB2_ABI_CHANNEL_BYTES));
    return RS_OK;
}

rs_status_t rs_usb2_irq_enable(uint32_t mask) {
    if ((mask & ~RS_USB2_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    rs_usb2_write(RS_USB2_REG_IRQ_ENABLE, mask);
    return RS_OK;
}

rs_status_t rs_usb2_irq_pending(uint32_t *mask) {
    if (mask == NULL) {
        return RS_EINVAL;
    }
    *mask = rs_usb2_read(RS_USB2_REG_IRQ_STATUS) & RS_USB2_IRQ_ALL;
    return RS_OK;
}

rs_status_t rs_usb2_irq_clear(uint32_t mask) {
    if ((mask & ~RS_USB2_IRQ_ALL) != 0U) {
        return RS_EINVAL;
    }
    rs_usb2_write(RS_USB2_REG_IRQ_STATUS, mask);
    return RS_OK;
}

rs_status_t rs_usb2_irq_test(uint32_t mask) {
    if ((mask == 0U) || ((mask & ~RS_USB2_IRQ_ALL) != 0U)) {
        return RS_EINVAL;
    }
    rs_usb2_write(RS_USB2_REG_IRQ_TEST, mask);
    return RS_OK;
}

rs_status_t rs_usb2_ulpi_read(uint8_t address, uint8_t *data, rs_timeout_t timeout) {
    uint32_t viewport;
    uint32_t result;
    rs_status_t status;

    if ((address > UINT8_C(63)) || (data == NULL)) {
        return RS_EINVAL;
    }
    status = rs_usb2_viewport_wait(timeout, &viewport);
    if (status != RS_OK) {
        return status;
    }
    (void)viewport;
    rs_usb2_write(RS_USB2_REG_ULPI_VIEWPORT,
                  RS_USB2_VIEWPORT_START |
                      ((uint32_t)address << RS_USB2_ABI_PHY_CTRL_VIEWPORT_ADDR_LSB));
    status = rs_usb2_viewport_wait(timeout, &viewport);
    if (status != RS_OK) {
        return status;
    }
    result = rs_usb2_read(RS_USB2_REG_ULPI_VIEWPORT_DATA);
    if ((result & RS_USB2_VIEWPORT_ERROR) != 0U) {
        return RS_EIO;
    }
    *data = (uint8_t)(result & UINT32_C(0xFF));
    return RS_OK;
}

rs_status_t rs_usb2_ulpi_write(uint8_t address, uint8_t data, rs_timeout_t timeout) {
    uint32_t viewport;
    uint32_t result;
    rs_status_t status;

    if (address > UINT8_C(63)) {
        return RS_EINVAL;
    }
    status = rs_usb2_viewport_wait(timeout, &viewport);
    if (status != RS_OK) {
        return status;
    }
    (void)viewport;
    rs_usb2_write(RS_USB2_REG_ULPI_VIEWPORT,
                  RS_USB2_VIEWPORT_START | RS_USB2_VIEWPORT_WRITE |
                      ((uint32_t)address << RS_USB2_ABI_PHY_CTRL_VIEWPORT_ADDR_LSB) |
                      (uint32_t)data);
    status = rs_usb2_viewport_wait(timeout, &viewport);
    if (status != RS_OK) {
        return status;
    }
    result = rs_usb2_read(RS_USB2_REG_ULPI_VIEWPORT_DATA);
    return ((result & RS_USB2_VIEWPORT_ERROR) != 0U) ? RS_EIO : RS_OK;
}

rs_status_t rs_usb2_controller_selftest(void) {
    const uint32_t test_irq = RS_USB2_IRQ_FATAL;
    uint32_t ip_id;
    uint32_t version;
    uint32_t capability0;
    uint32_t capability1;
    uint32_t irq_before;
    uint32_t irq_after;

    if (rs_usb2_probe(&ip_id, &version, &capability0, &capability1) != RS_OK) {
        return RS_EIO;
    }
    (void)ip_id;
    (void)version;
    (void)capability0;
    (void)capability1;
    if ((rs_usb2_read(RS_USB2_REG_GLOBAL_STATUS) & RS_USB2_GLOBAL_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    irq_before = rs_usb2_read(RS_USB2_REG_IRQ_STATUS);
    rs_usb2_write(RS_USB2_REG_IRQ_TEST, test_irq);
    irq_after = rs_usb2_read(RS_USB2_REG_IRQ_STATUS);
    if ((irq_after & test_irq) == 0U) {
        return RS_EIO;
    }
    if ((irq_before & test_irq) == 0U) {
        rs_usb2_write(RS_USB2_REG_IRQ_STATUS, test_irq);
    }
    return RS_OK;
}
