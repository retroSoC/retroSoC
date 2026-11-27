#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/piolite.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/lib/printf.h>

static uint32_t tx_word;
static uint32_t rx_word;
static uint32_t scratch_source;
static uint32_t scratch_destination;
static uint16_t out_program_words[2] = {UINT16_C(0x5000), UINT16_C(0x0020)};
static uint16_t in_program_words[3] = {UINT16_C(0x4000), UINT16_C(0x70C0), UINT16_C(0x0020)};
static uint16_t capture_two_words[5] = {UINT16_C(0x4000), UINT16_C(0x70C0), UINT16_C(0x4000),
                                        UINT16_C(0x70C0), UINT16_C(0x0020)};
static rs_dma_tcd_t tx_chain[2] __attribute__((aligned(64)));
static rs_dma_tcd_t rx_chain[2] __attribute__((aligned(64)));

static rs_piolite_program_t out_program = {
    .isa_version = RS_PIOLITE_ABI_APB4_ISA_VALUE,
    .words = out_program_words,
    .word_count = 2U,
    .entry = 0U,
    .wrap_bottom = 0U,
    .wrap_top = 1U,
    .relocation_sites = NULL,
    .relocation_count = 0U,
    .in_base = 0U,
    .in_width = 32U,
    .out_base = 0U,
    .out_width = 32U,
    .set_base = 0U,
    .set_width = 0U,
    .tx_bits = 32U,
    .tx_right = 1U,
    .autopull = 1U,
    .rx_bits = 32U,
    .rx_right = 1U,
    .autopush = 1U,
    .test_pin = RS_PIOLITE_TEST_PIN_NONE,
    .test_flag = 0U,
    .test_pin_enable = 0U,
    .claim_mask = UINT32_MAX,
    .flag_mask = 0U,
    .tx_items = 1U,
    .rx_items = 0U,
    .item_bits = 32U,
    .clock_ticks = 1U,
    .stretchable = 1U,
};
static rs_piolite_program_t in_program = {
    .isa_version = RS_PIOLITE_ABI_APB4_ISA_VALUE,
    .words = in_program_words,
    .word_count = 3U,
    .entry = 0U,
    .wrap_bottom = 0U,
    .wrap_top = 2U,
    .relocation_sites = NULL,
    .relocation_count = 0U,
    .in_base = 0U,
    .in_width = 32U,
    .out_base = 0U,
    .out_width = 32U,
    .set_base = 0U,
    .set_width = 0U,
    .tx_bits = 32U,
    .tx_right = 1U,
    .autopull = 1U,
    .rx_bits = 32U,
    .rx_right = 1U,
    .autopush = 0U,
    .test_pin = RS_PIOLITE_TEST_PIN_NONE,
    .test_flag = 0U,
    .test_pin_enable = 0U,
    .claim_mask = UINT32_MAX,
    .flag_mask = 0U,
    .tx_items = 0U,
    .rx_items = 1U,
    .item_bits = 32U,
    .clock_ticks = 1U,
    .stretchable = 1U,
};
static rs_piolite_program_t capture_two_program = {
    .isa_version = RS_PIOLITE_ABI_APB4_ISA_VALUE,
    .words = capture_two_words,
    .word_count = 5U,
    .entry = 0U,
    .wrap_bottom = 0U,
    .wrap_top = 4U,
    .relocation_sites = NULL,
    .relocation_count = 0U,
    .in_base = 0U,
    .in_width = 32U,
    .out_base = 0U,
    .out_width = 32U,
    .set_base = 0U,
    .set_width = 0U,
    .tx_bits = 32U,
    .tx_right = 1U,
    .autopull = 1U,
    .rx_bits = 32U,
    .rx_right = 1U,
    .autopush = 0U,
    .test_pin = RS_PIOLITE_TEST_PIN_NONE,
    .test_flag = 0U,
    .test_pin_enable = 0U,
    .claim_mask = UINT32_MAX,
    .flag_mask = 0U,
    .tx_items = 0U,
    .rx_items = 0U,
    .item_bits = 32U,
    .clock_ticks = 1U,
    .stretchable = 1U,
};

static rs_status_t prepare_session(rs_piolite_session_t *session,
                                   const rs_piolite_program_t *tx_program,
                                   const rs_piolite_program_t *rx_program, uint32_t initial_value) {
    rs_piolite_allocation_t *tx_allocation = NULL;
    rs_piolite_allocation_t *rx_allocation = NULL;
    rs_piolite_sm_config_t config;
    rs_status_t status = rs_piolite_session_init(session);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_program_load(session, tx_program, 0U, &tx_allocation);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_program_load(session, rx_program, tx_program->word_count, &rx_allocation);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_program_config(tx_program, tx_allocation, 0U, &config);
    if (status != RS_OK) {
        return status;
    }
    config.initial_value = initial_value;
    config.initial_oe = UINT32_MAX;
    status = rs_piolite_configure(session, 0U, &config);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_program_config(rx_program, rx_allocation, 1U, &config);
    if (status != RS_OK) {
        return status;
    }
    config.out_pins = 0U;
    config.set_pins = 0U;
    config.output_mask = 0U;
    config.initial_value = 0U;
    config.initial_oe = 0U;
    return rs_piolite_configure(session, 1U, &config);
}

static uint8_t residual_step;

static rs_status_t close_session(rs_piolite_session_t *session) {
    rs_status_t status = rs_piolite_abort_reset(session, 3U, 256U);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 9U;
    for (uint32_t index = RS_PIOLITE_IMEM_WORDS; index-- > 0U;) {
        if (session->allocations[index].published) {
            residual_step = (uint8_t)(10U + index);
            status = rs_piolite_program_unload(session, &session->allocations[index]);
            if (status != RS_OK) {
                return status;
            }
        }
    }
    residual_step = 50U;
    return rs_piolite_session_release(session);
}

static rs_status_t run_direct(uint32_t pattern) {
    rs_piolite_session_t session;
    rs_dma_config_t tx_config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_PIOLITE_TX,
        .source = (uintptr_t)&tx_word,
        .destination = (uintptr_t)0U,
        .byte_count = 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 1U,
        .burst_beats = 1U,
    };
    rs_dma_config_t rx_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_PIOLITE_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)&rx_word,
        .byte_count = 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 1U,
    };
    rs_status_t status = prepare_session(&session, &out_program, &in_program, pattern);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_claim(&session, 32U);
    if (status != RS_OK) {
        return status;
    }
    tx_word = pattern;
    rx_word = 0U;
    status = rs_piolite_dma_bind(&session, RS_PIOLITE_TX, 0U, 3U, 16U);
    if (status == RS_OK) {
        status = rs_piolite_dma_bind(&session, RS_PIOLITE_RX, 1U, 2U, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_start(&session, RS_PIOLITE_RX, &rx_config);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_start(&session, RS_PIOLITE_TX, &tx_config);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&session, 1U);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&session, 2U);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&session, 0U, 256U);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&session, 1U, 256U);
    }
    if ((status == RS_OK) && (rx_word != pattern)) {
        status = RS_EIO;
    }
    if (status == RS_OK) {
        status = rs_piolite_disable(&session, 3U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_unbind(&session, RS_PIOLITE_TX, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_unbind(&session, RS_PIOLITE_RX, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_release(&session, 32U);
    }
    if (status == RS_OK) {
        status = close_session(&session);
    }
    return status;
}

static void initialize_tcd(rs_dma_tcd_t *descriptor) {
    *descriptor = (rs_dma_tcd_t){0};
    descriptor->y_count = 1U;
}

static rs_status_t run_tcd(uint32_t pattern) {
    rs_piolite_session_t session;
    rs_status_t status = prepare_session(&session, &out_program, &in_program, pattern);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_claim(&session, 32U);
    if (status != RS_OK) {
        return status;
    }
    tx_word = pattern;
    rx_word = 0U;
    scratch_source = pattern ^ UINT32_C(0xFFFFFFFF);
    scratch_destination = 0U;
    initialize_tcd(&tx_chain[0]);
    tx_chain[0].next_ptr = (uint32_t)(uintptr_t)&tx_chain[1];
    tx_chain[0].source = (uint32_t)(uintptr_t)&scratch_source;
    tx_chain[0].destination = (uint32_t)(uintptr_t)&scratch_destination;
    tx_chain[0].byte_count = 4U;
    tx_chain[0].control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC;
    initialize_tcd(&tx_chain[1]);
    tx_chain[1].source = (uint32_t)(uintptr_t)&tx_word;
    tx_chain[1].destination = 0U;
    tx_chain[1].byte_count = 4U;
    tx_chain[1].control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC |
                          ((uint32_t)RS_DMA_KIND_MM_TO_STREAM << RS_DMA_TCD_KIND_SHIFT) |
                          ((uint32_t)RS_DMA_REQUEST_PIOLITE_TX << RS_DMA_TCD_REQUEST_SHIFT);
    initialize_tcd(&rx_chain[0]);
    rx_chain[0].next_ptr = (uint32_t)(uintptr_t)&rx_chain[1];
    rx_chain[0].source = (uint32_t)(uintptr_t)&scratch_source;
    rx_chain[0].destination = (uint32_t)(uintptr_t)&scratch_destination;
    rx_chain[0].byte_count = 4U;
    rx_chain[0].control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC;
    initialize_tcd(&rx_chain[1]);
    rx_chain[1].source = 0U;
    rx_chain[1].destination = (uint32_t)(uintptr_t)&rx_word;
    rx_chain[1].byte_count = 4U;
    rx_chain[1].control = RS_DMA_TCD_VALID | RS_DMA_TCD_DST_INC |
                          ((uint32_t)RS_DMA_KIND_STREAM_TO_MM << RS_DMA_TCD_KIND_SHIFT) |
                          ((uint32_t)RS_DMA_REQUEST_PIOLITE_RX << RS_DMA_TCD_REQUEST_SHIFT);
    status = rs_piolite_dma_bind(&session, RS_PIOLITE_TX, 0U, 3U, 16U);
    if (status == RS_OK) {
        status = rs_piolite_dma_bind(&session, RS_PIOLITE_RX, 1U, 2U, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_submit_tcd_chain(&session, RS_PIOLITE_TX, &tx_chain[0], 2U, 256U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_submit_tcd_chain(&session, RS_PIOLITE_RX, &rx_chain[0], 2U, 256U);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&session, 1U);
    }
    if (status == RS_OK) {
        status = rs_piolite_start(&session, 2U);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&session, 0U, 256U);
    }
    if (status == RS_OK) {
        status = rs_piolite_wait_done(&session, 1U, 256U);
    }
    if ((status == RS_OK) &&
        ((rx_word != pattern) || (scratch_destination != (pattern ^ UINT32_C(0xFFFFFFFF))))) {
        status = RS_EIO;
    }
    if (status == RS_OK) {
        status = rs_piolite_disable(&session, 3U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_unbind(&session, RS_PIOLITE_TX, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_dma_unbind(&session, RS_PIOLITE_RX, 16U);
    }
    if (status == RS_OK) {
        status = rs_piolite_release(&session, 32U);
    }
    if (status == RS_OK) {
        status = close_session(&session);
    }
    return status;
}

static rs_status_t run_residual_abort(void) {
    rs_piolite_session_t session;
    rs_dma_config_t rx_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_PIOLITE_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)&rx_word,
        .byte_count = 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = 1U,
    };
    rs_status_t status = prepare_session(&session, &out_program, &capture_two_program, 0U);
    residual_step = 1U;
    if (status != RS_OK) {
        return status;
    }
    residual_step = 2U;
    status = rs_piolite_claim(&session, 32U);
    if (status != RS_OK) {
        return status;
    }
    rx_word = 0U;
    residual_step = 3U;
    status = rs_piolite_dma_bind(&session, RS_PIOLITE_RX, 1U, 2U, 16U);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 4U;
    status = rs_piolite_dma_start(&session, RS_PIOLITE_RX, &rx_config);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 5U;
    status = rs_piolite_start(&session, 2U);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 6U;
    status = rs_piolite_abort_reset(&session, 2U, 256U);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 7U;
    status = rs_piolite_release(&session, 32U);
    if (status != RS_OK) {
        return status;
    }
    residual_step = 8U;
    return close_session(&session);
}

static uint16_t rcu_wait_words[2] = {UINT16_C(0x80C0), UINT16_C(0x0020)};
static uint16_t rcu_halt_words[1] = {UINT16_C(0x0020)};

static rs_status_t wait_sm_state(rs_piolite_session_t *session, uint32_t sm, uint32_t expected,
                                 uint32_t stall) {
    rs_piolite_status_t status;
    for (rs_timeout_t budget = 64U; budget != 0U; --budget) {
        const rs_status_t result = rs_piolite_get_status(session, sm, &status);
        if (result != RS_OK) {
            return result;
        }
        if (((status.status & 7U) == expected) &&
            (((status.status >> RS_PIOLITE_ABI_STATUS_STALL) & 7U) == stall)) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t expect_rcu_veto(uint32_t targets, bool reset) {
    const rs_status_t status =
        reset ? rs_tiny_rcu_apply_reset(targets, 32U) : rs_tiny_rcu_apply_gate(targets, 32U);
    if (status != RS_ETIMEOUT) {
        return RS_EIO;
    }
    return rs_tiny_rcu_clear_fault(RS_TINY_RCU_FAULT_MASK);
}

static rs_status_t rediscover_rate(rs_tiny_rcu_profile_t profile, uint32_t expected_hz) {
    rs_piolite_info_t info;
    rs_status_t status = rs_tiny_rcu_request_profile(profile, 256U);
    if (status != RS_OK) {
        return status;
    }
    status = rs_piolite_probe(&info);
    if ((status != RS_OK) || (info.clock_hz != expected_hz)) {
        return RS_EIO;
    }
    return RS_OK;
}

static uint8_t rcu_step;

static rs_status_t run_rcu_lifecycle(void) {
    const uint32_t gpio_target = UINT32_C(1) << 1U;
    rs_piolite_program_t wait_program = out_program;
    rs_piolite_program_t halt_program = in_program;
    rs_piolite_session_t session;
    rs_tiny_rcu_snapshot_t snapshot;
    rs_piolite_status_t sm_status;
    rs_status_t status;
    wait_program.words = rcu_wait_words;
    wait_program.word_count = 2U;
    wait_program.wrap_top = 1U;
    wait_program.tx_items = 0U;
    wait_program.flag_mask = 1U;
    halt_program.words = rcu_halt_words;
    halt_program.word_count = 1U;
    halt_program.wrap_top = 0U;
    halt_program.rx_items = 0U;
    rcu_step = 1U;
    status = prepare_session(&session, &wait_program, &halt_program, 0U);
    if (status != RS_OK) {
        return status;
    }
    rcu_step = 2U;
    status = rs_piolite_claim(&session, 32U);
    if (status == RS_OK) {
        rcu_step = 3U;
        status = rs_piolite_start(&session, 3U);
    }
    if (status == RS_OK) {
        rcu_step = 4U;
        status =
            wait_sm_state(&session, 0U, RS_PIOLITE_ABI_STATE_RUNNING, RS_PIOLITE_ABI_STALL_FLAG);
    }
    if (status == RS_OK) {
        rcu_step = 5U;
        if (wait_sm_state(&session, 1U, RS_PIOLITE_ABI_STATE_HALTED, RS_PIOLITE_ABI_STALL_NONE) !=
            RS_OK) {
            return RS_EIO;
        }
    }
    if (status == RS_OK) {
        rcu_step = 6U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE, false);
    }
    if (status == RS_OK) {
        rcu_step = 7U;
        status = expect_rcu_veto(gpio_target, false);
    }
    if (status == RS_OK) {
        rcu_step = 8U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE | gpio_target, false);
    }
    if (status == RS_OK) {
        rcu_step = 9U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE, true);
    }
    if (status == RS_OK) {
        rcu_step = 10U;
        status = expect_rcu_veto(gpio_target, true);
    }
    if (status == RS_OK) {
        rcu_step = 11U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE | gpio_target, true);
    }
    if (status == RS_OK) {
        rcu_step = 12U;
        status = rs_piolite_pause(&session, 1U);
    }
    if (status == RS_OK) {
        rcu_step = 13U;
        status =
            wait_sm_state(&session, 0U, RS_PIOLITE_ABI_STATE_PAUSED, RS_PIOLITE_ABI_STALL_NONE);
    }
    if (status == RS_OK) {
        rcu_step = 14U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE | gpio_target, false);
    }
    if (status == RS_OK) {
        rcu_step = 15U;
        status = expect_rcu_veto(RS_TINY_RCU_TARGET_PIOLITE | gpio_target, true);
    }
    if (status == RS_OK) {
        rcu_step = 16U;
        if ((rs_piolite_get_status(&session, 1U, &sm_status) != RS_OK) ||
            ((sm_status.status & 7U) != RS_PIOLITE_ABI_STATE_HALTED)) {
            return RS_EIO;
        }
    }
    if (status == RS_OK) {
        rcu_step = 17U;
        status = rs_piolite_release(&session, 32U);
    }
    if (status == RS_OK) {
        rcu_step = 18U;
        status = close_session(&session);
    }
    if (status != RS_OK) {
        return status;
    }
    rcu_step = 19U;
    status = rs_tiny_rcu_get_snapshot(&snapshot);
    if (status != RS_OK) {
        return status;
    }
    if ((snapshot.capability & RS_TINY_RCU_CAP_PLL_PRESENT) != 0U) {
        rcu_step = 20U;
        status = rediscover_rate(RS_TINY_RCU_PROFILE_PLL192, UINT32_C(48000000));
        if (status == RS_OK) {
            rcu_step = 21U;
            status = rediscover_rate(RS_TINY_RCU_PROFILE_PLL240, UINT32_C(60000000));
        }
        if (status != RS_OK) {
            return status;
        }
    }
    rcu_step = 22U;
    status = rediscover_rate(RS_TINY_RCU_PROFILE_SAFE24, UINT32_C(24000000));
    if (status != RS_OK) {
        return status;
    }
    rcu_step = 23U;
    status = rs_tiny_rcu_apply_gate(RS_TINY_RCU_TARGET_PIOLITE, 32U);
    if (status != RS_OK) {
        return RS_EIO;
    }
    rcu_step = 24U;
    status = rs_tiny_rcu_apply_gate(0U, 32U);
    if (status != RS_OK) {
        return RS_EIO;
    }
    rcu_step = 25U;
    status = rs_tiny_rcu_apply_reset(RS_TINY_RCU_TARGET_PIOLITE, 32U);
    if (status != RS_OK) {
        return RS_EIO;
    }
    rcu_step = 26U;
    return rediscover_rate(RS_TINY_RCU_PROFILE_SAFE24, UINT32_C(24000000));
}

static uint8_t run(void) {
    rs_status_t status = run_direct(UINT32_C(0xA55A3CC3));
    if (status != RS_OK) {
        return 1U;
    }
    status = run_tcd(UINT32_C(0x5AA5C33C));
    if (status != RS_OK) {
        return 2U;
    }
    status = run_residual_abort();
    if (status != RS_OK) {
        return (uint8_t)(30U + residual_step);
    }
    status = run_rcu_lifecycle();
    if (status != RS_OK) {
        return (uint8_t)(100U + rcu_step);
    }
    status = run_direct(UINT32_C(0x3CC3A55A));
    if (status != RS_OK) {
        return 5U;
    }
    return 0U;
}

int main(void) {
    const uint8_t code = run();
    rs_sysctrl_write_test_status(code == 0U, code);
    printf("PIOLITE_P3_RESULT code=%u direct=1 tcd=1 residual_abort=1 gpio32=1 rcu=1 reuse=1\n",
           code);
    printf("PIOLITE_P3_DEBUG residual_step=%u\n", residual_step);
    for (;;) {
    }
}
