#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#if defined(__riscv) && defined(RS_SOC_TINY)
#include <retrosoc/arch/riscv/system_base.h>
#endif

static volatile uint32_t *rs_tiny_rcu_register(uint32_t offset) {
#if defined(RS_TINY_RCU_TEST_MMIO)
    extern volatile uint32_t rs_tiny_rcu_test_mmio[1024];
    return &rs_tiny_rcu_test_mmio[offset / 4U];
#else
    return (volatile uint32_t *)(RS_SOC_APB4_SYSCTRL_BASE + (uintptr_t)offset);
#endif
}

static rs_status_t rs_tiny_rcu_fault_status(void) {
    const uint32_t fault = *rs_tiny_rcu_register(RS_TINY_RCU_FAULT_OFFSET);
    if ((fault & UINT32_C(0x09)) != 0U) {
        return RS_EIO;
    }
    return (fault != 0U) ? RS_ETIMEOUT : RS_OK;
}

static rs_status_t rs_tiny_rcu_prepare(rs_timeout_t timeout) {
    if (timeout == 0U) {
        return RS_EINVAL;
    }
    if ((*rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET) & RS_TINY_RCU_STATUS_BUSY) != 0U) {
        return RS_EBUSY;
    }
    /* The caller owns clearing sticky faults. Do not start an operation whose
     * result could be confused with a previous failure. */
    return rs_tiny_rcu_fault_status();
}

static rs_status_t rs_tiny_rcu_wait(rs_timeout_t timeout, uint32_t *status) {
    uint32_t value = 0U;

    while (timeout-- != 0U) {
        value = *rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET);
        if ((value & RS_TINY_RCU_STATUS_BUSY) == 0U) {
            if (status != NULL) {
                *status = value;
            }
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_tiny_rcu_get_snapshot(rs_tiny_rcu_snapshot_t *snapshot) {
    uint32_t initial_profile;
    if (snapshot == NULL) {
        return RS_EINVAL;
    }
    if ((*rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET) & RS_TINY_RCU_STATUS_BUSY) != 0U) {
        return RS_EBUSY;
    }
    initial_profile = *rs_tiny_rcu_register(RS_TINY_RCU_CLOCK_CURRENT_OFFSET);
    snapshot->capability = *rs_tiny_rcu_register(RS_TINY_RCU_CAPABILITY_OFFSET);
    snapshot->target_capability = *rs_tiny_rcu_register(RS_TINY_RCU_TARGET_CAP_OFFSET);
    snapshot->status = *rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET);
    snapshot->fault = *rs_tiny_rcu_register(RS_TINY_RCU_FAULT_OFFSET);
    snapshot->reset_cause = *rs_tiny_rcu_register(RS_TINY_RCU_RESET_CAUSE_OFFSET);
    snapshot->gate_status = *rs_tiny_rcu_register(RS_TINY_RCU_GATE_STATUS_OFFSET);
    snapshot->xin_hz = *rs_tiny_rcu_register(RS_TINY_RCU_XIN_HZ_OFFSET);
    snapshot->ref_hz = *rs_tiny_rcu_register(RS_TINY_RCU_REF_HZ_OFFSET);
    snapshot->sys_hz = *rs_tiny_rcu_register(RS_TINY_RCU_SYS_HZ_OFFSET);
    snapshot->mem_hz = *rs_tiny_rcu_register(RS_TINY_RCU_MEM_HZ_OFFSET);
    snapshot->pclk_hz = *rs_tiny_rcu_register(RS_TINY_RCU_PCLK_HZ_OFFSET);
    snapshot->clint_hz = *rs_tiny_rcu_register(RS_TINY_RCU_CLINT_HZ_OFFSET);
    snapshot->current_profile =
        (rs_tiny_rcu_profile_t)(*rs_tiny_rcu_register(RS_TINY_RCU_CLOCK_CURRENT_OFFSET) &
                                UINT32_C(3));
    if (((*rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET) & RS_TINY_RCU_STATUS_BUSY) != 0U) ||
        ((uint32_t)snapshot->current_profile != initial_profile)) {
        return RS_EBUSY;
    }
    return RS_OK;
}

rs_status_t rs_tiny_rcu_profile_hz(rs_tiny_rcu_profile_t profile, uint32_t *hz) {
    if (hz == NULL) {
        return RS_EINVAL;
    }
    switch (profile) {
    case RS_TINY_RCU_PROFILE_SAFE24:
        *hz = UINT32_C(24000000);
        break;
    case RS_TINY_RCU_PROFILE_XIN:
        *hz = *rs_tiny_rcu_register(RS_TINY_RCU_XIN_HZ_OFFSET);
        break;
    case RS_TINY_RCU_PROFILE_PLL192:
        *hz = UINT32_C(192000000);
        break;
    case RS_TINY_RCU_PROFILE_PLL240:
        *hz = UINT32_C(240000000);
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_tiny_rcu_request_profile(rs_tiny_rcu_profile_t profile, rs_timeout_t timeout) {
    uint32_t capability;
    uint32_t status;
    uint32_t hz;
    rs_status_t result;

    if (timeout == 0U || rs_tiny_rcu_profile_hz(profile, &hz) != RS_OK) {
        return RS_EINVAL;
    }
    (void)hz;
    capability = *rs_tiny_rcu_register(RS_TINY_RCU_CAPABILITY_OFFSET);
    if ((capability & (UINT32_C(1) << (uint32_t)profile)) == 0U) {
        return RS_ENOTSUP;
    }
    result = rs_tiny_rcu_prepare(timeout);
    if (result != RS_OK) {
        return result;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_CLOCK_REQUEST_OFFSET) = (uint32_t)profile;
    *rs_tiny_rcu_register(RS_TINY_RCU_COMMAND_OFFSET) = RS_TINY_RCU_COMMAND_CLOCK_APPLY;
    if (rs_tiny_rcu_wait(timeout, &status) != RS_OK) {
        return RS_ETIMEOUT;
    }
    if ((status & RS_TINY_RCU_STATUS_FAULT) != 0U) {
        return rs_tiny_rcu_fault_status();
    }
    if (*rs_tiny_rcu_register(RS_TINY_RCU_CLOCK_CURRENT_OFFSET) != (uint32_t)profile) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_tiny_rcu_apply_gate(uint32_t target_mask, rs_timeout_t timeout) {
    uint32_t status;
    rs_status_t result;

    if (timeout == 0U || (target_mask & ~RS_TINY_RCU_CAP_TARGET_MASK) != 0U) {
        return RS_EINVAL;
    }
    if ((target_mask & ~(*rs_tiny_rcu_register(RS_TINY_RCU_TARGET_CAP_OFFSET))) != 0U) {
        return RS_ENOTSUP;
    }
    result = rs_tiny_rcu_prepare(timeout);
    if (result != RS_OK) {
        return result;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_GATE_REQUEST_OFFSET) = target_mask;
    *rs_tiny_rcu_register(RS_TINY_RCU_COMMAND_OFFSET) = RS_TINY_RCU_COMMAND_GATE_APPLY;
    if (rs_tiny_rcu_wait(timeout, &status) != RS_OK) {
        return RS_ETIMEOUT;
    }
    result = rs_tiny_rcu_fault_status();
    if (result != RS_OK) {
        return result;
    }
#if defined(__riscv) && defined(RS_SOC_TINY)
    /* Hazard3's existing sleep permission complements the RCU leaf gate.
     * Keep power-down clear: the fabric, SRAM and DMA remain available. */
    if ((target_mask & 1U) != 0U) {
        __RV_CSR_CLEAR(RS_TINY_RCU_CSR_MSLEEP, 2U);
        __RV_CSR_SET(RS_TINY_RCU_CSR_MSLEEP, 1U);
    } else {
        __RV_CSR_CLEAR(RS_TINY_RCU_CSR_MSLEEP, 1U);
    }
#endif
    return RS_OK;
}

rs_status_t rs_tiny_rcu_apply_reset(uint32_t target_mask, rs_timeout_t timeout) {
    uint32_t status;
    rs_status_t result;

    if (timeout == 0U || target_mask == 0U || (target_mask & ~RS_TINY_RCU_CAP_TARGET_MASK) != 0U ||
        (target_mask & 1U) != 0U) {
        return RS_EINVAL;
    }
    if ((target_mask & ~(*rs_tiny_rcu_register(RS_TINY_RCU_TARGET_CAP_OFFSET))) != 0U) {
        return RS_ENOTSUP;
    }
    result = rs_tiny_rcu_prepare(timeout);
    if (result != RS_OK) {
        return result;
    }
    if ((*rs_tiny_rcu_register(RS_TINY_RCU_GATE_STATUS_OFFSET) & target_mask) != 0U) {
        return RS_EBUSY;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_RESET_REQUEST_OFFSET) = target_mask;
    *rs_tiny_rcu_register(RS_TINY_RCU_COMMAND_OFFSET) = RS_TINY_RCU_COMMAND_RESET_APPLY;
    if (rs_tiny_rcu_wait(timeout, &status) != RS_OK) {
        return RS_ETIMEOUT;
    }
    return rs_tiny_rcu_fault_status();
}

rs_status_t rs_tiny_rcu_clear_fault(uint32_t mask) {
    if ((mask & ~RS_TINY_RCU_FAULT_MASK) != 0U) {
        return RS_EINVAL;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_FAULT_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_tiny_rcu_clear_reset_cause(uint32_t mask) {
    if ((mask & ~RS_TINY_RCU_RESET_CAUSE_MASK) != 0U) {
        return RS_EINVAL;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_RESET_CAUSE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_tiny_rcu_system_reset(rs_timeout_t timeout) {
    uint32_t status;
    if (timeout == 0U) {
        return RS_EINVAL;
    }
    status = *rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET);
    if ((status & RS_TINY_RCU_STATUS_BUSY) != 0U) {
        return RS_EBUSY;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_COMMAND_OFFSET) = RS_TINY_RCU_COMMAND_SYSTEM_RESET;
    /* Success restarts execution at the reset vector. Returning means failure. */
    while (timeout-- != 0U) {
        status = *rs_tiny_rcu_register(RS_TINY_RCU_STATUS_OFFSET);
        if ((status & RS_TINY_RCU_STATUS_FAULT) != 0U) {
            return RS_EIO;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_tiny_rcu_set_clkout(uint32_t source, uint16_t half_period) {
    rs_tiny_rcu_snapshot_t snapshot;
    rs_status_t result;
    uint32_t hz;
    if (source > 4U || (source != 0U && half_period == 0U)) {
        return RS_EINVAL;
    }
    result = rs_tiny_rcu_get_snapshot(&snapshot);
    if (result != RS_OK) {
        return result;
    }
    hz = source == 2U   ? snapshot.sys_hz
         : source == 3U ? snapshot.mem_hz
         : source == 4U ? snapshot.pclk_hz
                        : snapshot.ref_hz;
    if (source != 0U && (uint64_t)hz > (UINT64_C(48000000) * (uint64_t)half_period)) {
        return RS_EINVAL;
    }
    if (source != 0U && (*rs_tiny_rcu_register(RS_TINY_RCU_CLKOUT_OFFSET) & 7U) != 0U) {
        return RS_EBUSY;
    }
    *rs_tiny_rcu_register(RS_TINY_RCU_CLKOUT_OFFSET) = source | ((uint32_t)half_period << 8U);
    return (*rs_tiny_rcu_register(RS_TINY_RCU_FAULT_OFFSET) != 0U) ? RS_EIO : RS_OK;
}
