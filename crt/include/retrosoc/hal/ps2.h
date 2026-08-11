#ifndef RETROSOC_HAL_PS2_H
#define RETROSOC_HAL_PS2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <ps2.h>
#include <ps2_keyboard.h>
#include <ps2_mouse.h>
#include <ps2_regs.h>

#include <retrosoc/core/status.h>

typedef ps2_config_t rs_ps2_config_t;
typedef ps2_rx_byte_t rs_ps2_rx_byte_t;
typedef ps2_device_info_t rs_ps2_device_info_t;
typedef ps2_controller_status_t rs_ps2_controller_status_t;
typedef ps2_key_event_t rs_ps2_key_event_t;
typedef ps2_keyboard_decoder_t rs_ps2_keyboard_decoder_t;
typedef ps2_mouse_mode_t rs_ps2_mouse_mode_t;
typedef ps2_mouse_event_t rs_ps2_mouse_event_t;
typedef ps2_mouse_decoder_t rs_ps2_mouse_decoder_t;

#define RS_PS2_INTERRUPT_RX_WATERMARK PS2_INTR_RX_WATERMARK_MASK
#define RS_PS2_INTERRUPT_TX_WATERMARK PS2_INTR_TX_WATERMARK_MASK
#define RS_PS2_INTERRUPT_TX_DONE      PS2_INTR_TX_DONE_MASK
#define RS_PS2_INTERRUPT_RX_ERROR     PS2_INTR_RX_ERROR_MASK
#define RS_PS2_INTERRUPT_TX_ERROR     PS2_INTR_TX_ERROR_MASK
#define RS_PS2_INTERRUPT_BUS_ERROR    PS2_INTR_BUS_ERROR_MASK
#define RS_PS2_INTERRUPT_ALL          PS2_INTR_VALID_MASK

rs_status_t rs_ps2_configure(const rs_ps2_config_t *config, rs_timeout_t timeout);
rs_status_t rs_ps2_init(uint32_t source_clock_hz);
rs_status_t rs_ps2_write(const uint8_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_ps2_read(rs_ps2_rx_byte_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_ps2_command(uint8_t command, const uint8_t *parameters, size_t parameter_count,
                           rs_timeout_t timeout);
rs_status_t rs_ps2_identify(rs_ps2_device_info_t *info, rs_timeout_t timeout);
rs_status_t rs_ps2_flush(bool flush_rx, bool flush_tx);
rs_status_t rs_ps2_abort(void);
rs_status_t rs_ps2_get_status(rs_ps2_controller_status_t *status);
rs_status_t rs_ps2_irq_enable(uint32_t mask);
rs_status_t rs_ps2_irq_ack(uint32_t mask);
rs_status_t rs_ps2_irq_test(uint32_t mask);

void rs_ps2_keyboard_decoder_init(rs_ps2_keyboard_decoder_t *decoder);
bool rs_ps2_keyboard_decode_byte(rs_ps2_keyboard_decoder_t *decoder, uint8_t byte,
                                 rs_ps2_key_event_t *event);
rs_status_t rs_ps2_keyboard_init(rs_ps2_device_info_t *info, rs_timeout_t timeout);
rs_status_t rs_ps2_keyboard_set_leds(uint8_t led_mask, rs_timeout_t timeout);
rs_status_t rs_ps2_keyboard_set_typematic(uint8_t value, rs_timeout_t timeout);

void rs_ps2_mouse_decoder_init(rs_ps2_mouse_decoder_t *decoder, uint8_t device_id);
bool rs_ps2_mouse_decode_byte(rs_ps2_mouse_decoder_t *decoder, uint8_t byte,
                              rs_ps2_mouse_event_t *event);
rs_status_t rs_ps2_mouse_init(rs_ps2_device_info_t *info, rs_timeout_t timeout);
rs_status_t rs_ps2_mouse_set_mode(rs_ps2_mouse_mode_t mode, rs_timeout_t timeout);
rs_status_t rs_ps2_mouse_set_sample_rate(uint8_t rate, rs_timeout_t timeout);
rs_status_t rs_ps2_mouse_set_resolution(uint8_t resolution, rs_timeout_t timeout);
rs_status_t rs_ps2_mouse_enable_reporting(bool enable, rs_timeout_t timeout);

void rs_ps2_shell_test(int argc, char **argv);

#endif
