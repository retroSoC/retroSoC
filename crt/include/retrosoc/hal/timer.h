#ifndef RETROSOC_HAL_TIMER_H
#define RETROSOC_HAL_TIMER_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_TIMER_INTERRUPT_TIMEOUT  UINT32_C(0x00000001)
#define RS_TIMER_INTERRUPT_COMPARE0 UINT32_C(0x00000002)
#define RS_TIMER_INTERRUPT_COMPARE1 UINT32_C(0x00000004)
#define RS_TIMER_INTERRUPT_ALL      UINT32_C(0x00000007)
#define RS_TIMER_DELAY_TIMEOUT      ((rs_timeout_t)UINT32_MAX)

typedef enum {
    RS_TIMER_0 = 0,
    RS_TIMER_1 = 1,
} rs_timer_id_t;

typedef enum {
    RS_TIMER_MODE_FREE_RUNNING = 0,
    RS_TIMER_MODE_PERIODIC = 1,
    RS_TIMER_MODE_ONE_SHOT = 2,
} rs_timer_mode_t;

typedef enum {
    RS_TIMER_DIRECTION_UP = 0,
    RS_TIMER_DIRECTION_DOWN = 1,
} rs_timer_direction_t;

typedef struct {
    rs_timer_mode_t mode;
    rs_timer_direction_t direction;
    uint16_t prescale;
    uint32_t load;
    uint32_t compare0;
    uint32_t compare1;
    uint32_t interrupt_enable;
    bool freeze_in_debug;
    bool compare0_enable;
    bool compare1_enable;
} rs_timer_config_t;

typedef struct {
    uint32_t value;
    uint32_t interrupt_state;
    bool active;
    bool debug_frozen;
} rs_timer_status_t;

typedef struct {
    uint16_t prescale;
    uint32_t load;
} rs_timer_period_t;

rs_status_t rs_timer_period_from_ms(uint32_t source_clock_hz, uint32_t milliseconds,
                                    rs_timer_period_t *period);
rs_status_t rs_timer_configure(rs_timer_id_t timer, const rs_timer_config_t *config);
rs_status_t rs_timer_start(rs_timer_id_t timer);
rs_status_t rs_timer_stop(rs_timer_id_t timer);
rs_status_t rs_timer_set_load(rs_timer_id_t timer, uint32_t load);
rs_status_t rs_timer_set_background_load(rs_timer_id_t timer, uint32_t load);
rs_status_t rs_timer_set_compare(rs_timer_id_t timer, uint32_t channel, uint32_t compare);
rs_status_t rs_timer_get_value(rs_timer_id_t timer, uint32_t *value);
rs_status_t rs_timer_get_status(rs_timer_id_t timer, rs_timer_status_t *status);
rs_status_t rs_timer_interrupt_enable(rs_timer_id_t timer, uint32_t mask);
rs_status_t rs_timer_interrupt_clear(rs_timer_id_t timer, uint32_t mask);
rs_status_t rs_timer_interrupt_test(rs_timer_id_t timer, uint32_t mask);
rs_status_t rs_timer_delay_ms(rs_timer_id_t timer, uint32_t milliseconds, rs_timeout_t timeout);
void rs_timer_shell_test(int argc, char **argv);

#endif
