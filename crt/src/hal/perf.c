#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/perf.h>

static uint64_t rs_perf_read_counter(volatile const uint32_t *low, volatile const uint32_t *high) {
    return ((uint64_t)*high << 32) | (uint64_t)*low;
}

rs_status_t rs_perf_start(void) {
    reg_sysctrl_perf_ctrl = RS_SOC_PERF_CTRL_CLEAR;
    reg_sysctrl_perf_ctrl = RS_SOC_PERF_CTRL_ENABLE;
    return RS_OK;
}

rs_status_t rs_perf_stop(void) {
    reg_sysctrl_perf_ctrl = 0U;
    return RS_OK;
}

rs_status_t rs_perf_snapshot(rs_perf_snapshot_t *snapshot) {
    if (snapshot == NULL) {
        return RS_EINVAL;
    }

    reg_sysctrl_perf_ctrl = RS_SOC_PERF_CTRL_ENABLE | RS_SOC_PERF_CTRL_SNAPSHOT;
    snapshot->mgmt_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_mgmt_wait_lo, &reg_sysctrl_perf_mgmt_wait_hi);
    snapshot->user_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_user_wait_lo, &reg_sysctrl_perf_user_wait_hi);
    snapshot->dma_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_dma_wait_lo, &reg_sysctrl_perf_dma_wait_hi);
    snapshot->ribp_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_ribp_wait_lo, &reg_sysctrl_perf_ribp_wait_hi);
    snapshot->apb_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_apb_wait_lo, &reg_sysctrl_perf_apb_wait_hi);
    snapshot->sdram_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_sdram_wait_lo, &reg_sysctrl_perf_sdram_wait_hi);
    snapshot->psram_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_psram_wait_lo, &reg_sysctrl_perf_psram_wait_hi);
    snapshot->flash_wait =
        rs_perf_read_counter(&reg_sysctrl_perf_flash_wait_lo, &reg_sysctrl_perf_flash_wait_hi);
    return RS_OK;
}
