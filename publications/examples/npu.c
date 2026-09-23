#include <stddef.h>
#include <retrosoc/hal/npu.h>

/* Caller owns resource 9, has cleaned/fenced input ranges and keeps buffers
 * reserved until a matching terminal result and completed cache handoff. */
rs_status_t example_npu_run(const rs_npu_job_t *job, rs_timeout_t budget,
                          rs_npu_status_t *result) {
    rs_status_t status;
    if ((job == NULL) || (result == NULL)) {
        return RS_EINVAL;
    }
    status = rs_npu_submit(job);
    if (status != RS_OK) {
        return status;
    }
    status = rs_npu_wait(job->job_id, budget, result);
    /* RS_ETIMEOUT does not stop DMA: caller must abort/drain before reuse. */
    return status;
}
