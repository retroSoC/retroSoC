#ifndef RETROSOC_PWM_H
#define RETROSOC_PWM_H

#include <pwm.h>
#include <pwm_regs.h>

#include <retrosoc/core/status.h>

typedef pwm_timer_config_t rs_pwm_timer_config_t;
typedef pwm_channel_config_t rs_pwm_channel_config_t;
typedef pwm_operator_config_t rs_pwm_operator_config_t;
typedef pwm_fade_segment_t rs_pwm_fade_segment_t;
typedef pwm_fault_config_t rs_pwm_fault_config_t;
typedef pwm_capture_config_t rs_pwm_capture_config_t;
typedef pwm_snapshot_t rs_pwm_snapshot_t;
typedef pwm_count_mode_t rs_pwm_count_mode_t;
typedef pwm_load_mode_t rs_pwm_load_mode_t;
typedef pwm_safe_state_t rs_pwm_safe_state_t;

#define RS_PWM_COUNT_MODE_UP           PWM_COUNT_MODE_UP
#define RS_PWM_COUNT_MODE_DOWN         PWM_COUNT_MODE_DOWN
#define RS_PWM_COUNT_MODE_UP_DOWN      PWM_COUNT_MODE_UP_DOWN
#define RS_PWM_LOAD_ON_ZERO            PWM_LOAD_ON_ZERO
#define RS_PWM_LOAD_ON_PERIOD          PWM_LOAD_ON_PERIOD
#define RS_PWM_LOAD_ON_ZERO_OR_SYNC    PWM_LOAD_ON_ZERO_OR_SYNC
#define RS_PWM_LOAD_ON_SYNC            PWM_LOAD_ON_SYNC
#define RS_PWM_SAFE_LOW                PWM_SAFE_LOW
#define RS_PWM_SAFE_HIGH               PWM_SAFE_HIGH
#define RS_PWM_SAFE_HIGH_Z             PWM_SAFE_HIGH_Z
#define RS_PWM_ACTION_HOLD             PWM_ACTION_HOLD
#define RS_PWM_ACTION_LOW              PWM_ACTION_LOW
#define RS_PWM_ACTION_HIGH             PWM_ACTION_HIGH
#define RS_PWM_ACTION_TOGGLE           PWM_ACTION_TOGGLE
#define RS_PWM_EVENT_TIMER0_ZERO       PWM_INTR_TIMER0_ZERO_MASK
#define RS_PWM_EVENT_TIMER1_ZERO       PWM_INTR_TIMER1_ZERO_MASK
#define RS_PWM_EVENT_TIMER0_PERIOD     PWM_INTR_TIMER0_PERIOD_MASK
#define RS_PWM_EVENT_TIMER1_PERIOD     PWM_INTR_TIMER1_PERIOD_MASK
#define RS_PWM_EVENT_FADE0_DONE        PWM_INTR_FADE0_DONE_MASK
#define RS_PWM_EVENT_FADE1_DONE        PWM_INTR_FADE1_DONE_MASK
#define RS_PWM_EVENT_FADE2_DONE        PWM_INTR_FADE2_DONE_MASK
#define RS_PWM_EVENT_FADE3_DONE        PWM_INTR_FADE3_DONE_MASK
#define RS_PWM_EVENT_FAULT             PWM_INTR_FAULT_MASK
#define RS_PWM_EVENT_CAPTURE0          PWM_INTR_CAPTURE0_MASK
#define RS_PWM_EVENT_CAPTURE1          PWM_INTR_CAPTURE1_MASK
#define RS_PWM_EVENT_CAPTURE0_OVERFLOW PWM_INTR_CAPTURE0_OVERFLOW_MASK
#define RS_PWM_EVENT_CAPTURE1_OVERFLOW PWM_INTR_CAPTURE1_OVERFLOW_MASK
#define RS_PWM_EVENT_ALL               PWM_INTR_ALL_MASK

rs_status_t rs_pwm_probe(void);
rs_status_t rs_pwm_timer_configure(uint8_t timer, const rs_pwm_timer_config_t *config);
rs_status_t rs_pwm_channel_configure(uint8_t channel, const rs_pwm_channel_config_t *config);
rs_status_t rs_pwm_operator_configure(uint8_t operator_id, const rs_pwm_operator_config_t *config);
rs_status_t rs_pwm_fault_configure(const rs_pwm_fault_config_t *config);
rs_status_t rs_pwm_capture_configure(const rs_pwm_capture_config_t *config);
rs_status_t rs_pwm_enable(bool debug_freeze);
rs_status_t rs_pwm_disable(void);
rs_status_t rs_pwm_apply_update(rs_timeout_t timeout);
rs_status_t rs_pwm_software_sync(void);
rs_status_t rs_pwm_set_duty(uint8_t channel, uint32_t duty, rs_timeout_t timeout);
rs_status_t rs_pwm_fade_configure(uint8_t channel, const rs_pwm_fade_segment_t *segment);
rs_status_t rs_pwm_fade_start(uint8_t channel);
rs_status_t rs_pwm_fade_pause(uint8_t channel);
rs_status_t rs_pwm_fade_resume(uint8_t channel);
rs_status_t rs_pwm_fade_stop(uint8_t channel);
rs_status_t rs_pwm_gamma_program(uint8_t channel, const rs_pwm_fade_segment_t *segments,
                                 uint8_t count);
rs_status_t rs_pwm_gamma_start(uint8_t channel, uint8_t count);
rs_status_t rs_pwm_fault_clear(void);
rs_status_t rs_pwm_fault_test(void);
rs_status_t rs_pwm_capture_read(uint8_t channel, uint32_t *timestamp, rs_timeout_t timeout);
rs_status_t rs_pwm_interrupt_enable(uint32_t mask);
rs_status_t rs_pwm_interrupt_clear(uint32_t mask);
rs_status_t rs_pwm_interrupt_test(uint32_t mask);
rs_status_t rs_pwm_get_status(rs_pwm_snapshot_t *snapshot);
void rs_pwm_shell_test(int argc, char **argv);

#endif
