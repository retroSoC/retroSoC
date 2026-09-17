#include <retrosoc/hal/ga2d.h>

/* Caller supplies an owned, writable, aligned 128-byte destination. */
rs_status_t ga2d_fill_example(uintptr_t destination, rs_timeout_t timeout) {
    const rs_ga2d_job_t job = {
        .operation = RS_GA2D_OP_FILL,
        .destination = {destination, 32U, RS_GA2D_FORMAT_XRGB8888},
        .width = 8U,
        .height = 4U,
        .color = UINT32_C(0xFF204060),
    };
    rs_status_t status = rs_ga2d_configure(&job);
    if (status == RS_OK) {
        status = rs_ga2d_start();
    }
    if (status == RS_OK) {
        status = rs_ga2d_wait(timeout);
    }
    /* Timeout still requires abort/drain before the caller reuses memory. */
    return status;
}
