#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clock.h>
#include <retrosoc/hal/ps2.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_ps2_status(ps2_status_t status) {
    rs_status_t result;

    switch (status) {
    case PS2_STATUS_OK:
        result = RS_OK;
        break;
    case PS2_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case PS2_STATUS_TIMEOUT:
        result = RS_ETIMEOUT;
        break;
    case PS2_STATUS_IO_ERROR:
        result = RS_EIO;
        break;
    case PS2_STATUS_UNSUPPORTED:
        result = RS_ENOTSUP;
        break;
    case PS2_STATUS_PROTOCOL_ERROR:
    default:
        result = RS_EFORMAT;
        break;
    }
    return result;
}

rs_status_t rs_ps2_configure(const rs_ps2_config_t *config, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_configure(RS_SOC_APB4_PS2_BASE, config, timeout));
}

rs_status_t rs_ps2_init(uint32_t source_clock_hz) {
    return rs_ps2_status(ps2_init(RS_SOC_APB4_PS2_BASE, source_clock_hz));
}

rs_status_t rs_ps2_write(const uint8_t *data, size_t length, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_write(RS_SOC_APB4_PS2_BASE, data, length, timeout));
}

rs_status_t rs_ps2_read(rs_ps2_rx_byte_t *data, size_t length, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_read(RS_SOC_APB4_PS2_BASE, data, length, timeout));
}

rs_status_t rs_ps2_command(uint8_t command, const uint8_t *parameters, size_t parameter_count,
                           rs_timeout_t timeout) {
    return rs_ps2_status(
        ps2_command(RS_SOC_APB4_PS2_BASE, command, parameters, parameter_count, timeout));
}

rs_status_t rs_ps2_identify(rs_ps2_device_info_t *info, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_identify(RS_SOC_APB4_PS2_BASE, info, timeout));
}

rs_status_t rs_ps2_flush(bool flush_rx, bool flush_tx) {
    return rs_ps2_status(ps2_flush(RS_SOC_APB4_PS2_BASE, flush_rx, flush_tx));
}

rs_status_t rs_ps2_abort(void) {
    return rs_ps2_status(ps2_abort(RS_SOC_APB4_PS2_BASE));
}

rs_status_t rs_ps2_get_status(rs_ps2_controller_status_t *status) {
    return rs_ps2_status(ps2_get_status(RS_SOC_APB4_PS2_BASE, status));
}

rs_status_t rs_ps2_irq_enable(uint32_t mask) {
    return rs_ps2_status(ps2_irq_enable(RS_SOC_APB4_PS2_BASE, mask));
}

rs_status_t rs_ps2_irq_ack(uint32_t mask) {
    return rs_ps2_status(ps2_irq_ack(RS_SOC_APB4_PS2_BASE, mask));
}

rs_status_t rs_ps2_irq_test(uint32_t mask) {
    return rs_ps2_status(ps2_irq_test(RS_SOC_APB4_PS2_BASE, mask));
}

void rs_ps2_keyboard_decoder_init(rs_ps2_keyboard_decoder_t *decoder) {
    ps2_keyboard_decoder_init(decoder);
}

bool rs_ps2_keyboard_decode_byte(rs_ps2_keyboard_decoder_t *decoder, uint8_t byte,
                                 rs_ps2_key_event_t *event) {
    return ps2_keyboard_decode_byte(decoder, byte, event);
}

rs_status_t rs_ps2_keyboard_init(rs_ps2_device_info_t *info, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_keyboard_init(RS_SOC_APB4_PS2_BASE, info, timeout));
}

rs_status_t rs_ps2_keyboard_set_leds(uint8_t led_mask, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_keyboard_set_leds(RS_SOC_APB4_PS2_BASE, led_mask, timeout));
}

rs_status_t rs_ps2_keyboard_set_typematic(uint8_t value, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_keyboard_set_typematic(RS_SOC_APB4_PS2_BASE, value, timeout));
}

void rs_ps2_mouse_decoder_init(rs_ps2_mouse_decoder_t *decoder, uint8_t device_id) {
    ps2_mouse_decoder_init(decoder, device_id);
}

bool rs_ps2_mouse_decode_byte(rs_ps2_mouse_decoder_t *decoder, uint8_t byte,
                              rs_ps2_mouse_event_t *event) {
    return ps2_mouse_decode_byte(decoder, byte, event);
}

rs_status_t rs_ps2_mouse_init(rs_ps2_device_info_t *info, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_mouse_init(RS_SOC_APB4_PS2_BASE, info, timeout));
}

rs_status_t rs_ps2_mouse_set_mode(rs_ps2_mouse_mode_t mode, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_mouse_set_mode(RS_SOC_APB4_PS2_BASE, mode, timeout));
}

rs_status_t rs_ps2_mouse_set_sample_rate(uint8_t rate, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_mouse_set_sample_rate(RS_SOC_APB4_PS2_BASE, rate, timeout));
}

rs_status_t rs_ps2_mouse_set_resolution(uint8_t resolution, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_mouse_set_resolution(RS_SOC_APB4_PS2_BASE, resolution, timeout));
}

rs_status_t rs_ps2_mouse_enable_reporting(bool enable, rs_timeout_t timeout) {
    return rs_ps2_status(ps2_mouse_enable_reporting(RS_SOC_APB4_PS2_BASE, enable, timeout));
}

void rs_ps2_shell_test(int argc, char **argv) {
    rs_ps2_device_info_t info;
    uint32_t clock_hz;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_clock_get_active_hz(&clock_hz);
    if (status == RS_OK) {
        status = rs_ps2_init(clock_hz);
    }
    if (status == RS_OK) {
        status = rs_ps2_identify(&info, RS_TIMEOUT_DEFAULT);
    }
    if (status != RS_OK) {
        printf("[PS2] initialization failed: %d\n", status);
        return;
    }

    printf("[APB IP] PS/2 V2 device=%u id=%x\n", (uint32_t)info.type, info.id[0]);
}
