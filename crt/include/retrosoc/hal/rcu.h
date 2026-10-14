#ifndef RETROSOC_HAL_RCU_H
#define RETROSOC_HAL_RCU_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_TINY_RCU_PROFILE_SAFE24 = 0,
    RS_TINY_RCU_PROFILE_XIN = 1,
    RS_TINY_RCU_PROFILE_PLL192 = 2,
    RS_TINY_RCU_PROFILE_PLL240 = 3,
} rs_tiny_rcu_profile_t;

typedef struct {
    uint32_t capability;
    uint32_t target_capability;
    uint32_t status;
    uint32_t fault;
    uint32_t reset_cause;
    uint32_t gate_status;
    uint32_t xin_hz;
    uint32_t ref_hz;
    uint32_t sys_hz;
    uint32_t mem_hz;
    uint32_t pclk_hz;
    uint32_t clint_hz;
    rs_tiny_rcu_profile_t current_profile;
} rs_tiny_rcu_snapshot_t;

rs_status_t rs_tiny_rcu_get_snapshot(rs_tiny_rcu_snapshot_t *snapshot);
rs_status_t rs_tiny_rcu_profile_hz(rs_tiny_rcu_profile_t profile, uint32_t *hz);
rs_status_t rs_tiny_rcu_request_profile(rs_tiny_rcu_profile_t profile, rs_timeout_t timeout);
rs_status_t rs_tiny_rcu_apply_gate(uint32_t target_mask, rs_timeout_t timeout);
rs_status_t rs_tiny_rcu_apply_reset(uint32_t target_mask, rs_timeout_t timeout);
rs_status_t rs_tiny_rcu_clear_fault(uint32_t mask);
rs_status_t rs_tiny_rcu_clear_reset_cause(uint32_t mask);
rs_status_t rs_tiny_rcu_system_reset(rs_timeout_t timeout);
rs_status_t rs_tiny_rcu_set_clkout(uint32_t source, uint16_t half_period);

#endif
