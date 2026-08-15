#include <stddef.h>

#include <retrosoc/hal/perf.h>
#include <retrosoc/hal/sysctrl.h>

rs_status_t rs_perf_start(void) {
    if ((rs_sysctrl_set_perf_control(false, true, false) != RS_OK) ||
        (rs_sysctrl_set_perf_control(true, false, false) != RS_OK)) {
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_perf_stop(void) {
    return rs_sysctrl_set_perf_control(false, false, false);
}

rs_status_t rs_perf_snapshot(rs_perf_snapshot_t *snapshot) {
    if (snapshot == NULL) {
        return RS_EINVAL;
    }

    if ((rs_sysctrl_set_perf_control(true, false, true) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_MGMT_WAIT, &snapshot->mgmt_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_USER_WAIT, &snapshot->user_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_DMA_WAIT, &snapshot->dma_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_RIBP_WAIT, &snapshot->ribp_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_APB_WAIT, &snapshot->apb_wait) != RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_SDRAM_WAIT, &snapshot->sdram_wait) !=
         RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_PSRAM_WAIT, &snapshot->psram_wait) !=
         RS_OK) ||
        (rs_sysctrl_read_perf_counter(RS_SYSCTRL_PERF_FLASH_WAIT, &snapshot->flash_wait) !=
         RS_OK)) {
        return RS_EIO;
    }
    return RS_OK;
}
