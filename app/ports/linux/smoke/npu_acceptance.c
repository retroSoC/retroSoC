#include <stdint.h>

#include <retrosoc/hal/npu.h>

#include "kws_npu.h"
#include "npu_acceptance_data.h"

static rs_kws_npu_workspace_t s_workspace;
static rs_kws_npu_profile_t s_profile;
static int8_t s_output[RS_NPU_ACCEPTANCE_OUTPUT_BYTES];

int rs_hp_npu_acceptance(void);
void rs_hp_npu_cache_clean(void);

static void rs_hp_npu_clean_range(const void *pointer, uint32_t bytes) {
    uintptr_t cursor = (uintptr_t)pointer & ~(uintptr_t)UINT32_C(63);
    uintptr_t end = ((uintptr_t)pointer + bytes + UINT32_C(63)) & ~(uintptr_t)UINT32_C(63);

    while (cursor < end) {
        __asm__ volatile("cbo.clean 0(%0)" : : "r"(cursor) : "memory");
        cursor += UINT32_C(64);
    }
}

int rs_hp_npu_acceptance(void) {
    rs_kws_npu_regions_t regions;
    uint32_t index;

    if ((rs_npu_irq_ack(RS_NPU_IRQ_ALL) != RS_OK) || (rs_npu_irq_enable(0U) != RS_OK) ||
        (rs_kws_npu_default_regions(&s_workspace, &regions) != RS_OK) ||
        (rs_kws_npu_prepare(&s_workspace, &regions, rs_npu_acceptance_input,
                            RS_NPU_ACCEPTANCE_INPUT_BYTES) != RS_OK) ||
        (rs_kws_npu_execute(&s_workspace, UINT32_C(0x48504E35), RS_TIMEOUT_DEFAULT * UINT32_C(64),
                            s_output, RS_NPU_ACCEPTANCE_OUTPUT_BYTES, &s_profile) != RS_OK) ||
        (rs_npu_irq_ack(RS_NPU_IRQ_ALL) != RS_OK) ||
        (s_profile.counters.retired_descriptors != RS_KWS_NPU_DESCRIPTOR_COUNT)) {
        return 0;
    }
    for (index = 0U; index < RS_NPU_ACCEPTANCE_OUTPUT_BYTES; ++index) {
        if (s_output[index] != rs_npu_acceptance_output[index]) {
            return 0;
        }
    }
    return 1;
}

void rs_hp_npu_cache_clean(void) {
    rs_hp_npu_clean_range(&s_workspace, sizeof(s_workspace));
    rs_hp_npu_clean_range(&s_profile, sizeof(s_profile));
    rs_hp_npu_clean_range(s_output, sizeof(s_output));
    rs_hp_npu_clean_range(rs_kws_npu_weights, sizeof(rs_kws_npu_weights));
    rs_hp_npu_clean_range(rs_kws_npu_params, sizeof(rs_kws_npu_params));
    __asm__ volatile("fence rw, rw" : : : "memory");
}
