#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/ppalite.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

#define RS_PPA_TARGET_MASK (UINT32_C(1) << 17U)
#define RS_PPA_GUARD       UINT32_C(0xC001D00D)

static _Alignas(64) uint32_t rs_ppa_storage[10];

static bool rs_ppa_camera_pins(void) {
    const rs_gpio_config_t camera = {
        .mode = RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    for (uint32_t pin = 12U; pin <= 22U; ++pin) {
        if (rs_gpio_configure(pin, &camera) != RS_OK) {
            return false;
        }
    }
    return true;
}

static bool rs_ppa_frame_valid(const rs_ppalite_frame_t *frame) {
    const volatile uint8_t *const bytes = (const volatile uint8_t *)&rs_ppa_storage[1];
    if ((frame->base != (uintptr_t)&rs_ppa_storage[1]) || !frame->valid || (frame->width != 7U) ||
        (frame->height != 4U) || (frame->row_bytes != 7U) || (frame->stride_bytes != 8U) ||
        (frame->valid_bytes != 28U) || (frame->transport_bytes != 32U) ||
        (frame->job_sequence != 1U) || (frame->source_sequence != 1U) ||
        (frame->result_config != UINT32_C(0x12)) || (rs_ppa_storage[0] != RS_PPA_GUARD) ||
        (rs_ppa_storage[9] != RS_PPA_GUARD)) {
        return false;
    }
    for (uint32_t row = 0U; row < 4U; ++row) {
        for (uint32_t column = 0U; column < 8U; ++column) {
            const uint32_t index = (row * 8U) + column;
            const uint8_t expected = column == 7U ? 0U : (uint8_t)(5U + (4U * column) + (6U * row));
            if (bytes[index] != expected) {
                return false;
            }
        }
    }
    return true;
}

int main(void) {
    const rs_ppalite_config_t config = {
        .input_format = RS_PPALITE_INPUT_YUYV,
        .source = {.format = RS_DVP_FORMAT_YUV422,
                   .frame_width = 16U,
                   .frame_height = 8U,
                   .crop_x = 1U,
                   .crop_y = 1U,
                   .crop_width = 13U,
                   .crop_height = 7U,
                   .crop_enable = true,
                   .snapshot = true,
                   .stream_enable = true},
        .step_x = 2U,
        .step_y = 2U,
        .output_gray8 = true,
    };
    rs_ppalite_session_t session = {0};
    rs_ppalite_frame_t frame = {0};
    rs_ppalite_info_t info;
    rs_tiny_rcu_snapshot_t rcu;
    rs_status_t result;
    uint8_t code = 0U;

    (void)rs_uart_init(UINT32_C(24000000), UINT32_C(921600));
    for (uint32_t index = 0U; index < 10U; ++index) {
        rs_ppa_storage[index] = RS_PPA_GUARD;
    }
    if (!rs_ppa_camera_pins() || (rs_tiny_rcu_get_snapshot(&rcu) != RS_OK) ||
        ((rcu.target_capability & RS_PPA_TARGET_MASK) == 0U) ||
        (rs_ppalite_probe(&info) != RS_OK) || (info.capability != UINT32_C(0x000003FF)) ||
        (info.clock_hz != UINT32_C(24000000)) ||
        (rs_ppalite_select_route(RS_PPALITE_ROUTE_PROCESS, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        code = 1U;
    }
    if (code == 0U) {
        result = rs_ppalite_capture_begin(&session, &config, (uintptr_t)&rs_ppa_storage[1], 32U,
                                          RS_TIMEOUT_DEFAULT);
        if (result != RS_OK) {
            code = 2U;
        }
    }
    if ((code == 0U) && (rs_ppalite_capture_start(&session, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        code = 3U;
    }
    if ((code == 0U) && (rs_ppalite_capture_wait(&session, &frame, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        code = 4U;
    }
    if ((code == 0U) && !rs_ppa_frame_valid(&frame)) {
        code = 5U;
    }
    if ((code == 0U) && (rs_ppalite_release(&session, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        code = 6U;
    }
    if ((code == 0U) &&
        ((rs_ppalite_select_route(RS_PPALITE_ROUTE_RAW, RS_TIMEOUT_DEFAULT) != RS_OK) ||
         (rs_tiny_rcu_apply_reset(RS_PPA_TARGET_MASK, RS_TIMEOUT_DEFAULT) != RS_OK) ||
         (rs_ppalite_probe(&info) != RS_OK) || (info.capability != UINT32_C(0x000003FF)))) {
        code = 7U;
    }
    if (session.acquired) {
        (void)rs_ppalite_abort(&session, RS_TIMEOUT_DEFAULT);
        (void)rs_ppalite_recover(&session, RS_TIMEOUT_DEFAULT);
    }
    printf("PPALITE_P3_RESULT code=%u valid=%u transport=%lu\n", code, frame.valid ? 1U : 0U,
           (unsigned long)frame.transport_bytes);
    rs_sysctrl_write_test_status(code == 0U, code);
    for (;;) {
    }
}
