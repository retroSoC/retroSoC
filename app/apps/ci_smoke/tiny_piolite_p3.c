#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/piolite.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>

#define RS_PIO_REG(offset) RS_SOC_REG32(RS_SOC_APB4_PIOLITE_BASE, (offset))
#define RS_PIO_TIMEOUT     RS_TIMEOUT_DEFAULT
#define RS_PIO_TX_BINDING  (UINT32_C(0x80000000) | (3U << RS_PIOLITE_ABI_TX_BIND_CHANNEL))
#define RS_PIO_RX_BINDING  (UINT32_C(0x80000000) | (2U << RS_PIOLITE_ABI_RX_BIND_CHANNEL))

static rs_piolite_program_t rs_pio_program;
static rs_piolite_session_t rs_pio_session;
static rs_piolite_session_t rs_pio_shared;
static rs_dma_session_t rs_pio_tx;
static rs_dma_session_t rs_pio_rx;
static uint16_t rs_pio_words[8];
static _Alignas(64) uint32_t rs_pio_tx_buffer[16];
static _Alignas(64) uint32_t rs_pio_rx_buffer[16];
static _Alignas(64) rs_dma_tcd_t rs_pio_tcds[2];
static _Alignas(64) uint32_t rs_pio_tcd_source[16];

static rs_piolite_config_t rs_pio_config(const rs_piolite_program_t *program, uint32_t sm,
                                         uint32_t in_base, uint32_t claim_mask,
                                         uint32_t output_mask) {
    const rs_piolite_config_t config = {.sm = sm,
                                        .program = program,
                                        .divider = 1U,
                                        .entry = 0U,
                                        .wrap_bottom = 0U,
                                        .wrap_top = program->word_count - 1U,
                                        .in_base = in_base,
                                        .in_width = 1U,
                                        .set_base = in_base,
                                        .set_width = (output_mask != 0U) ? 1U : 0U,
                                        .claim_mask = claim_mask,
                                        .output_mask = output_mask,
                                        .initial_oe = output_mask,
                                        .tx_bits = 32U,
                                        .rx_bits = 32U,
                                        .rx_high = 1U};
    return config;
}

static rs_status_t rs_pio_load(const uint16_t *words, uint32_t count, uint32_t base,
                               uint32_t wrap_bottom, uint32_t wrap_top) {
    rs_piolite_image_t image = {.isa_version = RS_PIOLITE_ABI_APB4_ISA_VALUE,
                                .words = words,
                                .word_count = count,
                                .entry = 0U,
                                .wrap_bottom = wrap_bottom,
                                .wrap_top = wrap_top};
    rs_piolite_program_t next = {.storage = rs_pio_words, .capacity = 8U};
    rs_status_t result;

    if (rs_pio_program.loaded) {
        result = rs_piolite_program_unload(&rs_pio_program);
        if (result != RS_OK) {
            return result;
        }
    }
    result = rs_piolite_program_load(&next, &image, base);
    if (result == RS_OK) {
        rs_pio_program = next;
    }
    return result;
}

static rs_status_t rs_pio_prepare_pin(uint32_t pin) {
    const rs_gpio_config_t input = {.mode = RS_GPIO_MODE_INPUT,
                                    .pull = RS_GPIO_PULL_NONE,
                                    .trigger = RS_GPIO_TRIGGER_NONE,
                                    .output_high = false};
    return rs_gpio_configure(pin, &input);
}

static rs_status_t rs_pio_setup(const rs_piolite_config_t *config) {
    rs_status_t result = rs_pio_prepare_pin(config->in_base);
    if (result == RS_OK) {
        result = rs_piolite_configure(&rs_pio_session, config);
    }
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    return result;
}

static rs_status_t rs_pio_finish_session(void) {
    rs_status_t result = rs_piolite_disable(&rs_pio_session);
    if (result == RS_OK) {
        result = rs_piolite_release(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if ((result == RS_OK) && rs_pio_program.loaded) {
        result = rs_piolite_program_unload(&rs_pio_program);
    }
    return result;
}

static rs_status_t rs_pio_discover(void) {
    rs_piolite_info_t info;
    rs_tiny_rcu_snapshot_t rcu;
    rs_status_t result = rs_piolite_discover(&info);
    if ((result != RS_OK) || (info.ip_id != RS_PIOLITE_ABI_APB4_ID_VALUE) ||
        (info.apb_version != RS_PIOLITE_ABI_APB4_VERSION_VALUE) ||
        (info.isa_version != RS_PIOLITE_ABI_APB4_ISA_VALUE) ||
        (info.capability != RS_PIOLITE_ABI_APB4_CAPABILITY_VALUE) ||
        (info.routable_mask != RS_PIOLITE_ABI_APB4_ROUTES_VALUE) ||
        (info.clock_hz != UINT32_C(24000000)) ||
        (RS_DMA_REG(RS_DMA_REG_IP_VERSION) != RS_DMA_IP_VERSION_V22) ||
        ((RS_DMA_REG(RS_DMA_REG_SUPPORTED_REQUESTS) & UINT32_C(0xC000)) != UINT32_C(0xC000)) ||
        (rs_tiny_rcu_get_snapshot(&rcu) != RS_OK) ||
        ((rcu.target_capability & UINT32_C(0x8000)) == 0U)) {
        return RS_EIO;
    }
    printf("PIOLITE_P3_CHECK id=1 pass=1 clock=%lu mask=%08lx\n", (unsigned long)info.clock_hz,
           (unsigned long)rcu.target_capability);
    return RS_OK;
}

static rs_status_t rs_pio_gpio_sweep(void) {
    static const uint16_t code[3] = {UINT16_C(0x4001), UINT16_C(0x70C0), UINT16_C(0x0020)};
    for (uint32_t pin = 0U; pin < 32U; ++pin) {
        rs_status_t result = rs_pio_load(code, 3U, 0U, 0U, 2U);
        if (result != RS_OK) {
            return result;
        }
        rs_piolite_config_t config =
            rs_pio_config(&rs_pio_program, 0U, pin, UINT32_C(1) << pin, 0U);
        uint32_t sample = UINT32_MAX;
        config.rx_bits = 1U;
        result = rs_pio_setup(&config);
        if (result == RS_OK) {
            result = rs_piolite_start(&rs_pio_session);
        }
        if (result == RS_OK) {
            result = rs_piolite_fifo_read(&rs_pio_session, &sample, 1U, RS_PIO_TIMEOUT);
        }
        if ((result == RS_OK) && ((sample & 1U) != (pin & 1U))) {
            result = RS_EIO;
        }
        if (result == RS_OK) {
            result = rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT);
        }
        if (result == RS_OK) {
            result = rs_pio_finish_session();
        }
        if (result != RS_OK) {
            return result;
        }
    }
    printf("PIOLITE_P3_CHECK id=2 pass=1 pins=32\n");
    return RS_OK;
}

static rs_status_t rs_pio_shared_input(void) {
    static const uint16_t code[3] = {UINT16_C(0x4001), UINT16_C(0x70C0), UINT16_C(0x0020)};
    rs_piolite_config_t first;
    rs_piolite_config_t second;
    uint32_t sample = 0U;
    rs_status_t result = rs_pio_load(code, 3U, 0U, 0U, 2U);
    if (result != RS_OK) {
        return result;
    }
    first = rs_pio_config(&rs_pio_program, 0U, 4U, UINT32_C(0x10), 0U);
    second = rs_pio_config(&rs_pio_program, 1U, 4U, UINT32_C(0x10), 0U);
    first.rx_bits = 1U;
    first.output_mask = UINT32_C(0x10);
    second.rx_bits = 1U;
    result = rs_pio_setup(&first);
    if (result != RS_OK) {
        return result;
    }
    second.output_mask = UINT32_C(0x10);
    if (rs_piolite_configure(&rs_pio_shared, &second) != RS_EBUSY) {
        return RS_EIO;
    }
    second.output_mask = 0U;
    result = rs_piolite_configure(&rs_pio_shared, &second);
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_shared);
    }
    if (result == RS_OK) {
        result = rs_piolite_fifo_read(&rs_pio_session, &sample, 1U, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_fifo_read(&rs_pio_shared, &sample, 1U, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_disable(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_disable(&rs_pio_shared);
    }
    if (result == RS_OK) {
        result = rs_piolite_release(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_release(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_program_unload(&rs_pio_program);
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=3 pass=1 shared=1\n");
    }
    return result;
}

static rs_status_t rs_pio_output(void) {
    static const uint16_t code[3] = {UINT16_C(0x1001), UINT16_C(0x2001), UINT16_C(0x0020)};
    rs_piolite_config_t config;
    rs_status_t result = rs_pio_load(code, 3U, 0U, 0U, 2U);
    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 4U, UINT32_C(0x10), UINT32_C(0x10));
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=4 pass=1 output=1\n");
    }
    return result;
}

static rs_status_t rs_pio_direct_dma(void) {
    static const uint16_t code[5] = {UINT16_C(0x7040), UINT16_C(0x5080), UINT16_C(0x4060),
                                     UINT16_C(0x70C0), UINT16_C(0x0020)};
    rs_piolite_config_t config;
    rs_status_t result;
    rs_pio_tx.channel = 3U;
    rs_pio_rx.channel = 2U;
    rs_pio_tx_buffer[0] = UINT32_C(0x13579BDF);
    rs_pio_tx_buffer[1] = UINT32_C(0x89ABCDEF);
    rs_pio_tx_buffer[2] = UINT32_C(0x13579BDF);
    rs_pio_tx_buffer[3] = UINT32_C(0x13579BDF);
    rs_pio_rx_buffer[0] = UINT32_C(0x13579BDF);
    rs_pio_rx_buffer[1] = UINT32_C(0x89ABCDEF);
    rs_pio_rx_buffer[2] = UINT32_C(0x13579BDF);
    rs_pio_rx_buffer[3] = UINT32_C(0x13579BDF);
    result = rs_pio_load(code, 5U, 0U, 0U, 4U);
    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_dma_bind(&rs_pio_session, RS_PIOLITE_DMA_TX, &rs_pio_tx,
                                     (uintptr_t)&rs_pio_tx_buffer[1], 4U, 1U);
    }
    if (result == RS_OK) {
        result = rs_piolite_dma_bind(&rs_pio_session, RS_PIOLITE_DMA_RX, &rs_pio_rx,
                                     (uintptr_t)&rs_pio_rx_buffer[1], 4U, 1U);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if ((result == RS_OK) &&
        ((rs_pio_rx_buffer[1] != 0U) || (rs_pio_tx_buffer[0] != 0x13579BDFU) ||
         (rs_pio_tx_buffer[3] != 0x13579BDFU) || (rs_pio_rx_buffer[0] != 0x13579BDFU) ||
         (rs_pio_rx_buffer[3] != 0x13579BDFU))) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_piolite_disable(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_dma_unbind(&rs_pio_session, RS_PIOLITE_DMA_TX);
    }
    if (result == RS_OK) {
        result = rs_piolite_dma_unbind(&rs_pio_session, RS_PIOLITE_DMA_RX);
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=5 pass=1 tx_bytes=4 rx_bytes=4\n");
    }
    return result;
}

static rs_status_t rs_pio_recovery_matrix(void);

static rs_status_t rs_pio_mixed_tcd(void) {
    static const uint16_t code[3] = {UINT16_C(0x7040), UINT16_C(0x5080), UINT16_C(0x0020)};
    rs_piolite_config_t config;
    rs_status_t result;
    rs_pio_tcd_source[0] = UINT32_C(0x2468ACE0);
    rs_pio_tcd_source[1] = 0U;
    rs_pio_tcds[0] =
        (rs_dma_tcd_t){.next_ptr = (uint32_t)(uintptr_t)&rs_pio_tcds[1],
                       .source = (uint32_t)(uintptr_t)&rs_pio_tcd_source[0],
                       .destination = (uint32_t)(uintptr_t)&rs_pio_tcd_source[1],
                       .byte_count = 4U,
                       .y_count = 1U,
                       .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                                  ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT)};
    rs_pio_tcds[1] = (rs_dma_tcd_t){
        .source = (uint32_t)(uintptr_t)&rs_pio_tcd_source[1],
        .destination = RS_SOC_APB4_PIOLITE_BASE + 0x240U,
        .byte_count = 4U,
        .y_count = 1U,
        .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC |
                   ((uint32_t)RS_DMA_KIND_MM_TO_STREAM << RS_DMA_TCD_KIND_SHIFT) |
                   ((uint32_t)RS_DMA_REQUEST_PIOLITE_TX << RS_DMA_TCD_REQUEST_SHIFT)};
    result = rs_pio_load(code, 3U, 0U, 0U, 2U);
    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) = RS_PIO_TX_BINDING;
        if (RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) != RS_PIO_TX_BINDING) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_dma_submit_tcd_chain(3U, &rs_pio_tcds[0], 2U, RS_PIO_TIMEOUT);
    }
    if ((result == RS_OK) &&
        ((rs_pio_tcd_source[1] != rs_pio_tcd_source[0]) || (rs_pio_tcds[1].bytes_done != 4U))) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_disable(&rs_pio_session);
    }
    RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) = 0U;
    if ((result == RS_OK) && (RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) != 0U)) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    if (result == RS_OK) {
        result = rs_pio_recovery_matrix();
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=6 pass=1 tcds=2 tx_bytes=4\n");
    }
    return result;
}

static rs_status_t rs_pio_wait_transport(uint32_t mask) {
    uint32_t timeout = RS_PIO_TIMEOUT;

    while (timeout != 0U) {
        if ((RS_PIO_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) & mask) == mask) {
            return RS_OK;
        }
        --timeout;
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_pio_recover_after_abort(void) {
    rs_status_t result = RS_OK;

    if ((RS_PIO_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) != 0U) ||
        (RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) != 0U) ||
        (RS_PIO_REG(RS_PIOLITE_ABI_APB4_RX_BIND) != 0U) || rs_pio_session.claimed ||
        rs_pio_session.closing) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    return result;
}

static rs_status_t rs_pio_recover(void) {
    rs_status_t result = rs_piolite_abort_reset(&rs_pio_session, RS_PIO_TIMEOUT);

    if (result == RS_OK) {
        result = rs_pio_recover_after_abort();
    }
    return result;
}

static rs_status_t rs_pio_direct_abort(rs_piolite_dma_direction_t direction) {
    static const uint16_t loop[1] = {UINT16_C(0x9000)};
    rs_piolite_config_t config;
    rs_status_t result = rs_pio_load(loop, 1U, 0U, 0U, 0U);

    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        const bool tx = direction == RS_PIOLITE_DMA_TX;
        result = rs_piolite_dma_bind(
            &rs_pio_session, direction, tx ? &rs_pio_tx : &rs_pio_rx,
            tx ? (uintptr_t)&rs_pio_tx_buffer[0] : (uintptr_t)&rs_pio_rx_buffer[0], 64U, 16U);
        if ((result == RS_OK) &&
            (rs_pio_wait_transport(tx ? UINT32_C(0x5) : UINT32_C(0x2)) != RS_OK)) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_pio_recover();
    }
    return result;
}

static rs_status_t rs_pio_residual_rx(void) {
    static const uint16_t code[5] = {UINT16_C(0x4001), UINT16_C(0x70C0), UINT16_C(0x4060),
                                     UINT16_C(0x70C0), UINT16_C(0x0020)};
    rs_piolite_config_t config;
    rs_piolite_status_t pio_status;
    rs_dma_status_t status;
    rs_status_t result = rs_pio_load(code, 5U, 0U, 0U, 4U);
    uint32_t timeout = RS_PIO_TIMEOUT;

    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_dma_bind(&rs_pio_session, RS_PIOLITE_DMA_RX, &rs_pio_rx,
                                     (uintptr_t)&rs_pio_rx_buffer[0], 4U, 1U);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if ((result == RS_OK) && (rs_pio_wait_transport(UINT32_C(0x8)) != RS_OK)) {
        result = RS_EIO;
    }
    while ((result == RS_OK) && (timeout != 0U)) {
        result = rs_dma_get_status(2U, &status);
        if (result != RS_OK) {
            break;
        }
        if (status.done && !status.busy && !status.suspended && !status.aborted && !status.error &&
            (status.bytes_done == 4U) && (status.remaining == 0U)) {
            if ((RS_PIO_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) & UINT32_C(0x8)) == 0U) {
                result = RS_EIO;
            }
            break;
        }
        --timeout;
    }
    if ((result == RS_OK) && (timeout == 0U)) {
        result = RS_ETIMEOUT;
    }
    if (result == RS_OK) {
        result = rs_piolite_get_status(&rs_pio_session, &pio_status);
        if ((result == RS_OK) && (pio_status.complete || ((pio_status.status & UINT32_C(7)) !=
                                                          RS_PIOLITE_ABI_STATE_HALTED))) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_pio_recover();
    }
    return result;
}

static rs_status_t rs_pio_unrelated_progress(void) {
    static const uint16_t code[3] = {UINT16_C(0x4001), UINT16_C(0x70C0), UINT16_C(0x0020)};
    rs_piolite_config_t config;
    rs_piolite_config_t shared_config;
    rs_dma_status_t status;
    rs_status_t result = rs_pio_load(code, 3U, 0U, 0U, 2U);
    uint32_t sample = 0U;

    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_dma_bind(&rs_pio_session, RS_PIOLITE_DMA_RX, &rs_pio_rx,
                                     (uintptr_t)&rs_pio_rx_buffer[0], 64U, 16U);
    }
    if (result == RS_OK) {
        shared_config = rs_pio_config(&rs_pio_program, 1U, 1U, 2U, 0U);
        result = rs_piolite_configure(&rs_pio_shared, &shared_config);
    }
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_shared);
    }
    rs_pio_tcds[0] =
        (rs_dma_tcd_t){.source = (uint32_t)(uintptr_t)&rs_pio_tcd_source[0],
                       .destination = (uint32_t)(uintptr_t)&rs_pio_tx_buffer[0],
                       .byte_count = 64U,
                       .y_count = 1U,
                       .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                                  ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT)};
    const rs_dma_config_t other = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .source = (uintptr_t)&rs_pio_tcd_source[0],
        .destination = (uintptr_t)&rs_pio_tx_buffer[0],
        .byte_count = 64U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .burst_beats = 1U,
    };
    if (result == RS_OK) {
        result = rs_dma_configure(1U, &other);
    }
    if (result == RS_OK) {
        RS_DMA_CH_REG(1U, RS_DMA_CH_REG_TCD_HEAD) = (uint32_t)(uintptr_t)&rs_pio_tcds[0];
        RS_DMA_CH_REG(1U, RS_DMA_CH_REG_TCD_COUNT) = 1U;
        result = rs_dma_start(1U);
    }
    if (result == RS_OK) {
        result = rs_piolite_abort_reset(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_fifo_read(&rs_pio_shared, &sample, 1U, RS_PIO_TIMEOUT);
        if ((result == RS_OK) && ((sample & 1U) != 1U)) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_piolite_wait_done(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_dma_wait(1U, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_dma_get_status(1U, &status);
        if ((result == RS_OK) &&
            ((status.bytes_done != 64U) || (rs_pio_tx_buffer[0] != rs_pio_tcd_source[0]))) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_piolite_disable(&rs_pio_shared);
    }
    if (result == RS_OK) {
        result = rs_piolite_release(&rs_pio_shared, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_pio_recover_after_abort();
    }
    if (rs_dma_reset(1U) != RS_OK) {
        result = RS_EIO;
    }
    return result;
}

static rs_status_t rs_pio_mixed_abort(void) {
    static const uint16_t loop[1] = {UINT16_C(0x9000)};
    rs_piolite_config_t config;
    rs_status_t result = rs_pio_load(loop, 1U, 0U, 0U, 0U);

    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) = RS_PIO_TX_BINDING;
        if (RS_PIO_REG(RS_PIOLITE_ABI_APB4_TX_BIND) != RS_PIO_TX_BINDING) {
            result = RS_EIO;
        }
    }
    rs_pio_tcds[0] =
        (rs_dma_tcd_t){.next_ptr = (uint32_t)(uintptr_t)&rs_pio_tcds[1],
                       .source = (uint32_t)(uintptr_t)&rs_pio_tcd_source[0],
                       .destination = (uint32_t)(uintptr_t)&rs_pio_rx_buffer[0],
                       .byte_count = 64U,
                       .y_count = 1U,
                       .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                                  ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT)};
    rs_pio_tcds[1] = (rs_dma_tcd_t){
        .source = (uint32_t)(uintptr_t)&rs_pio_tx_buffer[0],
        .destination = RS_SOC_APB4_PIOLITE_BASE + 0x240U,
        .byte_count = 64U,
        .y_count = 1U,
        .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC |
                   ((uint32_t)RS_DMA_KIND_MM_TO_STREAM << RS_DMA_TCD_KIND_SHIFT) |
                   ((uint32_t)RS_DMA_REQUEST_PIOLITE_TX << RS_DMA_TCD_REQUEST_SHIFT)};
    const rs_dma_config_t first = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .source = (uintptr_t)&rs_pio_tcd_source[0],
        .destination = (uintptr_t)&rs_pio_rx_buffer[0],
        .byte_count = 64U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .burst_beats = 1U,
    };
    if (result == RS_OK) {
        result = rs_dma_configure(3U, &first);
    }
    if (result == RS_OK) {
        RS_DMA_CH_REG(3U, RS_DMA_CH_REG_TCD_HEAD) = (uint32_t)(uintptr_t)&rs_pio_tcds[0];
        RS_DMA_CH_REG(3U, RS_DMA_CH_REG_TCD_COUNT) = 2U;
        result = rs_dma_start(3U);
    }
    if ((result == RS_OK) && (rs_pio_wait_transport(UINT32_C(0x5)) != RS_OK)) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        RS_PIO_REG(RS_PIOLITE_ABI_APB4_ABORT) = UINT32_C(1);
        if ((RS_PIO_REG(RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
            RS_PIOLITE_ABI_STATE_CLOSING) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_dma_abort_wait(3U, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_dma_reset(3U);
    }
    if (result == RS_OK) {
        result = rs_pio_recover();
    }
    return result;
}

static rs_status_t rs_pio_recovery_matrix(void) {
    rs_status_t result;

    for (uint32_t index = 0U; index < 16U; ++index) {
        rs_pio_tx_buffer[index] = UINT32_C(0x10203040) + index;
        rs_pio_rx_buffer[index] = 0U;
        rs_pio_tcd_source[index] = UINT32_C(0x2468ACE0) + index;
    }
    result = rs_pio_direct_abort(RS_PIOLITE_DMA_TX);
    if (result == RS_OK) {
        result = rs_pio_direct_abort(RS_PIOLITE_DMA_RX);
    }
    if (result == RS_OK) {
        result = rs_pio_residual_rx();
    }
    if (result == RS_OK) {
        result = rs_pio_unrelated_progress();
    }
    if (result == RS_OK) {
        result = rs_pio_mixed_abort();
    }
    return result;
}

static rs_status_t rs_pio_rcu_recover(rs_status_t rejection, rs_status_t expected,
                                      uint32_t expected_fault, uint32_t gate_mask,
                                      uint32_t profile_mask) {
    rs_tiny_rcu_snapshot_t snapshot;
    rs_status_t result;
    uint32_t timeout = RS_PIO_TIMEOUT;

    if (rejection != expected) {
        return RS_EIO;
    }
    while ((timeout != 0U) && ((RS_SOC_REG32(RS_SOC_APB4_SYSCTRL_BASE, RS_TINY_RCU_STATUS_OFFSET) &
                                RS_TINY_RCU_STATUS_BUSY) != 0U)) {
        --timeout;
    }
    if (timeout == 0U) {
        return RS_ETIMEOUT;
    }
    result = rs_tiny_rcu_get_snapshot(&snapshot);
    if (result != RS_OK) {
        return result;
    }
    if ((snapshot.fault != expected_fault) ||
        ((expected == RS_ENOTSUP) && ((snapshot.capability & profile_mask) != 0U)) ||
        ((snapshot.gate_status & gate_mask) != 0U) ||
        (((UINT32_C(1) << (uint32_t)snapshot.current_profile) & profile_mask) != 0U)) {
        return RS_EIO;
    }
    if (expected_fault != 0U) {
        result = rs_tiny_rcu_clear_fault(expected_fault);
        if (result != RS_OK) {
            return result;
        }
    }
    result = rs_tiny_rcu_get_snapshot(&snapshot);
    if ((result == RS_OK) && (snapshot.fault != 0U)) {
        result = RS_EIO;
    }
    return result;
}

static rs_status_t rs_pio_rcu(void) {
    static const uint16_t loop[1] = {UINT16_C(0x9000)};
    rs_piolite_config_t config;
    rs_tiny_rcu_snapshot_t snapshot;
    rs_status_t result = rs_pio_load(loop, 1U, 0U, 0U, 0U);
    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 0U, 1U, 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if (result == RS_OK) {
        result = rs_pio_rcu_recover(rs_tiny_rcu_apply_gate(UINT32_C(0x8000), RS_PIO_TIMEOUT),
                                    RS_ETIMEOUT, UINT32_C(2), UINT32_C(0x8000), 0U);
    }
    if ((result == RS_OK) &&
        ((rs_pio_rcu_recover(RS_EBUSY, RS_ETIMEOUT, UINT32_C(2), 0U, 0U) != RS_EIO) ||
         (rs_pio_rcu_recover(RS_ETIMEOUT, RS_ETIMEOUT, UINT32_C(2), 0U, 0U) != RS_EIO))) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_get_snapshot(&snapshot);
    }
    if (result == RS_OK) {
        result = rs_pio_rcu_recover(
            rs_tiny_rcu_request_profile(RS_TINY_RCU_PROFILE_PLL192, RS_PIO_TIMEOUT),
            ((snapshot.capability & UINT32_C(4)) != 0U) ? RS_ETIMEOUT : RS_ENOTSUP,
            ((snapshot.capability & UINT32_C(4)) != 0U) ? UINT32_C(2) : 0U, 0U, UINT32_C(4));
    }
    if (result == RS_OK) {
        result = rs_piolite_abort_reset(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_apply_gate(UINT32_C(0x8000), RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_apply_gate(0U, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_apply_reset(UINT32_C(0x8000), RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_get_snapshot(&snapshot);
    }
    if ((result == RS_OK) && ((snapshot.capability & UINT32_C(0xC)) != 0U)) {
        result = rs_tiny_rcu_request_profile(RS_TINY_RCU_PROFILE_PLL192, RS_PIO_TIMEOUT);
        if (result == RS_OK) {
            rs_piolite_info_t info;
            result = rs_piolite_discover(&info);
            if ((result == RS_OK) && (info.clock_hz != UINT32_C(48000000))) {
                result = RS_EIO;
            }
        }
        if (result == RS_OK) {
            result = rs_tiny_rcu_request_profile(RS_TINY_RCU_PROFILE_SAFE24, RS_PIO_TIMEOUT);
        }
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=7 pass=1 rcu=1\n");
    }
    return result;
}

static rs_status_t rs_pio_gpio_reset(void) {
    static const uint16_t loop[1] = {UINT16_C(0x9000)};
    rs_piolite_config_t config;
    rs_status_t result = rs_pio_load(loop, 1U, 0U, 0U, 0U);
    if (result != RS_OK) {
        return result;
    }
    config = rs_pio_config(&rs_pio_program, 0U, 31U, UINT32_C(0x80000000), 0U);
    result = rs_pio_setup(&config);
    if (result == RS_OK) {
        result = rs_piolite_start(&rs_pio_session);
    }
    if ((result == RS_OK) && (rs_piolite_wait_done(&rs_pio_session, RS_PIO_TIMEOUT) != RS_EIO)) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_piolite_abort_reset(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if ((result == RS_OK) && rs_pio_session.claimed) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_tiny_rcu_apply_reset(UINT32_C(2), RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_piolite_claim(&rs_pio_session, RS_PIO_TIMEOUT);
    }
    if (result == RS_OK) {
        result = rs_pio_finish_session();
    }
    if (result == RS_OK) {
        printf("PIOLITE_P3_CHECK id=8 pass=1 reset=1\n");
    }
    return result;
}

static void rs_pio_finish(uint8_t code) {
    rs_uart_status_t status;
    uint32_t timeout = RS_PIO_TIMEOUT;
    bool drained = false;

    while (timeout != 0U) {
        --timeout;
        if (rs_uart_get_status(&status) != RS_OK) {
            break;
        }
        if ((status.tx_level == 0U) && ((status.flags & UINT32_C(4)) == 0U)) {
            drained = true;
            break;
        }
    }
    rs_sysctrl_write_test_status((code == 0U) && drained, drained ? code : UINT8_C(250));
    for (;;) {
    }
}

int main(void) {
    const rs_uart_config_t console = {.source_clock_hz = UINT32_C(24000000),
                                      .baud_rate = UINT32_C(921600),
                                      .data_bits = 8U,
                                      .stop_bits = 1U,
                                      .parity = RS_UART_PARITY_NONE,
                                      .tx_watermark = 16U,
                                      .rx_watermark = 32U,
                                      .rx_timeout_bits = 32U,
                                      .tx_enable = true,
                                      .rx_enable = false};
    uint8_t code = 0U;

    if (rs_uart_configure(&console, RS_PIO_TIMEOUT) != RS_OK) {
        rs_sysctrl_write_test_status(false, 1U);
        for (;;) {
        }
    }
    rs_pio_program = (rs_piolite_program_t){0};
    rs_pio_session = (rs_piolite_session_t){0};
    rs_pio_shared = (rs_piolite_session_t){.sm = 1U};
    rs_pio_tx = (rs_dma_session_t){.channel = 3U};
    rs_pio_rx = (rs_dma_session_t){.channel = 2U};
    if ((code == 0U) && (rs_pio_discover() != RS_OK)) {
        code = 1U;
    }
    if ((code == 0U) && (rs_pio_gpio_sweep() != RS_OK)) {
        code = 2U;
    }
    if ((code == 0U) && (rs_pio_shared_input() != RS_OK)) {
        code = 3U;
    }
    if ((code == 0U) && (rs_pio_output() != RS_OK)) {
        code = 4U;
    }
    if ((code == 0U) && (rs_pio_direct_dma() != RS_OK)) {
        code = 5U;
    }
    if ((code == 0U) && (rs_pio_mixed_tcd() != RS_OK)) {
        code = 6U;
    }
    if ((code == 0U) && (rs_pio_rcu() != RS_OK)) {
        code = 7U;
    }
    if ((code == 0U) && (rs_pio_gpio_reset() != RS_OK)) {
        code = 8U;
    }
    if (code != 0U) {
        if (rs_pio_session.configured || rs_pio_session.closing) {
            (void)rs_piolite_abort_reset(&rs_pio_session, RS_PIO_TIMEOUT);
        }
        if (rs_pio_session.claimed) {
            (void)rs_piolite_release(&rs_pio_session, RS_PIO_TIMEOUT);
        }
        if (rs_pio_shared.configured || rs_pio_shared.closing) {
            (void)rs_piolite_abort_reset(&rs_pio_shared, RS_PIO_TIMEOUT);
        }
        if (rs_pio_shared.claimed) {
            (void)rs_piolite_release(&rs_pio_shared, RS_PIO_TIMEOUT);
        }
    }
    printf("PIOLITE_P3_RESULT code=%u\n", code);
    rs_pio_finish(code);
}
