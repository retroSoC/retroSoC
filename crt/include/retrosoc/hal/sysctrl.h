#ifndef RETROSOC_HAL_SYSCTRL_H
#define RETROSOC_HAL_SYSCTRL_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_SYSCTRL_PERF_MGMT_WAIT = 0,
    RS_SYSCTRL_PERF_USER_WAIT = 1,
    RS_SYSCTRL_PERF_DMA_WAIT = 2,
    RS_SYSCTRL_PERF_APB4_PERIPH_WAIT = 3,
    RS_SYSCTRL_PERF_APB4_SYSTEM_WAIT = 4,
    RS_SYSCTRL_PERF_SDRAM_WAIT = 5,
    RS_SYSCTRL_PERF_PSRAM_WAIT = 6,
    RS_SYSCTRL_PERF_FLASH_WAIT = 7,
} rs_sysctrl_perf_counter_t;

typedef struct {
    uint32_t reset_mask;
    uint8_t selected_core;
    bool bus_enabled;
    bool bus_idle;
    bool draining;
    bool config_error;
} rs_sysctrl_user_core_status_t;

typedef struct {
    uint32_t address;
    uint32_t count;
    uint8_t reason;
    uint8_t detail;
    uint8_t master;
    bool pending;
    bool write;
} rs_sysctrl_fault_status_t;

typedef struct {
    uint32_t active_selection;
    uint8_t error_reason;
    bool active_valid;
    bool busy;
    bool error;
    bool safe_clock;
    bool pll_locked;
    bool capable;
} rs_sysctrl_pll_status_t;

rs_status_t rs_sysctrl_get_core_select(uint8_t *core_id);
rs_status_t rs_sysctrl_set_core_select(uint8_t core_id);
rs_status_t rs_sysctrl_get_ip_select(uint8_t *ip_id);
rs_status_t rs_sysctrl_set_ip_select(uint8_t ip_id);
rs_status_t rs_sysctrl_get_user_core_status(rs_sysctrl_user_core_status_t *status);
rs_status_t rs_sysctrl_set_user_core_reset(uint32_t reset_mask);
rs_status_t rs_sysctrl_clear_user_core_config_error(void);
rs_status_t rs_sysctrl_get_pll_config(uint8_t *selection);
rs_status_t rs_sysctrl_set_pll_config(uint8_t selection);
rs_status_t rs_sysctrl_apply_pll_config(void);
rs_status_t rs_sysctrl_clear_pll_error(void);
rs_status_t rs_sysctrl_get_pll_status(rs_sysctrl_pll_status_t *status);
rs_status_t rs_sysctrl_get_fault_status(rs_sysctrl_fault_status_t *status);
rs_status_t rs_sysctrl_clear_fault(void);
rs_status_t rs_sysctrl_set_perf_control(bool enable, bool clear, bool snapshot);
rs_status_t rs_sysctrl_read_perf_counter(rs_sysctrl_perf_counter_t counter, uint64_t *value);
void rs_sysctrl_write_test_status(bool pass, uint8_t code);
rs_status_t rs_sysctrl_get_test_status(bool *done, bool *pass, uint8_t *code);
rs_status_t rs_sysctrl_get_rtc_wake_status(bool *live, bool *seen);
rs_status_t rs_sysctrl_clear_rtc_wake(void);

#endif
