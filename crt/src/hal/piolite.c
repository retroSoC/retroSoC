#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/piolite.h>

#if defined(RS_SOC_HAS_PIOLITE) && (RS_SOC_HAS_PIOLITE != 0U) && defined(RS_SOC_APB4_PIOLITE_BASE)
#define RS_PIOLITE_PRESENT 1
#endif

#ifdef RS_PIOLITE_PRESENT
#ifdef RS_PIOLITE_TEST_MMIO
extern volatile uint32_t rs_piolite_test_mmio[1024];
#define RS_PIOLITE_REG(offset) rs_piolite_test_mmio[(offset) / 4U]
#else
#define RS_PIOLITE_REG(offset) RS_SOC_REG32(RS_SOC_APB4_PIOLITE_BASE, (offset))
#endif
#define RS_PIOLITE_SM_REG(sm, offset)                                                              \
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_SM0_BASE + ((sm)*RS_PIOLITE_ABI_APB4_SM_STRIDE) + (offset))
#define RS_PIOLITE_BIND_ENABLE      UINT32_C(0x80000000)
#define RS_PIOLITE_EVENT_ERROR_MASK UINT32_C(0x00000026)

static bool rs_piolite_control_lock;
static uint32_t rs_piolite_allocated;
static uint8_t rs_piolite_references[RS_PIOLITE_ABI_APB4_IMEM_WORDS];
static rs_piolite_session_t *rs_piolite_sessions[RS_PIOLITE_ABI_APB4_SM_COUNT];

static uint32_t rs_piolite_window_mask(uint32_t base, uint32_t width) {
    if (width == 0U) {
        return 0U;
    }
    return (uint32_t)(UINT32_MAX >> (32U - width)) << base;
}

static uint32_t rs_piolite_region_mask(uint32_t base, uint32_t count) {
    return rs_piolite_window_mask(base, count);
}

static bool rs_piolite_instruction_valid(uint16_t word) {
    const uint32_t opcode = ((uint32_t)word >> 12U) & UINT32_C(0xF);
    const uint32_t delay = ((uint32_t)word >> 8U) & UINT32_C(0xF);
    const uint32_t operand = (uint32_t)word & UINT32_C(0xFF);
    bool valid = true;

    if (opcode > RS_PIOLITE_ABI_OPCODE_FLAG) {
        valid = false;
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_CTRL) {
        valid = ((operand & UINT32_C(0x1F)) == 0U) && ((operand >> 5U) <= 3U) &&
                (((operand >> 5U) != RS_PIOLITE_ABI_CTRL_HALT) || (delay == 0U));
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_IN) {
        valid = (operand >> 5U) <= RS_PIOLITE_ABI_IN_ZERO;
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_OUT) {
        const uint32_t destination = operand >> 5U;
        const uint32_t count = (operand & UINT32_C(0x1F)) == 0U ? 32U : (operand & UINT32_C(0x1F));
        valid = (destination <= RS_PIOLITE_ABI_OUT_DISCARD) &&
                (((destination != RS_PIOLITE_ABI_OUT_X) && (destination != RS_PIOLITE_ABI_OUT_Y)) ||
                 (count <= 16U));
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_MOVE) {
        valid = ((operand & UINT32_C(7)) == 0U) && (((operand >> 3U) & UINT32_C(7)) <= 5U);
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_FIFO) {
        valid = (operand & UINT32_C(0x3F)) == 0U;
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_WAIT) {
        valid = ((operand & UINT32_C(1)) == 0U) &&
                (((operand & UINT32_C(0x80)) == 0U) || (((operand >> 1U) & UINT32_C(0x1F)) <= 3U));
    } else if (opcode == RS_PIOLITE_ABI_OPCODE_FLAG) {
        valid = (operand & UINT32_C(0x1F)) == 0U;
    } else {
        valid = true;
    }
    return valid;
}

static uint32_t rs_piolite_irq_saved;

static uint32_t rs_piolite_irq_save(void) {
    uint32_t saved = 0U;
#ifdef RS_PIOLITE_TEST_MMIO
    extern uint32_t rs_piolite_test_irq_save(void);
    saved = rs_piolite_test_irq_save();
#elif defined(__riscv) && defined(CSR_ENABLE)
    __asm__ volatile("csrrci %0, mstatus, 8" : "=r"(saved)::"memory");
#endif
    return saved;
}

static void rs_piolite_irq_restore(uint32_t saved) {
#ifdef RS_PIOLITE_TEST_MMIO
    extern void rs_piolite_test_irq_restore(uint32_t state);
    rs_piolite_test_irq_restore(saved);
#elif defined(__riscv) && defined(CSR_ENABLE)
    if ((saved & UINT32_C(8)) != 0U) {
        __asm__ volatile("csrsi mstatus, 8" ::: "memory");
    }
#else
    (void)saved;
#endif
}

static bool rs_piolite_lock(void) {
    const uint32_t saved = rs_piolite_irq_save();
    if (rs_piolite_control_lock) {
        rs_piolite_irq_restore(saved);
        return false;
    }
    rs_piolite_irq_saved = saved;
    rs_piolite_control_lock = true;
    return true;
}

static void rs_piolite_unlock(void) {
    const uint32_t saved = rs_piolite_irq_saved;
    rs_piolite_irq_restore(saved);
    rs_piolite_control_lock = false;
}

static bool rs_piolite_session_valid(const rs_piolite_session_t *session) {
    return (session != NULL) && (session->sm < RS_PIOLITE_ABI_APB4_SM_COUNT) &&
           (session->configured || session->closing);
}

static rs_status_t rs_piolite_claim_check(const rs_piolite_session_t *session,
                                          bool require_claimed) {
    if (!rs_piolite_session_valid(session)) {
        return RS_EINVAL;
    }
    if (session->output_cleanup_pending || (session->recovery_mask != 0U) ||
        (require_claimed && !session->claimed)) {
        return RS_EIO;
    }
    if ((session->claimed && ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) &
                               session->claim_mask) != session->claim_mask)) ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) ==
         RS_PIOLITE_ABI_STATE_CLOSING)) {
        return RS_EIO;
    }
    return RS_OK;
}

static rs_status_t rs_piolite_dma_done(const rs_piolite_dma_t *dma) {
    rs_dma_status_t status;
    const rs_status_t result = rs_dma_get_status(dma->lease->channel, &status);

    if (result != RS_OK) {
        return result;
    }
    if (status.busy || status.suspended || !status.done || status.aborted || status.error ||
        (status.bytes_done != (dma->word_count * 4U)) || (status.remaining != 0U)) {
        return RS_EIO;
    }
    return RS_OK;
}

static uint32_t rs_piolite_transport_mask(const rs_piolite_session_t *session) {
    const uint32_t tx_bind = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TX_BIND);
    const uint32_t rx_bind = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_RX_BIND);
    uint32_t mask = 0U;

    if (session->dma[RS_PIOLITE_DMA_TX].acquired || session->dma[RS_PIOLITE_DMA_TX].bound ||
        (((tx_bind & RS_PIOLITE_BIND_ENABLE) != 0U) && ((tx_bind & 1U) == session->sm))) {
        mask |= UINT32_C(0x15);
    }
    if (session->dma[RS_PIOLITE_DMA_RX].acquired || session->dma[RS_PIOLITE_DMA_RX].bound ||
        (((rx_bind & RS_PIOLITE_BIND_ENABLE) != 0U) && ((rx_bind & 1U) == session->sm))) {
        mask |= UINT32_C(0x2A);
    }
    return mask;
}

static rs_status_t rs_piolite_complete_locked(const rs_piolite_session_t *session) {
    const uint32_t state =
        RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7);
    const uint32_t events = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_EVENTS);
    const uint32_t levels = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS);
    const uint32_t transport =
        RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) & rs_piolite_transport_mask(session);

    if (((events & RS_PIOLITE_EVENT_ERROR_MASK) != 0U) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U) ||
        (state == RS_PIOLITE_ABI_STATE_CLOSING) || ((transport & UINT32_C(0x30)) != 0U)) {
        return RS_EIO;
    }
    if ((state == RS_PIOLITE_ABI_STATE_HALTED) &&
        (((events & (UINT32_C(1) << RS_PIOLITE_ABI_EVENTS_HALT)) == 0U) || (levels != 0U) ||
         (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_COUNTS) != 0U))) {
        return RS_EIO;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        const rs_piolite_dma_t *dma = &session->dma[direction];
        rs_dma_status_t status;
        if (!dma->bound) {
            continue;
        }
        if (rs_dma_get_status(dma->lease->channel, &status) != RS_OK || status.aborted ||
            status.error || (status.busy && (status.bytes_done > (dma->word_count * 4U))) ||
            (!status.busy && !status.done) ||
            (status.done && (status.suspended || (status.bytes_done != (dma->word_count * 4U)) ||
                             (status.remaining != 0U)))) {
            return RS_EIO;
        }
        if (!status.done) {
            return RS_EBUSY;
        }
    }
    if ((state != RS_PIOLITE_ABI_STATE_HALTED) || ((transport & UINT32_C(0x0F)) != 0U)) {
        return RS_EBUSY;
    }
    return RS_OK;
}

static rs_status_t rs_piolite_wait_transport_idle(uint32_t mask, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_TEST_MMIO
    extern bool rs_piolite_test_recovery_stall(void);
    if (rs_piolite_test_recovery_stall()) {
        return RS_ETIMEOUT;
    }
#endif
    while (timeout-- != 0U) {
        if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) & mask) == 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_piolite_dma_recover(rs_piolite_dma_t *dma, bool tx, rs_timeout_t timeout) {
    const uint32_t mask = tx ? UINT32_C(0x05) : UINT32_C(0x02);
    rs_status_t result = rs_dma_session_abort_wait(dma->lease, timeout);

    if (result != RS_OK) {
        return result;
    }
    result = rs_piolite_wait_transport_idle(mask, timeout);
    if (result != RS_OK) {
        return result;
    }
    return rs_dma_session_reset(dma->lease);
}

static rs_status_t rs_piolite_config_check(const rs_piolite_session_t *session,
                                           const rs_piolite_config_t *config) {
    uint32_t required;

    if ((session == NULL) || (config == NULL) || (config->sm >= RS_PIOLITE_ABI_APB4_SM_COUNT) ||
        (session->sm != config->sm) || (config->program == NULL) || !config->program->loaded ||
        (config->program->word_count == 0U) ||
        (config->program->base >= RS_PIOLITE_ABI_APB4_IMEM_WORDS) ||
        (config->program->word_count > (RS_PIOLITE_ABI_APB4_IMEM_WORDS - config->program->base)) ||
        (config->divider == 0U) || (config->divider > UINT32_C(65535)) ||
        (config->entry >= config->program->word_count) ||
        (config->wrap_bottom >= config->program->word_count) ||
        (config->wrap_top >= config->program->word_count) ||
        (config->wrap_bottom > config->wrap_top) || (config->in_base > 31U) ||
        (config->out_base > 31U) || (config->set_base > 31U) || (config->in_width > 32U) ||
        (config->out_width > 32U) || (config->set_width > 8U) ||
        (config->in_width > (32U - config->in_base)) ||
        (config->out_width > (32U - config->out_base)) ||
        (config->set_width > (32U - config->set_base)) || (config->tx_bits == 0U) ||
        (config->tx_bits > 32U) || (config->rx_bits == 0U) || (config->rx_bits > 32U) ||
        (config->test_pin > 31U) || (config->test_flag > 3U) || (config->tx_low > 8U) ||
        (config->rx_high == 0U) || (config->rx_high > 8U) || (config->claim_mask == 0U)) {
        return RS_EINVAL;
    }
    if (session->started || session->closing || session->output_cleanup_pending ||
        (session->recovery_mask != 0U)) {
        return RS_EBUSY;
    }
    if (session->claimed || session->dma[RS_PIOLITE_DMA_TX].bound ||
        session->dma[RS_PIOLITE_DMA_RX].bound) {
        return RS_EBUSY;
    }
    required = rs_piolite_window_mask(config->in_base, config->in_width) |
               rs_piolite_window_mask(config->out_base, config->out_width) |
               rs_piolite_window_mask(config->set_base, config->set_width) |
               (config->test_pin_enable ? (UINT32_C(1) << config->test_pin) : 0U);
    if (((required & ~config->claim_mask) != 0U) ||
        ((config->output_mask & ~config->claim_mask) != 0U) ||
        ((config->initial_value & ~config->output_mask) != 0U) ||
        ((config->initial_oe & ~config->output_mask) != 0U) ||
        (config->initial_x > UINT32_C(65535)) || (config->initial_y > UINT32_C(65535))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

static rs_status_t rs_piolite_config_readback(const rs_piolite_config_t *config) {
    const uint32_t sm = config->sm;
    const uint32_t base = config->program->base;
    const uint32_t options = (config->autopull ? 1U : 0U) | (config->autopush ? 2U : 0U) |
                             (config->tx_right ? 4U : 0U) | (config->rx_right ? 8U : 0U) |
                             (config->test_pin_enable ? 16U : 0U);
    const uint32_t region = rs_piolite_region_mask(base, config->program->word_count);

#ifdef RS_PIOLITE_TEST_MMIO
    extern void rs_piolite_test_config_readback(void);
    rs_piolite_test_config_readback();
#endif
    if ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CONFIG) != options) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_DIV) != config->divider) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_PROGRAM) !=
         (base | (config->program->word_count << 8U) |
          ((config->program->base + config->entry) << 16U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WRAP) !=
         ((config->program->base + config->wrap_bottom) |
          ((config->program->base + config->wrap_top) << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CLAIM_MASK) != config->claim_mask) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) != config->output_mask) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_IN_PINS) !=
         (config->in_base | (config->in_width << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUT_PINS) !=
         (config->out_base | (config->out_width << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SET_PINS) !=
         (config->set_base | (config->set_width << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_VALUE) != config->initial_value) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_OE) != config->initial_oe) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_XY) !=
         (config->initial_x | (config->initial_y << 16U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_LIMITS) !=
         (config->tx_bits | (config->rx_bits << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TEST_SELECT) !=
         (config->test_pin | (config->test_flag << 8U))) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WATERMARKS) !=
         (config->tx_low | (config->rx_high << 8U))) ||
        ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) & region) != region)) {
        return RS_EIO;
    }
    return RS_OK;
}

static void rs_piolite_reference(const rs_piolite_program_t *program, bool add) {
    if (program == NULL) {
        return;
    }
    for (uint32_t index = 0U; index < program->word_count; ++index) {
        const uint32_t slot = program->base + index;
        if (add) {
            if (rs_piolite_references[slot] < UINT8_MAX) {
                ++rs_piolite_references[slot];
            }
        } else if (rs_piolite_references[slot] != 0U) {
            --rs_piolite_references[slot];
        } else {
            /* An unreferenced program has no count to decrement. */
        }
    }
}
#endif

rs_status_t rs_piolite_discover(rs_piolite_info_t *info) {
    if (info == NULL) {
        return RS_EINVAL;
    }
#ifdef RS_PIOLITE_PRESENT
    info->ip_id = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IP_ID);
    info->apb_version = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IP_VERSION);
    info->isa_version = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_ISA_VERSION);
    info->capability = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_CAPABILITY);
    info->routable_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_ROUTABLE_MASK);
    info->clock_hz = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_CLOCK_HZ);
    info->transport_status = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    if ((info->apb_version != RS_PIOLITE_ABI_APB4_VERSION_VALUE) ||
        (info->isa_version != RS_PIOLITE_ABI_APB4_ISA_VALUE)) {
        return RS_ENOTSUP;
    }
    return (info->ip_id == RS_PIOLITE_ABI_APB4_ID_VALUE) ? RS_OK : RS_EIO;
#else
    *info = (rs_piolite_info_t){0};
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_program_load(rs_piolite_program_t *program, const rs_piolite_image_t *image,
                                    uint32_t base) {
#ifdef RS_PIOLITE_PRESENT
    uint32_t region;
    rs_piolite_info_t info;
    rs_status_t result;
    bool saw_relocation[RS_PIOLITE_ABI_APB4_IMEM_WORDS] = {false};

    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if ((program == NULL) || (image == NULL) || (program->storage == NULL) ||
        (image->words == NULL) || program->loaded || (image->word_count == 0U) ||
        (image->word_count > RS_PIOLITE_ABI_APB4_IMEM_WORDS) ||
        (base >= RS_PIOLITE_ABI_APB4_IMEM_WORDS) ||
        (image->word_count > (RS_PIOLITE_ABI_APB4_IMEM_WORDS - base)) ||
        (program->capacity < image->word_count) || (image->entry >= image->word_count) ||
        (image->wrap_bottom >= image->word_count) || (image->wrap_top >= image->word_count) ||
        (image->wrap_bottom > image->wrap_top) ||
        ((image->relocation_count != 0U) && (image->relocation_sites == NULL))) {
        rs_piolite_unlock();
        return RS_EINVAL;
    }
    result = rs_piolite_discover(&info);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    if (image->isa_version != info.isa_version) {
        rs_piolite_unlock();
        return RS_ENOTSUP;
    }
    region = rs_piolite_region_mask(base, image->word_count);
    if (((rs_piolite_allocated & region) != 0U) || (info.transport_status != 0U)) {
        rs_piolite_unlock();
        return (info.transport_status != 0U) ? RS_EBUSY : RS_ENOSPC;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_ABI_APB4_SM_COUNT; ++sm) {
        if ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
            RS_PIOLITE_ABI_STATE_DISABLED) {
            rs_piolite_unlock();
            return RS_EBUSY;
        }
    }
    for (uint32_t index = 0U; index < image->word_count; ++index) {
        if (!rs_piolite_instruction_valid(image->words[index])) {
            rs_piolite_unlock();
            return RS_EFORMAT;
        }
        program->storage[index] = image->words[index];
    }
    for (uint32_t index = 0U; index < image->relocation_count; ++index) {
        const uint32_t site = image->relocation_sites[index];
        uint16_t word;
        uint32_t target;
        if ((site >= image->word_count) || saw_relocation[site] ||
            (((image->words[site] >> 12U) & UINT32_C(0xF)) != RS_PIOLITE_ABI_OPCODE_BRANCH)) {
            rs_piolite_unlock();
            return RS_EFORMAT;
        }
        saw_relocation[site] = true;
        target = (uint32_t)image->words[site] & UINT32_C(0x1F);
        if (target >= image->word_count) {
            rs_piolite_unlock();
            return RS_EFORMAT;
        }
        word = (uint16_t)(((uint32_t)program->storage[site] & UINT32_C(0xFFE0)) | (base + target));
        program->storage[site] = word;
    }
    for (uint32_t index = 0U; index < image->word_count; ++index) {
        const uint32_t opcode = ((uint32_t)program->storage[index] >> 12U) & UINT32_C(0xF);
        const uint32_t target = (uint32_t)program->storage[index] & UINT32_C(0x1F);
        if (!rs_piolite_instruction_valid(program->storage[index]) ||
            ((opcode == RS_PIOLITE_ABI_OPCODE_BRANCH) &&
             ((target < base) || (target >= (base + image->word_count))))) {
            rs_piolite_unlock();
            return RS_EFORMAT;
        }
    }
    for (uint32_t index = 0U; index < image->word_count; ++index) {
        RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_BASE + (index * 4U) + (base * 4U)) =
            program->storage[index];
    }
    for (uint32_t index = 0U; index < image->word_count; ++index) {
        if (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_BASE + (index * 4U) + (base * 4U)) !=
            program->storage[index]) {
            rs_piolite_unlock();
            return RS_EIO;
        }
    }
    if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) & region) != region) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    program->base = base;
    program->word_count = image->word_count;
    program->loaded = true;
    rs_piolite_allocated |= region;
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)program;
    (void)image;
    (void)base;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_program_unload(rs_piolite_program_t *program) {
#ifdef RS_PIOLITE_PRESENT
    uint32_t region;
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if ((program == NULL) || !program->loaded || (program->word_count == 0U) ||
        (program->base >= RS_PIOLITE_ABI_APB4_IMEM_WORDS) ||
        (program->word_count > (RS_PIOLITE_ABI_APB4_IMEM_WORDS - program->base))) {
        rs_piolite_unlock();
        return RS_EINVAL;
    }
    region = rs_piolite_region_mask(program->base, program->word_count);
    if ((rs_piolite_allocated & region) != region) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    for (uint32_t index = 0U; index < program->word_count; ++index) {
        if (rs_piolite_references[program->base + index] != 0U) {
            rs_piolite_unlock();
            return RS_EBUSY;
        }
    }
    rs_piolite_allocated &= ~region;
    program->loaded = false;
    program->base = 0U;
    program->word_count = 0U;
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)program;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_configure(rs_piolite_session_t *session, const rs_piolite_config_t *config) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result;
    uint32_t sm;
    const rs_piolite_program_t *old_program;

    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_config_check(session, config);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    sm = config->sm;
    if (((rs_piolite_sessions[sm] != NULL) && (rs_piolite_sessions[sm] != session)) ||
        session->claimed || session->closing || session->dma[0].acquired ||
        session->dma[1].acquired ||
        ((rs_piolite_sessions[sm ^ 1U] != NULL) &&
         ((RS_PIOLITE_SM_REG(sm ^ 1U, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) & config->output_mask) !=
          0U))) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    if ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
        RS_PIOLITE_ABI_STATE_DISABLED) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CONFIG) =
        (config->autopull ? 1U : 0U) | (config->autopush ? 2U : 0U) | (config->tx_right ? 4U : 0U) |
        (config->rx_right ? 8U : 0U) | (config->test_pin_enable ? 16U : 0U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_DIV) = config->divider;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_PROGRAM) =
        config->program->base | (config->program->word_count << 8U) |
        ((config->program->base + config->entry) << 16U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WRAP) =
        (config->program->base + config->wrap_bottom) |
        ((config->program->base + config->wrap_top) << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_IN_PINS) =
        config->in_base | (config->in_width << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUT_PINS) =
        config->out_base | (config->out_width << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SET_PINS) =
        config->set_base | (config->set_width << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CLAIM_MASK) = config->claim_mask;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) = config->output_mask;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_VALUE) = config->initial_value;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_OE) = config->initial_oe;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_XY) =
        config->initial_x | (config->initial_y << 16U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_LIMITS) =
        config->tx_bits | (config->rx_bits << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TEST_SELECT) =
        config->test_pin | (config->test_flag << 8U);
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WATERMARKS) =
        config->tx_low | (config->rx_high << 8U);
    result = rs_piolite_config_readback(config);
    if (result == RS_OK) {
        old_program = session->program;
        rs_piolite_reference(old_program, false);
        rs_piolite_reference(config->program, true);
        session->program = config->program;
        session->claim_mask = config->claim_mask;
        session->configured = true;
        rs_piolite_sessions[sm] = session;
    } else {
        if (session->program == NULL) {
            session->program = config->program;
            rs_piolite_reference(config->program, true);
        }
        session->configured = false;
        session->closing = true;
        rs_piolite_sessions[sm] = session;
    }
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    (void)config;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_claim(rs_piolite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    rs_piolite_session_t *other;
    uint32_t new_mask;
    rs_status_t result;
    if (!rs_piolite_session_valid(session) || !session->configured || session->closing ||
        (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (session->claimed) {
        return RS_EBUSY;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if (!session->configured || session->closing || session->output_cleanup_pending ||
        session->claimed || (session->recovery_mask != 0U)) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    other = rs_piolite_sessions[session->sm ^ 1U];
    new_mask = session->claim_mask & ~((other != NULL && other->claimed) ? other->claim_mask : 0U);
    session->recovery_mask = new_mask;
    result = (new_mask != 0U) ? rs_gpio_user_acquire(new_mask, timeout) : RS_OK;
    if ((result == RS_OK) && ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) &
                               session->claim_mask) == session->claim_mask)) {
        session->claimed = true;
        session->recovery_mask = 0U;
        rs_piolite_unlock();
        return RS_OK;
    }
    if ((new_mask == 0U) || (rs_gpio_user_release(new_mask, timeout) == RS_OK)) {
        session->recovery_mask = 0U;
    } else {
        session->closing = true;
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = RS_EIO;
    }
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_release(rs_piolite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    rs_piolite_session_t *other;
    uint32_t release_mask;
    rs_status_t result;
    if (!rs_piolite_session_valid(session) || !session->configured || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (!session->claimed) {
        return RS_EIO;
    }
    if (session->started || session->closing || (session->recovery_mask != 0U) ||
        session->dma[0].bound || session->dma[1].bound || session->dma[0].acquired ||
        session->dma[1].acquired ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) != 0U) ||
        ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) &
          rs_piolite_transport_mask(session)) != 0U)) {
        return RS_EBUSY;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if (!session->configured || !session->claimed || session->started || session->closing ||
        session->output_cleanup_pending || (session->recovery_mask != 0U) ||
        session->dma[0].bound || session->dma[1].bound || session->dma[0].acquired ||
        session->dma[1].acquired ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) != 0U) ||
        ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) &
          rs_piolite_transport_mask(session)) != 0U)) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    other = rs_piolite_sessions[session->sm ^ 1U];
    release_mask =
        session->claim_mask & ~((other != NULL && other->claimed) ? other->claim_mask : 0U);
    result = (release_mask != 0U) ? rs_gpio_user_release(release_mask, timeout) : RS_OK;
    if (result == RS_OK) {
        RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) = 0U;
#ifdef RS_PIOLITE_TEST_MMIO
        extern void rs_piolite_test_output_cleanup(void);
        rs_piolite_test_output_cleanup();
#endif
        if (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) != 0U) {
            session->output_cleanup_pending = true;
            session->recovery_mask = release_mask;
            if ((release_mask != 0U) && (rs_gpio_user_acquire(release_mask, timeout) == RS_OK)) {
                session->recovery_mask = 0U;
            } else if (release_mask != 0U) {
                session->closing = true;
            } else {
                session->recovery_mask = 0U;
            }
            rs_piolite_unlock();
            return RS_EIO;
        }
        session->output_cleanup_pending = false;
        session->claimed = false;
        rs_piolite_reference(session->program, false);
        if (rs_piolite_sessions[session->sm] == session) {
            rs_piolite_sessions[session->sm] = NULL;
        }
        session->configured = false;
        session->program = NULL;
        session->claim_mask = 0U;
    }
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_dma_bind(rs_piolite_session_t *session, rs_piolite_dma_direction_t direction,
                                rs_dma_session_t *lease, uintptr_t buffer, uint32_t capacity_bytes,
                                uint32_t word_count) {
#ifdef RS_PIOLITE_PRESENT
    rs_piolite_dma_t *dma;
    rs_piolite_session_t *other;
    rs_dma_config_t config = {0};
    uint32_t bytes;
    uint32_t bind;
    uint32_t offset;
    bool bind_written = false;
    rs_status_t result = rs_piolite_claim_check(session, true);

    if ((result != RS_OK) || (lease == NULL) ||
        ((uint32_t)direction > (uint32_t)RS_PIOLITE_DMA_RX) || session->started ||
        session->closing ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        (buffer == (uintptr_t)0U) || ((buffer & UINT32_C(3)) != 0U) || (word_count == 0U) ||
        (word_count > (UINT32_MAX / 4U))) {
        return (result != RS_OK) ? result : RS_EINVAL;
    }
    bytes = word_count * 4U;
    if ((capacity_bytes < bytes) || (buffer > UINT32_MAX) || (bytes > (UINT32_MAX - buffer))) {
        return RS_EINVAL;
    }
    dma = &session->dma[direction];
    if (rs_dma_supports_request((direction == RS_PIOLITE_DMA_TX)
                                    ? RS_DMA_REQUEST_PIOLITE_TX
                                    : RS_DMA_REQUEST_PIOLITE_RX) != RS_OK) {
        return RS_ENOTSUP;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    other = rs_piolite_sessions[session->sm ^ 1U];
    offset = (direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_ABI_APB4_TX_BIND
                                              : RS_PIOLITE_ABI_APB4_RX_BIND;
    bind = RS_PIOLITE_REG(offset);
    result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || session->started || session->closing || dma->bound || dma->acquired ||
        (session->dma[(direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_DMA_RX : RS_PIOLITE_DMA_TX]
             .bound &&
         (session->dma[(direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_DMA_RX : RS_PIOLITE_DMA_TX]
              .lease->channel == lease->channel)) ||
        (((bind & RS_PIOLITE_BIND_ENABLE) != 0U) && ((bind & 1U) != session->sm)) ||
        ((other != NULL) && (other->dma[direction].bound || other->dma[direction].acquired)) ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED)) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EBUSY;
    }
    result = rs_dma_session_acquire(lease, lease->channel);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    dma->acquired = true;
    dma->lease = lease;
    dma->buffer = buffer;
    dma->capacity_bytes = capacity_bytes;
    dma->word_count = word_count;
    config.kind =
        (direction == RS_PIOLITE_DMA_TX) ? RS_DMA_KIND_MM_TO_STREAM : RS_DMA_KIND_STREAM_TO_MM;
    config.request =
        (direction == RS_PIOLITE_DMA_TX) ? RS_DMA_REQUEST_PIOLITE_TX : RS_DMA_REQUEST_PIOLITE_RX;
    config.source = (direction == RS_PIOLITE_DMA_TX) ? buffer : (uintptr_t)0U;
    config.destination = (direction == RS_PIOLITE_DMA_RX) ? buffer : (uintptr_t)0U;
    config.byte_count = bytes;
    config.width = RS_DMA_WIDTH_32;
    config.source_increment = direction == RS_PIOLITE_DMA_TX;
    config.destination_increment = direction == RS_PIOLITE_DMA_RX;
    config.burst_beats = 1U;
    result = rs_dma_session_configure(lease, &config);
    bind = RS_PIOLITE_BIND_ENABLE | session->sm | (lease->channel << 8U);
    if (result == RS_OK) {
        bind_written = true;
        RS_PIOLITE_REG(offset) = bind;
#ifdef RS_PIOLITE_TEST_MMIO
        extern void rs_piolite_test_bind_write(uint32_t command);
        rs_piolite_test_bind_write(offset);
#endif
        if (RS_PIOLITE_REG(offset) != bind) {
            result = RS_EIO;
        }
    }
    if (result == RS_OK) {
        result = rs_dma_session_start(lease);
    }
    if (result == RS_OK) {
        dma->bound = true;
    } else {
        session->closing = true;
        if (bind_written) {
            RS_PIOLITE_REG(offset) = 0U;
            if (RS_PIOLITE_REG(offset) != 0U) {
                rs_piolite_unlock();
                return RS_EIO;
            }
        }
        if ((rs_dma_session_abort_wait(lease, 1U) == RS_OK) &&
            (rs_dma_session_reset(lease) == RS_OK) && (rs_dma_session_release(lease) == RS_OK)) {
            dma->acquired = false;
            dma->lease = NULL;
            session->closing = false;
        }
    }
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    (void)direction;
    (void)lease;
    (void)buffer;
    (void)capacity_bytes;
    (void)word_count;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_dma_unbind(rs_piolite_session_t *session,
                                  rs_piolite_dma_direction_t direction) {
#ifdef RS_PIOLITE_PRESENT
    rs_piolite_dma_t *dma;
    rs_status_t result = rs_piolite_claim_check(session, true);

    if ((result != RS_OK) || ((uint32_t)direction > (uint32_t)RS_PIOLITE_DMA_RX)) {
        return (result != RS_OK) ? result : RS_EINVAL;
    }
    dma = &session->dma[direction];
    if (!dma->bound || !dma->acquired) {
        return RS_EIO;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) &
          ((direction == RS_PIOLITE_DMA_TX) ? UINT32_C(0x15) : UINT32_C(0x2A))) != 0U) ||
        (rs_piolite_dma_done(dma) != RS_OK)) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EBUSY;
    }
    if (RS_PIOLITE_REG((direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                        : RS_PIOLITE_ABI_APB4_RX_BIND) !=
        (RS_PIOLITE_BIND_ENABLE | session->sm | (dma->lease->channel << 8U))) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    RS_PIOLITE_REG((direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                    : RS_PIOLITE_ABI_APB4_RX_BIND) = 0U;
    if (RS_PIOLITE_REG((direction == RS_PIOLITE_DMA_TX) ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                        : RS_PIOLITE_ABI_APB4_RX_BIND) != 0U) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    result = rs_dma_session_release(dma->lease);
    if (result == RS_OK) {
        dma->acquired = false;
        dma->bound = false;
        dma->lease = NULL;
    }
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    (void)direction;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_fifo_write(rs_piolite_session_t *session, const uint32_t *words,
                                  uint32_t word_count, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || (words == NULL) || (word_count == 0U) || (timeout == 0U)) {
        return (result != RS_OK) ? result : RS_EINVAL;
    }
    if (session->dma[RS_PIOLITE_DMA_TX].bound) {
        return RS_EBUSY;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || session->dma[RS_PIOLITE_DMA_TX].bound) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EBUSY;
    }
    for (uint32_t index = 0U; index < word_count; ++index) {
        rs_timeout_t remaining = timeout;
        while (((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) &
                 UINT32_C(0xF)) >= RS_PIOLITE_ABI_APB4_FIFO_DEPTH) &&
               (remaining-- != 0U)) {
        }
        if ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) & UINT32_C(0xF)) >=
            RS_PIOLITE_ABI_APB4_FIFO_DEPTH) {
            rs_piolite_unlock();
            return RS_ETIMEOUT;
        }
        RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_TXDATA) = words[index];
    }
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)session;
    (void)words;
    (void)word_count;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_fifo_read(rs_piolite_session_t *session, uint32_t *words,
                                 uint32_t word_count, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || (words == NULL) || (word_count == 0U) || (timeout == 0U)) {
        return (result != RS_OK) ? result : RS_EINVAL;
    }
    if (session->dma[RS_PIOLITE_DMA_RX].bound) {
        return RS_EBUSY;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || session->dma[RS_PIOLITE_DMA_RX].bound) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EBUSY;
    }
    for (uint32_t index = 0U; index < word_count; ++index) {
        rs_timeout_t remaining = timeout;
        while (((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) &
                 UINT32_C(0xF00)) == 0U) &&
               (remaining-- != 0U)) {
        }
        if ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) &
             UINT32_C(0xF00)) == 0U) {
            rs_piolite_unlock();
            return RS_ETIMEOUT;
        }
        words[index] = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_RXDATA);
    }
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)session;
    (void)words;
    (void)word_count;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

#ifdef RS_PIOLITE_PRESENT
static void rs_piolite_lifecycle(uint32_t offset, uint32_t sm) {
    RS_PIOLITE_REG(offset) = UINT32_C(1) << sm;
#ifdef RS_PIOLITE_TEST_MMIO
    extern void rs_piolite_test_lifecycle(uint32_t command, uint32_t selected);
    rs_piolite_test_lifecycle(offset, sm);
#endif
}
#endif

rs_status_t rs_piolite_start(rs_piolite_session_t *session) {
#ifdef RS_PIOLITE_PRESENT
    uint32_t state;
    uint32_t region;
    rs_status_t result = rs_piolite_claim_check(session, true);
    if (result != RS_OK) {
        return result;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || !session->program->loaded) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EIO;
    }
    state = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7);
    region = rs_piolite_region_mask(session->program->base, session->program->word_count);
    if ((result != RS_OK) || session->started || session->closing ||
        (state != RS_PIOLITE_ABI_STATE_DISABLED) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U) ||
        ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) & UINT32_C(0xF00)) !=
         0U) ||
        ((RS_PIOLITE_SM_REG(session->sm ^ 1U, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) &
          RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK)) != 0U) ||
        ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) & region) != region)) {
        rs_piolite_unlock();
        return (result != RS_OK) ? result : RS_EIO;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (session->dma[direction].acquired && !session->dma[direction].bound) {
            session->closing = true;
            rs_piolite_unlock();
            return RS_EIO;
        }
    }
    RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_EVENTS) = UINT32_C(0x3F);
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_START, session->sm);
    state = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7);
    if (((state != RS_PIOLITE_ABI_STATE_RUNNING) && (state != RS_PIOLITE_ABI_STATE_HALTED)) ||
        ((state == RS_PIOLITE_ABI_STATE_HALTED) &&
         ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_EVENTS) &
           (UINT32_C(1) << RS_PIOLITE_ABI_EVENTS_HALT)) == 0U))) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    session->started = true;
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)session;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_pause(rs_piolite_session_t *session) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result = rs_piolite_claim_check(session, true);
    if (result != RS_OK) {
        return result;
    }
    if (!session->started || !rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if (!session->started || ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) &
                               UINT32_C(7)) != RS_PIOLITE_ABI_STATE_RUNNING)) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_PAUSE, session->sm);
    result = ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) ==
              RS_PIOLITE_ABI_STATE_PAUSED)
                 ? RS_OK
                 : RS_EIO;
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_resume(rs_piolite_session_t *session) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result = rs_piolite_claim_check(session, true);
    if (result != RS_OK) {
        return result;
    }
    if (!session->started || !rs_piolite_lock()) {
        return RS_EBUSY;
    }
    if (!session->started || ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) &
                               UINT32_C(7)) != RS_PIOLITE_ABI_STATE_PAUSED)) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_RESUME, session->sm);
    result = ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) ==
              RS_PIOLITE_ABI_STATE_RUNNING)
                 ? RS_OK
                 : RS_EIO;
    rs_piolite_unlock();
    return result;
#else
    (void)session;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_disable(rs_piolite_session_t *session) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result = rs_piolite_claim_check(session, true);
    if (result != RS_OK) {
        return result;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    result = rs_piolite_claim_check(session, true);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if ((session->dma[direction].acquired && !session->dma[direction].bound) ||
            (session->dma[direction].bound &&
             (rs_piolite_dma_done(&session->dma[direction]) != RS_OK))) {
            rs_piolite_unlock();
            return RS_EBUSY;
        }
    }
    if (!session->started && (((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) &
                                UINT32_C(7)) != RS_PIOLITE_ABI_STATE_HALTED) &&
                              ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) &
                                UINT32_C(7)) != RS_PIOLITE_ABI_STATE_DISABLED))) {
        rs_piolite_unlock();
        return RS_EBUSY;
    }
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_DISABLE, session->sm);
    if ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
        RS_PIOLITE_ABI_STATE_DISABLED) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    session->started = false;
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)session;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_wait_done(rs_piolite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    const rs_status_t result = rs_piolite_claim_check(session, true);
    if ((result != RS_OK) || !session->started || (timeout == 0U)) {
        return (result != RS_OK) ? result : RS_EINVAL;
    }
    while (timeout-- != 0U) {
        rs_status_t completion;
        if (!rs_piolite_lock()) {
            return RS_EBUSY;
        }
        completion = rs_piolite_complete_locked(session);
        rs_piolite_unlock();
        if (completion == RS_OK) {
            if (!rs_piolite_lock()) {
                return RS_EBUSY;
            }
            completion = rs_piolite_complete_locked(session);
            if (completion == RS_OK) {
                session->started = false;
            }
            rs_piolite_unlock();
            return completion;
        }
        if (completion != RS_EBUSY) {
            if ((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) ==
                RS_PIOLITE_ABI_STATE_CLOSING) {
                session->closing = true;
            }
            return completion;
        }
    }
    return RS_ETIMEOUT;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_abort_reset(rs_piolite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PIOLITE_PRESENT
    rs_status_t result;
    if (!rs_piolite_session_valid(session) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    const bool output_cleanup = session->output_cleanup_pending;
    if (session->output_cleanup_pending) {
        RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) = 0U;
#ifdef RS_PIOLITE_TEST_MMIO
        extern void rs_piolite_test_output_cleanup(void);
        rs_piolite_test_output_cleanup();
#endif
        if (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) != 0U) {
            rs_piolite_unlock();
            return RS_EIO;
        }
    }
    session->closing = true;
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_ABORT, session->sm);
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (session->dma[direction].acquired) {
            result = rs_piolite_dma_recover(&session->dma[direction],
                                            direction == RS_PIOLITE_DMA_TX, timeout);
            if (result != RS_OK) {
                rs_piolite_unlock();
                return result;
            }
        }
    }
    result = rs_piolite_wait_transport_idle(rs_piolite_transport_mask(session) & UINT32_C(0x07),
                                            timeout);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    rs_piolite_lifecycle(RS_PIOLITE_ABI_APB4_SM_RESET, session->sm);
    result = rs_piolite_wait_transport_idle(rs_piolite_transport_mask(session), timeout);
    if (result != RS_OK) {
        rs_piolite_unlock();
        return result;
    }
    if (((RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & UINT32_C(7)) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) != 0U) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_EVENTS) != 0U) ||
        (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U) ||
        (((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TX_BIND) & UINT32_C(1)) == session->sm) &&
         ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TX_BIND) & RS_PIOLITE_BIND_ENABLE) != 0U)) ||
        (((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_RX_BIND) & UINT32_C(1)) == session->sm) &&
         ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_RX_BIND) & RS_PIOLITE_BIND_ENABLE) != 0U))) {
        rs_piolite_unlock();
        return RS_EIO;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (session->dma[direction].acquired) {
            result = rs_dma_session_release(session->dma[direction].lease);
            if (result != RS_OK) {
                rs_piolite_unlock();
                return result;
            }
        }
        session->dma[direction].acquired = false;
        session->dma[direction].bound = false;
        session->dma[direction].lease = NULL;
    }
    if (session->claimed || (session->recovery_mask != 0U)) {
        const rs_piolite_session_t *other = rs_piolite_sessions[session->sm ^ 1U];
        const uint32_t owned_mask = session->claimed ? session->claim_mask : session->recovery_mask;
        const uint32_t release_mask =
            owned_mask & ~((other != NULL && other->claimed) ? other->claim_mask : 0U);
        result = (release_mask != 0U) ? rs_gpio_user_release(release_mask, timeout) : RS_OK;
        if (result != RS_OK) {
            rs_piolite_unlock();
            return result;
        }
        session->claimed = false;
        session->recovery_mask = 0U;
    }
    if (!session->configured) {
        RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) = 0U;
        if (RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) != 0U) {
            rs_piolite_unlock();
            return RS_EIO;
        }
        rs_piolite_reference(session->program, false);
        session->program = NULL;
        session->claim_mask = 0U;
        if (rs_piolite_sessions[session->sm] == session) {
            rs_piolite_sessions[session->sm] = NULL;
        }
    }
    if (output_cleanup && !session->claimed && (session->program != NULL)) {
        rs_piolite_reference(session->program, false);
        session->configured = false;
        session->program = NULL;
        session->claim_mask = 0U;
        if (rs_piolite_sessions[session->sm] == session) {
            rs_piolite_sessions[session->sm] = NULL;
        }
    }
    if (output_cleanup) {
        session->output_cleanup_pending = false;
    }
    session->started = false;
    session->closing = false;
    rs_piolite_unlock();
    return RS_OK;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_piolite_get_status(const rs_piolite_session_t *session,
                                  rs_piolite_status_t *status) {
    if ((session == NULL) || (status == NULL) || (session->sm >= RS_PIOLITE_ABI_APB4_SM_COUNT)) {
        return RS_EINVAL;
    }
#ifdef RS_PIOLITE_PRESENT
    status->status = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_STATUS);
    status->events = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_EVENTS);
    status->fault = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FAULT);
    status->fifo_levels = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS);
    status->transport_status = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    status->owned_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK);
    status->pc = RS_PIOLITE_SM_REG(session->sm, RS_PIOLITE_ABI_APB4_SM_PC);
    if (!rs_piolite_lock()) {
        return RS_EBUSY;
    }
    status->complete = session->configured && (rs_piolite_complete_locked(session) == RS_OK);
    rs_piolite_unlock();
    return RS_OK;
#else
    *status = (rs_piolite_status_t){0};
    return RS_ENOTSUP;
#endif
}
