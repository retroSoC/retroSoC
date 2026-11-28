#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/piolite.h>

#if defined(RS_PIOLITE_TEST_MMIO)
extern volatile uint32_t rs_piolite_test_mmio[1024];
#define RS_PIOLITE_REG(offset) rs_piolite_test_mmio[(offset) / 4U]
#define RS_PIOLITE_PRESENT     1
#elif defined(RS_SOC_TINY) && defined(RS_SOC_HAS_PIOLITE)
#define RS_PIOLITE_REG(offset) RS_SOC_REG32(RS_SOC_APB4_PIOLITE_BASE, (offset))
#define RS_PIOLITE_PRESENT     1
#else
#define RS_PIOLITE_PRESENT 0
#endif

#define RS_PIOLITE_SM_REG(sm, offset)                                                              \
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_SM0_BASE + ((sm)*RS_PIOLITE_ABI_APB4_SM_STRIDE) + (offset))
#define RS_PIOLITE_BIND_ENABLE (UINT32_C(1) << 31U)

#ifdef RS_PIOLITE_TEST_MMIO
uint32_t rs_piolite_test_irq_save(void);
void rs_piolite_test_irq_restore(uint32_t saved);
#endif

static uint32_t rs_piolite_lock(void) {
    uint32_t saved = 0U;
#ifdef RS_PIOLITE_TEST_MMIO
    saved = rs_piolite_test_irq_save();
#elif defined(__riscv) && defined(CSR_ENABLE)
    __asm__ volatile("csrrci %0, mstatus, 8" : "=r"(saved)::"memory");
#endif
    return saved;
}

static void rs_piolite_unlock(uint32_t saved) {
#ifdef RS_PIOLITE_TEST_MMIO
    rs_piolite_test_irq_restore(saved);
#elif defined(__riscv) && defined(CSR_ENABLE)
    if ((saved & UINT32_C(8)) != 0U) {
        __asm__ volatile("csrsi mstatus, 8" ::: "memory");
    }
#else
    (void)saved;
#endif
}

static rs_status_t rs_piolite_active(const rs_piolite_session_t *session) {
    if (session == NULL) {
        return RS_EINVAL;
    }
    if (!RS_PIOLITE_PRESENT) {
        return RS_ENOTSUP;
    }
    return (session->active && !session->recovery_failed) ? RS_OK : RS_EIO;
}

static uint32_t rs_piolite_binding(uint32_t direction) {
    return RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                     : RS_PIOLITE_ABI_APB4_RX_BIND);
}

static bool rs_piolite_direction_bound_sm(uint32_t direction, uint32_t sm) {
    const uint32_t binding = rs_piolite_binding(direction);
    return ((binding & RS_PIOLITE_BIND_ENABLE) != 0U) && ((binding & 1U) == sm);
}

static bool rs_piolite_sm_bound(uint32_t sm) {
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (rs_piolite_direction_bound_sm(direction, sm)) {
            return true;
        }
    }
    return false;
}

static uint32_t rs_piolite_sm_dma_mask(uint32_t sm) {
    uint32_t mask = 0U;
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (rs_piolite_direction_bound_sm(direction, sm)) {
            mask |= UINT32_C(0x15) << direction;
        }
    }
    return mask;
}

static bool rs_piolite_sm_dma_active(uint32_t sm) {
    const uint32_t transport = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    return (transport & rs_piolite_sm_dma_mask(sm)) != 0U;
}

static bool rs_piolite_direction_dma_active(uint32_t direction) {
    const uint32_t transport = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    return (transport & (UINT32_C(0x15) << direction)) != 0U;
}

static uint32_t rs_piolite_window_mask(uint32_t base, uint32_t width) {
    if (width == 0U) {
        return 0U;
    }
    if (width == 32U) {
        return UINT32_MAX;
    }
    return ((UINT32_C(1) << width) - 1U) << base;
}

static uint64_t rs_piolite_expected_bytes(uint32_t items, uint32_t item_bits, uint32_t shift_bits) {
    if (shift_bits == 0U) {
        return UINT64_MAX;
    }
    return ((((uint64_t)items * item_bits) + shift_bits - 1U) / shift_bits) * 4U;
}

static uint32_t rs_piolite_shift_bits(const rs_piolite_session_t *session, uint32_t sm,
                                      uint32_t direction) {
    if ((session == NULL) || (sm >= RS_PIOLITE_SM_COUNT)) {
        return 0U;
    }
    return direction == RS_PIOLITE_TX ? (session->sm[sm].shift_limits & 0x3FU)
                                      : ((session->sm[sm].shift_limits >> 8U) & 0x3FU);
}

static uint32_t rs_piolite_window(uint32_t value) {
    return (value & UINT32_C(0x1F)) | (((value >> 8U) & UINT32_C(0x3F)) << 8U);
}

static bool rs_piolite_config_legal(const rs_piolite_sm_config_t *config) {
    const uint32_t base = config->program & UINT32_C(0x1F);
    const uint32_t length = (config->program >> 8U) & UINT32_C(0x3F);
    const uint32_t entry = (config->program >> 16U) & UINT32_C(0x1F);
    const uint32_t bottom = config->wrap & UINT32_C(0x1F);
    const uint32_t top = (config->wrap >> 8U) & UINT32_C(0x1F);
    const uint32_t in = rs_piolite_window(config->in_pins);
    const uint32_t out = rs_piolite_window(config->out_pins);
    const uint32_t set = rs_piolite_window(config->set_pins);
    const uint32_t in_mask = rs_piolite_window_mask(in & 0x1FU, (in >> 8U) & 0x3FU);
    const uint32_t out_mask = rs_piolite_window_mask(out & 0x1FU, (out >> 8U) & 0x3FU);
    const uint32_t set_mask = rs_piolite_window_mask(set & 0x1FU, (set >> 8U) & 0x3FU);
    const uint32_t tx_bits = config->shift_limits & UINT32_C(0x3F);
    const uint32_t rx_bits = (config->shift_limits >> 8U) & UINT32_C(0x3F);
    const uint32_t tx_low = config->watermarks & UINT32_C(0xF);
    const uint32_t rx_high = (config->watermarks >> 8U) & UINT32_C(0xF);

    if (((config->program & ~UINT32_C(0x001F3F1F)) != 0U) ||
        ((config->wrap & ~UINT32_C(0x1F1F)) != 0U) ||
        ((config->in_pins & ~UINT32_C(0x3F1F)) != 0U) ||
        ((config->out_pins & ~UINT32_C(0x3F1F)) != 0U) ||
        ((config->set_pins & ~UINT32_C(0x3F1F)) != 0U) ||
        ((config->shift_limits & ~UINT32_C(0x3F3F)) != 0U) ||
        ((config->test_select & ~UINT32_C(0x3FF)) != 0U) ||
        ((config->watermarks & ~UINT32_C(0xF0F)) != 0U)) {
        return false;
    }
    if ((config->item_bits == 0U) || (config->item_bits > 32U) ||
        (config->tx_tail_policy > RS_PIOLITE_TAIL_APPLICATION) ||
        (config->rx_tail_policy > RS_PIOLITE_TAIL_APPLICATION) ||
        (rs_piolite_expected_bytes(config->tx_items, config->item_bits, tx_bits) > UINT32_MAX) ||
        (rs_piolite_expected_bytes(config->rx_items, config->item_bits, rx_bits) > UINT32_MAX)) {
        return false;
    }
    if ((config->divider == 0U) || (length == 0U) || (length > 32U) || ((base + length) > 32U) ||
        (entry < base) || (entry >= (base + length)) || (bottom < base) ||
        (bottom >= (base + length)) || (top < base) || (top >= (base + length)) || (bottom > top) ||
        (tx_bits == 0U) || (tx_bits > 32U) || (rx_bits == 0U) || (rx_bits > 32U) || (tx_low > 8U) ||
        (rx_high == 0U) || (rx_high > 8U) || ((config->config & ~UINT32_C(0x1F)) != 0U)) {
        return false;
    }
    if ((((in >> 8U) + (in & 0x1FU)) > 32U) || (((out >> 8U) + (out & 0x1FU)) > 32U) ||
        (((set >> 8U) + (set & 0x1FU)) > 32U) || (((set >> 8U) & 0x3FU) > 8U)) {
        return false;
    }
    if ((((in_mask | out_mask | set_mask) & ~config->claim_mask) != 0U) ||
        (((out_mask | set_mask) & ~config->output_mask) != 0U) ||
        ((config->output_mask & ~config->claim_mask) != 0U) ||
        ((config->initial_value & ~config->output_mask) != 0U) ||
        ((config->initial_oe & ~config->output_mask) != 0U)) {
        return false;
    }
    if (((config->config & (UINT32_C(1) << RS_PIOLITE_ABI_CONFIG_TEST_PIN_ENABLE)) != 0U) &&
        ((config->claim_mask & (UINT32_C(1) << (config->test_select & 0x1FU))) == 0U)) {
        return false;
    }
    return true;
}

static bool rs_piolite_instruction_legal(uint16_t word, uint32_t word_count) {
    const uint32_t opcode = (uint32_t)word >> 12U;
    const uint32_t delay = ((uint32_t)word >> 8U) & UINT32_C(0xF);
    const uint32_t operand = (uint32_t)word & UINT32_C(0xFF);
    const uint32_t count = (operand & 0x1FU) == 0U ? 32U : (operand & 0x1FU);

    if (opcode > RS_PIOLITE_ABI_OPCODE_FLAG) {
        return false;
    }
    switch (opcode) {
    case RS_PIOLITE_ABI_OPCODE_CTRL:
        return ((operand & 0x1FU) == 0U) && ((operand >> 5U) <= 3U) &&
               !(((operand >> 5U) == RS_PIOLITE_ABI_CTRL_HALT) && (delay != 0U));
    case RS_PIOLITE_ABI_OPCODE_SET_PIN:
    case RS_PIOLITE_ABI_OPCODE_SET_DIR:
    case RS_PIOLITE_ABI_OPCODE_SET_COUNT:
        return true;
    case RS_PIOLITE_ABI_OPCODE_IN:
        return (operand >> 5U) <= 3U;
    case RS_PIOLITE_ABI_OPCODE_OUT:
        return ((operand >> 5U) <= 4U) && (((operand >> 5U) < 2U) || (count <= 16U));
    case RS_PIOLITE_ABI_OPCODE_MOVE:
        return ((operand & 0x7U) == 0U) && (((operand >> 3U) & 0x7U) <= 5U) &&
               ((operand >> 6U) <= 3U);
    case RS_PIOLITE_ABI_OPCODE_FIFO:
        return (operand & 0x3FU) == 0U;
    case RS_PIOLITE_ABI_OPCODE_WAIT:
        return ((operand & 1U) == 0U) &&
               (((operand & 0x80U) == 0U) || (((operand >> 1U) & 0x1FU) <= 3U));
    case RS_PIOLITE_ABI_OPCODE_BRANCH:
        return (operand & 0x1FU) < word_count;
    case RS_PIOLITE_ABI_OPCODE_FLAG:
        return (operand & 0x1FU) == 0U;
    default:
        return false;
    }
}

static bool rs_piolite_program_equal(const rs_piolite_program_t *left,
                                     const rs_piolite_program_t *right) {
    if ((left->isa_version != right->isa_version) || (left->word_count != right->word_count) ||
        (left->entry != right->entry) || (left->wrap_bottom != right->wrap_bottom) ||
        (left->wrap_top != right->wrap_top) ||
        (left->relocation_count != right->relocation_count) || (left->in_base != right->in_base) ||
        (left->in_width != right->in_width) || (left->out_base != right->out_base) ||
        (left->out_width != right->out_width) || (left->set_base != right->set_base) ||
        (left->set_width != right->set_width) || (left->tx_bits != right->tx_bits) ||
        (left->tx_right != right->tx_right) || (left->autopull != right->autopull) ||
        (left->rx_bits != right->rx_bits) || (left->rx_right != right->rx_right) ||
        (left->autopush != right->autopush) || (left->test_pin != right->test_pin) ||
        (left->test_flag != right->test_flag) ||
        (left->test_pin_enable != right->test_pin_enable) ||
        (left->claim_mask != right->claim_mask) || (left->flag_mask != right->flag_mask) ||
        (left->tx_items != right->tx_items) || (left->rx_items != right->rx_items) ||
        (left->item_bits != right->item_bits) || (left->clock_ticks != right->clock_ticks) ||
        (left->stretchable != right->stretchable)) {
        return false;
    }
    for (uint32_t index = 0U; index < left->word_count; ++index) {
        if (left->words[index] != right->words[index]) {
            return false;
        }
    }
    for (uint32_t index = 0U; index < left->relocation_count; ++index) {
        if (left->relocation_sites[index] != right->relocation_sites[index]) {
            return false;
        }
    }
    return true;
}

static rs_status_t rs_piolite_program_validate(const rs_piolite_program_t *program) {
    uint32_t expected_claim;
    uint32_t expected_flags = 0U;
    bool test_used = false;

    if ((program == NULL) || (program->words == NULL) ||
        (program->isa_version != RS_PIOLITE_ABI_APB4_ISA_VALUE) || (program->word_count == 0U) ||
        (program->word_count > RS_PIOLITE_IMEM_WORDS) || (program->entry >= program->word_count) ||
        (program->wrap_bottom >= program->word_count) ||
        (program->wrap_top >= program->word_count) || (program->wrap_bottom > program->wrap_top) ||
        ((program->relocation_count != 0U) && (program->relocation_sites == NULL)) ||
        (program->relocation_count > program->word_count) || (program->in_base > 31U) ||
        (program->in_width > 32U) || ((program->in_base + program->in_width) > 32U) ||
        (program->out_base > 31U) || (program->out_width > 32U) ||
        ((program->out_base + program->out_width) > 32U) || (program->set_base > 31U) ||
        (program->set_width > 8U) || ((program->set_base + program->set_width) > 32U) ||
        (program->tx_bits == 0U) || (program->tx_bits > 32U) || (program->rx_bits == 0U) ||
        (program->rx_bits > 32U) || (program->tx_right > 1U) || (program->autopull > 1U) ||
        (program->rx_right > 1U) || (program->autopush > 1U) || (program->test_flag > 3U) ||
        ((program->test_pin != RS_PIOLITE_TEST_PIN_NONE) && (program->test_pin > 31U)) ||
        (program->test_pin_enable > 1U) || (program->item_bits == 0U) ||
        (program->item_bits > 32U) || (program->clock_ticks == 0U) || (program->stretchable > 1U) ||
        (rs_piolite_expected_bytes(program->tx_items, program->item_bits, program->tx_bits) >
         UINT32_MAX) ||
        (rs_piolite_expected_bytes(program->rx_items, program->item_bits, program->rx_bits) >
         UINT32_MAX)) {
        return RS_EFORMAT;
    }
    for (uint32_t index = 0U; index < program->relocation_count; ++index) {
        const uint32_t site = program->relocation_sites[index];
        if ((site >= program->word_count) ||
            (((uint32_t)program->words[site] >> 12U) != RS_PIOLITE_ABI_OPCODE_BRANCH) ||
            ((index != 0U) && (program->relocation_sites[index - 1U] >= site))) {
            return RS_EFORMAT;
        }
    }
    expected_claim = rs_piolite_window_mask(program->in_base, program->in_width) |
                     rs_piolite_window_mask(program->out_base, program->out_width) |
                     rs_piolite_window_mask(program->set_base, program->set_width);
    for (uint32_t index = 0U; index < program->word_count; ++index) {
        const uint16_t word = program->words[index];
        const uint32_t opcode = (uint32_t)word >> 12U;
        const uint32_t operand = (uint32_t)word & UINT32_C(0xFF);
        const uint32_t count = (operand & 0x1FU) == 0U ? 32U : (operand & 0x1FU);
        if (!rs_piolite_instruction_legal(word, program->word_count)) {
            return RS_EFORMAT;
        }
        if ((opcode == RS_PIOLITE_ABI_OPCODE_IN) && ((operand >> 5U) == RS_PIOLITE_ABI_IN_PINS) &&
            (count > program->in_width)) {
            return RS_EFORMAT;
        }
        if ((opcode == RS_PIOLITE_ABI_OPCODE_OUT) &&
            (((operand >> 5U) == RS_PIOLITE_ABI_OUT_PINS) ||
             ((operand >> 5U) == RS_PIOLITE_ABI_OUT_DIRECTIONS)) &&
            (count > program->out_width)) {
            return RS_EFORMAT;
        }
        if (((opcode == RS_PIOLITE_ABI_OPCODE_SET_PIN) ||
             (opcode == RS_PIOLITE_ABI_OPCODE_SET_DIR)) &&
            (program->set_width == 0U)) {
            return RS_EFORMAT;
        }
        if (opcode == RS_PIOLITE_ABI_OPCODE_WAIT) {
            if ((operand & 0x80U) != 0U) {
                expected_flags |= UINT32_C(1) << ((operand >> 1U) & 0x1FU);
            } else {
                expected_claim |= UINT32_C(1) << ((operand >> 1U) & 0x1FU);
            }
        } else if (opcode == RS_PIOLITE_ABI_OPCODE_FLAG) {
            expected_flags |= UINT32_C(1) << ((operand >> 5U) & 0x3U);
        } else if (opcode == RS_PIOLITE_ABI_OPCODE_BRANCH) {
            if ((operand >> 5U) == RS_PIOLITE_ABI_BRANCH_TEST_PIN_HIGH) {
                if (program->test_pin == RS_PIOLITE_TEST_PIN_NONE) {
                    return RS_EFORMAT;
                }
                test_used = true;
                expected_claim |= UINT32_C(1) << program->test_pin;
            } else if ((operand >> 5U) == RS_PIOLITE_ABI_BRANCH_TEST_FLAG_SET) {
                expected_flags |= UINT32_C(1) << program->test_flag;
            } else {
                /* Other branch conditions use no additional pin or flag. */
            }
        } else {
            /* No additional resource is referenced by this instruction. */
        }
    }
    if ((program->claim_mask != expected_claim) || (program->flag_mask != expected_flags) ||
        (program->test_pin_enable != (test_used ? 1U : 0U))) {
        return RS_EFORMAT;
    }
    return RS_OK;
}

static uint16_t rs_piolite_relocate(const rs_piolite_program_t *program, uint32_t base,
                                    uint32_t index) {
    uint16_t word = program->words[index];
    if (((uint32_t)word >> 12U) == RS_PIOLITE_ABI_OPCODE_BRANCH) {
        const uint32_t target = base + ((uint32_t)word & 0x1FU);
        word = (uint16_t)((word & ~UINT16_C(0x1F)) | (uint16_t)target);
    }
    return word;
}

static rs_status_t rs_piolite_unlocked_probe(rs_piolite_info_t *info) {
    if (info == NULL) {
        return RS_EINVAL;
    }
    if (!RS_PIOLITE_PRESENT) {
        info->capability = 0U;
        return RS_ENOTSUP;
    }
    info->ip_id = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IP_ID);
    info->apb_version = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IP_VERSION);
    info->isa_version = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_ISA_VERSION);
    info->capability = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_CAPABILITY);
    info->routable_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_ROUTABLE_MASK);
    info->clock_hz = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_CLOCK_HZ);
    if ((info->ip_id != RS_PIOLITE_ABI_APB4_ID_VALUE) ||
        (info->apb_version != RS_PIOLITE_ABI_APB4_VERSION_VALUE) ||
        (info->isa_version != RS_PIOLITE_ABI_APB4_ISA_VALUE) ||
        (info->capability != RS_PIOLITE_ABI_APB4_CAPABILITY_VALUE) ||
        (info->routable_mask != RS_PIOLITE_ABI_APB4_ROUTES_VALUE)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_session_init(rs_piolite_session_t *session) {
    if (session == NULL) {
        return RS_EINVAL;
    }
    if (!RS_PIOLITE_PRESENT) {
        return RS_ENOTSUP;
    }
    *session = (rs_piolite_session_t){0};
    session->next_handle = 1U;
    session->active = true;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_program_config(const rs_piolite_program_t *program,
                                                      const rs_piolite_allocation_t *allocation,
                                                      uint32_t sm, rs_piolite_sm_config_t *config) {
    if ((program == NULL) || (allocation == NULL) || (config == NULL) ||
        (sm >= RS_PIOLITE_SM_COUNT) || !allocation->published || (allocation->program != program) ||
        ((allocation->base + allocation->word_count) > RS_PIOLITE_IMEM_WORDS)) {
        return RS_EINVAL;
    }
    *config = (rs_piolite_sm_config_t){0};
    config->divider = 1U;
    config->program = allocation->base | ((uint32_t)allocation->word_count << 8U) |
                      ((uint32_t)(allocation->base + program->entry) << 16U);
    config->wrap = (allocation->base + program->wrap_bottom) |
                   ((uint32_t)(allocation->base + program->wrap_top) << 8U);
    config->in_pins = program->in_base | ((uint32_t)program->in_width << 8U);
    config->out_pins = program->out_base | ((uint32_t)program->out_width << 8U);
    config->set_pins = program->set_base | ((uint32_t)program->set_width << 8U);
    config->claim_mask = program->claim_mask;
    config->output_mask = rs_piolite_window_mask(program->out_base, program->out_width) |
                          rs_piolite_window_mask(program->set_base, program->set_width);
    config->shift_limits = program->tx_bits | ((uint32_t)program->rx_bits << 8U);
    config->test_select =
        ((program->test_pin == RS_PIOLITE_TEST_PIN_NONE) ? 0U : program->test_pin) |
        ((uint32_t)program->test_flag << 8U);
    config->watermarks = RS_PIOLITE_ABI_APB4_WATERMARKS_RESET;
    config->tx_items = program->tx_items;
    config->rx_items = program->rx_items;
    config->item_bits = program->item_bits;
    config->tx_tail_policy = (program->autopull != 0U) && (program->tx_items != 0U)
                                 ? RS_PIOLITE_TAIL_ZERO
                                 : RS_PIOLITE_TAIL_APPLICATION;
    config->rx_tail_policy = (program->autopush != 0U) && (program->rx_items != 0U)
                                 ? RS_PIOLITE_TAIL_ZERO
                                 : RS_PIOLITE_TAIL_APPLICATION;
    config->config = (program->autopull << RS_PIOLITE_ABI_CONFIG_AUTOPULL) |
                     (program->autopush << RS_PIOLITE_ABI_CONFIG_AUTOPUSH) |
                     (program->tx_right << RS_PIOLITE_ABI_CONFIG_TX_RIGHT) |
                     (program->rx_right << RS_PIOLITE_ABI_CONFIG_RX_RIGHT) |
                     (program->test_pin_enable << RS_PIOLITE_ABI_CONFIG_TEST_PIN_ENABLE);
    return rs_piolite_config_legal(config) ? RS_OK : RS_EFORMAT;
}

static rs_status_t rs_piolite_write_config(rs_piolite_session_t *session, uint32_t sm,
                                           const rs_piolite_sm_config_t *config) {
    if (!rs_piolite_config_legal(config)) {
        return RS_EIO;
    }
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CONFIG) = config->config;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_DIV) = config->divider;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_PROGRAM) = config->program;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WRAP) = config->wrap;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_IN_PINS) = config->in_pins;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUT_PINS) = config->out_pins;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SET_PINS) = config->set_pins;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CLAIM_MASK) = config->claim_mask;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) = config->output_mask;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_VALUE) = config->initial_value;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_OE) = config->initial_oe;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_XY) = config->initial_xy;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_LIMITS) = config->shift_limits;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TEST_SELECT) = config->test_select;
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WATERMARKS) = config->watermarks;
    if ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CONFIG) != config->config) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_DIV) != config->divider) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_PROGRAM) != config->program) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WRAP) != config->wrap) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_IN_PINS) != config->in_pins) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUT_PINS) != config->out_pins) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SET_PINS) != config->set_pins) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_CLAIM_MASK) != config->claim_mask) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_OUTPUT_MASK) != config->output_mask) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_VALUE) != config->initial_value) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_OE) != config->initial_oe) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_INITIAL_XY) != config->initial_xy) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_LIMITS) != config->shift_limits) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TEST_SELECT) != config->test_select) ||
        (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_WATERMARKS) != config->watermarks)) {
        return RS_EIO;
    }
    session->sm[sm] = *config;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_configure(rs_piolite_session_t *session, uint32_t sm,
                                                 const rs_piolite_sm_config_t *config) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((sm >= RS_PIOLITE_SM_COUNT) || (config == NULL) || !rs_piolite_config_legal(config)) {
        return RS_EINVAL;
    }
    if (((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        rs_piolite_sm_bound(sm) || rs_piolite_sm_dma_active(sm) ||
        (session->claimed && ((session->claim_mask & config->claim_mask) != config->claim_mask)) ||
        ((sm == 0U) && ((config->output_mask & session->sm[1].output_mask) != 0U)) ||
        ((sm == 1U) && ((config->output_mask & session->sm[0].output_mask) != 0U))) {
        return RS_EIO;
    }
    return rs_piolite_write_config(session, sm, config);
}

static uint32_t rs_piolite_bitmap(const rs_piolite_session_t *session) {
    uint32_t bitmap = 0U;
    for (uint32_t index = 0U; index < RS_PIOLITE_IMEM_WORDS; ++index) {
        if (session->allocations[index].published) {
            bitmap |= rs_piolite_window_mask(index, session->allocations[index].word_count);
        }
    }
    return bitmap;
}

static rs_status_t rs_piolite_clean_state(rs_piolite_session_t *session) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if (session->claimed || session->bound[0] || session->bound[1] ||
        (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) != 0U) ||
        (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) != 0U)) {
        return RS_EIO;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if (((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
             RS_PIOLITE_ABI_STATE_DISABLED) ||
            (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U) ||
            (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) != 0U) ||
            (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_EVENTS) != 0U)) {
            return RS_EIO;
        }
    }
    return RS_OK;
}

static rs_status_t rs_piolite_quiescent(rs_piolite_session_t *session) {
    const rs_status_t status = rs_piolite_clean_state(session);
    if (status != RS_OK) {
        return status;
    }
    return (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) == rs_piolite_bitmap(session)) ? RS_OK
                                                                                          : RS_EIO;
}

static rs_status_t rs_piolite_write_imem(const rs_piolite_session_t *session,
                                         const rs_piolite_allocation_t *allocation) {
    (void)session;
#ifdef RS_PIOLITE_TEST_MMIO
    extern volatile uint32_t rs_piolite_test_readback_fail_mask;
#endif
    for (uint32_t index = 0U; index < allocation->word_count; ++index) {
        const uint32_t address = allocation->base + index;
        const uint16_t word = rs_piolite_relocate(allocation->program, allocation->base, index);
        RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_BASE + (address * 4U)) = word;
#ifdef RS_PIOLITE_TEST_MMIO
        rs_piolite_test_mmio[RS_PIOLITE_ABI_APB4_IMEM_VALID / 4U] |= UINT32_C(1) << address;
        if ((rs_piolite_test_readback_fail_mask & (UINT32_C(1) << address)) != 0U) {
            return RS_EIO;
        }
#endif
        if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_BASE + (address * 4U)) != word) ||
            ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) & (UINT32_C(1) << address)) == 0U)) {
            return RS_EIO;
        }
    }
    return RS_OK;
}

static rs_status_t rs_piolite_reset_reload(rs_piolite_session_t *session) {
    const uint32_t flags = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_FLAGS);
    const uint32_t irq_enable = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IRQ_ENABLE);
    const uint32_t event_enable[RS_PIOLITE_SM_COUNT] = {
        RS_PIOLITE_SM_REG(0U, RS_PIOLITE_ABI_APB4_SM_EVENT_ENABLE),
        RS_PIOLITE_SM_REG(1U, RS_PIOLITE_ABI_APB4_SM_EVENT_ENABLE),
    };
    rs_status_t status = rs_piolite_clean_state(session);
    if (status != RS_OK) {
        return status;
    }
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_BLOCK_RESET) = 1U;
#ifdef RS_PIOLITE_TEST_MMIO
    rs_piolite_test_mmio[RS_PIOLITE_ABI_APB4_IMEM_VALID / 4U] = 0U;
#endif
    for (uint32_t index = 0U; index < RS_PIOLITE_IMEM_WORDS; ++index) {
        if (session->allocations[index].published) {
            status = rs_piolite_write_imem(session, &session->allocations[index]);
            if (status != RS_OK) {
                session->recovery_failed = true;
                return status;
            }
        }
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if (rs_piolite_config_legal(&session->sm[sm])) {
            status = rs_piolite_write_config(session, sm, &session->sm[sm]);
            if (status != RS_OK) {
                session->recovery_failed = true;
                return status;
            }
        }
        RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_EVENT_ENABLE) = event_enable[sm];
    }
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IRQ_ENABLE) = irq_enable;
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_FLAG_SET) = flags;
    if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) != rs_piolite_bitmap(session)) ||
        (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_FLAGS) != flags) ||
        (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IRQ_ENABLE) != irq_enable)) {
        session->recovery_failed = true;
        return RS_EIO;
    }
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_program_load(rs_piolite_session_t *session,
                                                    const rs_piolite_program_t *program,
                                                    uint32_t requested_base,
                                                    rs_piolite_allocation_t **allocation) {
    rs_status_t status = rs_piolite_active(session);
    uint32_t base = requested_base;
    if (status != RS_OK) {
        return status;
    }
    if (allocation == NULL) {
        return RS_EINVAL;
    }
    *allocation = NULL;
    status = rs_piolite_program_validate(program);
    if (status != RS_OK) {
        return status;
    }
    if ((requested_base != RS_PIOLITE_ALLOCATE_ANY) &&
        ((requested_base >= RS_PIOLITE_IMEM_WORDS) ||
         ((requested_base + program->word_count) > RS_PIOLITE_IMEM_WORDS))) {
        return RS_ENOSPC;
    }
    status = rs_piolite_quiescent(session);
    if (status != RS_OK) {
        return status;
    }
    if (requested_base == RS_PIOLITE_ALLOCATE_ANY) {
        base = RS_PIOLITE_IMEM_WORDS;
        for (uint32_t candidate = 0U; candidate <= (RS_PIOLITE_IMEM_WORDS - program->word_count);
             ++candidate) {
            bool free = true;
            for (uint32_t index = 0U; index < RS_PIOLITE_IMEM_WORDS; ++index) {
                if (session->allocations[index].published &&
                    (candidate < (index + session->allocations[index].word_count)) &&
                    (index < (candidate + program->word_count)) &&
                    ((index != candidate) ||
                     !rs_piolite_program_equal(session->allocations[index].program, program))) {
                    free = false;
                    break;
                }
            }
            if (free) {
                base = candidate;
                break;
            }
        }
        if (base == RS_PIOLITE_IMEM_WORDS) {
            return RS_ENOSPC;
        }
    }
    for (uint32_t index = 0U; index < RS_PIOLITE_IMEM_WORDS; ++index) {
        if ((index != base) && session->allocations[index].published &&
            (base < (index + session->allocations[index].word_count)) &&
            (index < (base + program->word_count))) {
            return RS_ENOSPC;
        }
    }
    if (session->allocations[base].published) {
        rs_piolite_allocation_t *current = &session->allocations[base];
        if ((current->word_count != program->word_count) ||
            !rs_piolite_program_equal(current->program, program)) {
            return RS_ENOSPC;
        }
        if (current->references == UINT16_MAX) {
            return RS_ENOSPC;
        }
        current->references++;
        *allocation = current;
        return RS_OK;
    }
    session->allocations[base] = (rs_piolite_allocation_t){
        .program = program,
        .base = base,
        .handle = session->next_handle,
        .references = 1U,
        .word_count = (uint8_t)program->word_count,
        .published = false,
    };
    session->next_handle++;
    if (session->next_handle == 0U) {
        session->next_handle = 1U;
    }
    for (uint32_t index = 0U; index < program->word_count; ++index) {
        if (!rs_piolite_instruction_legal(rs_piolite_relocate(program, base, index),
                                          RS_PIOLITE_IMEM_WORDS)) {
            return RS_EFORMAT;
        }
    }
    status = rs_piolite_write_imem(session, &session->allocations[base]);
    if (status != RS_OK) {
        (void)rs_piolite_reset_reload(session);
        return status;
    }
    session->allocations[base].published = true;
    *allocation = &session->allocations[base];
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_program_unload(rs_piolite_session_t *session,
                                                      rs_piolite_allocation_t *allocation) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((allocation == NULL) || (allocation->base >= RS_PIOLITE_IMEM_WORDS) ||
        (allocation != &session->allocations[allocation->base]) || !allocation->published ||
        (allocation->references == 0U)) {
        return RS_EINVAL;
    }
    status = rs_piolite_quiescent(session);
    if (status != RS_OK) {
        return status;
    }
    if (allocation->references > 1U) {
        allocation->references--;
        return RS_OK;
    }
    allocation->published = false;
    allocation->references = 0U;
    return rs_piolite_reset_reload(session);
}

static rs_status_t rs_piolite_unlocked_claim(rs_piolite_session_t *session, rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    uint32_t claims = 0U;
    uint32_t outputs = 0U;
    if (status != RS_OK) {
        return status;
    }
    if (session->claimed) {
        return RS_EIO;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if (!rs_piolite_config_legal(&session->sm[sm])) {
            return RS_EINVAL;
        }
        claims |= session->sm[sm].claim_mask;
        outputs |= session->sm[sm].output_mask;
    }
    if ((session->sm[0].output_mask & session->sm[1].output_mask) != 0U) {
        return RS_EIO;
    }
    status = rs_gpio_user_acquire(claims, outputs, timeout);
    if (status != RS_OK) {
        session->claim_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) & claims;
        session->claimed = session->claim_mask != 0U;
        return status;
    }
    if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) & claims) != claims) {
        status = rs_gpio_user_release(claims, timeout);
        if (status != RS_OK) {
            session->claim_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK) & claims;
            session->claimed = session->claim_mask != 0U;
        }
        return RS_EIO;
    }
    session->claim_mask = claims;
    session->claimed = true;
    return RS_OK;
}

static rs_status_t rs_piolite_dma_idle(const rs_piolite_session_t *session) {
    const uint32_t transport = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    if (transport != 0U) {
        return RS_EIO;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (session->bound[direction] &&
            ((RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                        : RS_PIOLITE_ABI_APB4_RX_BIND) &
              RS_PIOLITE_BIND_ENABLE) != 0U)) {
            return RS_EIO;
        }
    }
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_release(rs_piolite_session_t *session,
                                               rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if (!session->claimed) {
        return RS_EIO;
    }
    if (session->bound[0] || session->bound[1] ||
        (RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) != 0U)) {
        status = rs_piolite_abort_reset(session, 3U, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    status = rs_piolite_disable(session, 3U);
    if (status != RS_OK) {
        return status;
    }
    if (rs_piolite_dma_idle(session) != RS_OK) {
        return RS_EIO;
    }
    status = rs_gpio_user_release(session->claim_mask, timeout);
    if (status != RS_OK) {
        return status;
    }
    session->claim_mask = 0U;
    session->claimed = false;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_session_release(rs_piolite_session_t *session) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if (session->claimed || session->bound[0] || session->bound[1] ||
        (rs_piolite_bitmap(session) != 0U)) {
        return RS_EIO;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
            RS_PIOLITE_ABI_STATE_DISABLED) {
            return RS_EIO;
        }
    }
    session->active = false;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_dma_bind(rs_piolite_session_t *session, uint32_t direction,
                                                uint32_t sm, uint32_t channel,
                                                rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    rs_piolite_info_t info;
    uint32_t binding;
    if (status != RS_OK) {
        return status;
    }
    if ((direction > RS_PIOLITE_RX) || (sm >= RS_PIOLITE_SM_COUNT) ||
        (channel >= RS_PIOLITE_DMA_CHANNEL_COUNT) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (!rs_piolite_config_legal(&session->sm[sm])) {
        return RS_EINVAL;
    }
    if (!session->claimed || session->bound[direction] ||
        ((rs_piolite_binding(direction) & RS_PIOLITE_BIND_ENABLE) != 0U) ||
        ((direction == RS_PIOLITE_TX) && session->bound[RS_PIOLITE_RX] &&
         (session->dma[RS_PIOLITE_RX].channel == channel)) ||
        ((direction == RS_PIOLITE_RX) && session->bound[RS_PIOLITE_TX] &&
         (session->dma[RS_PIOLITE_TX].channel == channel)) ||
        ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
         RS_PIOLITE_ABI_STATE_DISABLED) ||
        rs_piolite_sm_dma_active(sm)) {
        return RS_EIO;
    }
    status = rs_piolite_probe(&info);
    if (status != RS_OK) {
        return status;
    }
    status = rs_dma_supports_request(direction == RS_PIOLITE_TX ? RS_DMA_REQUEST_PIOLITE_TX
                                                                : RS_DMA_REQUEST_PIOLITE_RX);
    if (status != RS_OK) {
        return status;
    }
    status = rs_dma_session_acquire(&session->dma[direction], channel);
    if (status != RS_OK) {
        return status;
    }
    binding = RS_PIOLITE_BIND_ENABLE | sm | (channel << 8U);
    RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                              : RS_PIOLITE_ABI_APB4_RX_BIND) = binding;
    if (RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                  : RS_PIOLITE_ABI_APB4_RX_BIND) != binding) {
        (void)rs_dma_session_release(&session->dma[direction]);
        return RS_EIO;
    }
    session->bound[direction] = true;
    session->dma_started[direction] = false;
    return RS_OK;
}

static rs_status_t rs_piolite_release_binding(rs_piolite_session_t *session, uint32_t direction) {
    const uint32_t offset =
        direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND : RS_PIOLITE_ABI_APB4_RX_BIND;
    const uint32_t binding = RS_PIOLITE_REG(offset);
    rs_status_t status = rs_dma_session_release(&session->dma[direction]);
    if (status != RS_OK) {
        return status;
    }
    RS_PIOLITE_REG(offset) = 0U;
    if ((RS_PIOLITE_REG(offset) & RS_PIOLITE_BIND_ENABLE) != 0U) {
        const rs_status_t restore =
            rs_dma_session_acquire(&session->dma[direction], session->dma[direction].channel);
        RS_PIOLITE_REG(offset) = binding;
        if (restore != RS_OK) {
            session->recovery_failed = true;
        }
        return RS_EIO;
    }
    session->bound[direction] = false;
    session->dma_started[direction] = false;
    session->expected_dma_bytes[direction] = 0U;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_dma_unbind(rs_piolite_session_t *session, uint32_t direction,
                                                  rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if (direction > RS_PIOLITE_RX) {
        return RS_EINVAL;
    }
    if (!session->bound[direction]) {
        return RS_OK;
    }
    if (rs_piolite_direction_dma_active(direction) || (timeout == 0U)) {
        return RS_EIO;
    }
    return rs_piolite_release_binding(session, direction);
}

static rs_status_t rs_piolite_unlocked_dma_start(rs_piolite_session_t *session, uint32_t direction,
                                                 const rs_dma_config_t *config) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((direction > RS_PIOLITE_RX) || (config == NULL)) {
        return RS_EINVAL;
    }
    if (!session->bound[direction] || (session->dma[direction].channel >= RS_DMA_CHANNEL_COUNT)) {
        return RS_EIO;
    }
    if (((direction == RS_PIOLITE_TX) && ((config->kind != RS_DMA_KIND_MM_TO_STREAM) ||
                                          (config->request != RS_DMA_REQUEST_PIOLITE_TX))) ||
        ((direction == RS_PIOLITE_RX) && ((config->kind != RS_DMA_KIND_STREAM_TO_MM) ||
                                          (config->request != RS_DMA_REQUEST_PIOLITE_RX)))) {
        return RS_EINVAL;
    }
    status = rs_dma_config_validate(session->dma[direction].channel, config);
    if (status != RS_OK) {
        return status;
    }
    {
        const uint32_t sm =
            RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                      : RS_PIOLITE_ABI_APB4_RX_BIND) &
            1U;
        const uint32_t items =
            direction == RS_PIOLITE_TX ? session->sm[sm].tx_items : session->sm[sm].rx_items;
        const uint64_t expected =
            items == 0U ? config->byte_count
                        : rs_piolite_expected_bytes(items, session->sm[sm].item_bits,
                                                    rs_piolite_shift_bits(session, sm, direction));
        if ((sm >= RS_PIOLITE_SM_COUNT) || !rs_piolite_config_legal(&session->sm[sm]) ||
            (expected != config->byte_count)) {
            return RS_EINVAL;
        }
    }
    status = rs_dma_session_configure(&session->dma[direction], config);
    if (status != RS_OK) {
        return status;
    }
    RS_DMA_CH_REG(session->dma[direction].channel, RS_DMA_CH_REG_TCD_HEAD) = 0U;
    RS_DMA_CH_REG(session->dma[direction].channel, RS_DMA_CH_REG_TCD_COUNT) = 0U;
    status = rs_dma_session_start(&session->dma[direction]);
    if (status == RS_OK) {
        session->expected_dma_bytes[direction] = config->byte_count;
        session->dma_started[direction] = true;
    }
    return status;
}

static rs_status_t rs_piolite_unlocked_dma_submit_tcd_chain(rs_piolite_session_t *session,
                                                            uint32_t direction, rs_dma_tcd_t *first,
                                                            uint32_t max_tcds,
                                                            rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    rs_dma_tcd_t *current = first;
    rs_dma_config_t config = {0};
    uint32_t submitted = 0U;
    uint32_t final_bytes = 0U;
    uint64_t stream_bytes = 0U;
    if (status != RS_OK) {
        return status;
    }
    if ((direction > RS_PIOLITE_RX) || (first == NULL) || (max_tcds == 0U) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    final_bytes = first->byte_count;
    if (!session->bound[direction]) {
        return RS_EIO;
    }
    while ((current != NULL) && (submitted < max_tcds)) {
        uint32_t request;
        uint32_t kind;
        status = rs_dma_tcd_validate(session->dma[direction].channel, current);
        if (status != RS_OK) {
            return status;
        }
        request = (current->control >> RS_DMA_TCD_REQUEST_SHIFT) & 0xFU;
        if ((current->control & RS_DMA_TCD_REQUEST_HIGH) != 0U) {
            request |= 0x10U;
        }
        kind = (current->control >> RS_DMA_TCD_KIND_SHIFT) & 0x7U;
        if ((request != RS_DMA_REQUEST_SOFTWARE) &&
            ((direction == RS_PIOLITE_TX)
                 ? ((request != RS_DMA_REQUEST_PIOLITE_TX) || (kind != RS_DMA_KIND_MM_TO_STREAM))
                 : ((request != RS_DMA_REQUEST_PIOLITE_RX) ||
                    (kind != RS_DMA_KIND_STREAM_TO_MM)))) {
            return RS_EINVAL;
        }
        if ((request == RS_DMA_REQUEST_SOFTWARE) && (kind != RS_DMA_KIND_MM_TO_MM)) {
            return RS_EINVAL;
        }
        final_bytes = current->byte_count;
        if (request != RS_DMA_REQUEST_SOFTWARE) {
            stream_bytes += current->byte_count;
        }
        current = (rs_dma_tcd_t *)(uintptr_t)current->next_ptr;
        submitted++;
    }
    if ((current != NULL) || (submitted > UINT16_MAX)) {
        return RS_EINVAL;
    }
    {
        const uint32_t sm =
            RS_PIOLITE_REG(direction == RS_PIOLITE_TX ? RS_PIOLITE_ABI_APB4_TX_BIND
                                                      : RS_PIOLITE_ABI_APB4_RX_BIND) &
            1U;
        const uint32_t items =
            direction == RS_PIOLITE_TX ? session->sm[sm].tx_items : session->sm[sm].rx_items;
        if (!rs_piolite_config_legal(&session->sm[sm]) ||
            ((items != 0U) &&
             (rs_piolite_expected_bytes(items, session->sm[sm].item_bits,
                                        rs_piolite_shift_bits(session, sm, direction)) !=
              stream_bytes))) {
            return RS_EINVAL;
        }
    }
    config.kind = (rs_dma_transfer_kind_t)((first->control >> RS_DMA_TCD_KIND_SHIFT) & 0x7U);
    config.request = (rs_dma_request_t)((first->control >> RS_DMA_TCD_REQUEST_SHIFT) & 0xFU);
    if ((first->control & RS_DMA_TCD_REQUEST_HIGH) != 0U) {
        config.request = (rs_dma_request_t)((uint32_t)config.request | 0x10U);
    }
    config.source = (uintptr_t)first->source;
    config.destination = (uintptr_t)first->destination;
    config.byte_count = first->byte_count;
    config.width = RS_DMA_WIDTH_32;
    config.source_increment = (first->control & RS_DMA_TCD_SRC_INC) != 0U;
    config.destination_increment = (first->control & RS_DMA_TCD_DST_INC) != 0U;
    config.crc_enable = (first->control & RS_DMA_TCD_CRC_ENABLE) != 0U;
    config.crc_final = (first->control & RS_DMA_TCD_CRC_FINAL) != 0U;
    config.crc_expected = first->crc_expected;
    config.priority = (uint8_t)((first->control >> RS_DMA_TCD_PRIORITY_SHIFT) & 0x3U);
    config.burst_beats = (uint8_t)((first->control >> RS_DMA_TCD_BURST_SHIFT) & 0x1FU);
    if (config.burst_beats == 0U) {
        config.burst_beats = RS_DMA_MAX_BURST_BEATS;
    }
    if (session->dma_started[direction]) {
        status = rs_dma_wait(session->dma[direction].channel, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    status = rs_dma_session_configure(&session->dma[direction], &config);
    if (status != RS_OK) {
        return status;
    }
    RS_DMA_CH_REG(session->dma[direction].channel, RS_DMA_CH_REG_TCD_HEAD) =
        (uint32_t)(uintptr_t)first;
    RS_DMA_CH_REG(session->dma[direction].channel, RS_DMA_CH_REG_TCD_COUNT) = submitted;
    status = rs_dma_session_start(&session->dma[direction]);
    if (status == RS_OK) {
        session->expected_dma_bytes[direction] = final_bytes;
        session->dma_started[direction] = true;
    }
    return status;
}

static rs_status_t rs_piolite_unlocked_write(rs_piolite_session_t *session, uint32_t sm,
                                             uint32_t value) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if (sm >= RS_PIOLITE_SM_COUNT) {
        return RS_EINVAL;
    }
    if (!session->claimed || rs_piolite_direction_bound_sm(RS_PIOLITE_TX, sm) ||
        ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) ==
         RS_PIOLITE_ABI_STATE_CLOSING) ||
        ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) & 0xFU) >= 8U)) {
        return RS_EIO;
    }
    RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TXDATA) = value;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_read(rs_piolite_session_t *session, uint32_t sm,
                                            uint32_t *value) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((sm >= RS_PIOLITE_SM_COUNT) || (value == NULL)) {
        return RS_EINVAL;
    }
    if (!session->claimed || rs_piolite_direction_bound_sm(RS_PIOLITE_RX, sm) ||
        ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) ==
         RS_PIOLITE_ABI_STATE_CLOSING) ||
        (((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) >> 8U) & 0xFU) == 0U)) {
        return RS_EIO;
    }
    *value = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_RXDATA);
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_start(rs_piolite_session_t *session, uint32_t sm_mask) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((sm_mask == 0U) || (sm_mask > 3U) || !session->claimed) {
        return RS_EINVAL;
    }
    if ((session->sm[0].output_mask & session->sm[1].output_mask) != 0U) {
        return RS_EIO;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        const uint32_t base = session->sm[sm].program & 0x1FU;
        const uint32_t length = (session->sm[sm].program >> 8U) & 0x3FU;
        const uint32_t region = rs_piolite_window_mask(base, length);
        if (((sm_mask & (UINT32_C(1) << sm)) != 0U) &&
            (((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
              RS_PIOLITE_ABI_STATE_DISABLED) ||
             (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U) ||
             ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) & 0xF00U) != 0U) ||
             ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_IMEM_VALID) & region) != region))) {
            return RS_EIO;
        }
    }
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_START) = sm_mask;
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if (((sm_mask & (UINT32_C(1) << sm)) != 0U) &&
            ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) ==
             RS_PIOLITE_ABI_STATE_DISABLED)) {
            return RS_EIO;
        }
    }
    return RS_OK;
}

static rs_status_t rs_piolite_state_command(rs_piolite_session_t *session, uint32_t sm_mask,
                                            uint32_t offset, uint32_t expected) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((sm_mask == 0U) || (sm_mask > 3U)) {
        return RS_EINVAL;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        if (((sm_mask & (UINT32_C(1) << sm)) != 0U) &&
            ((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) != expected)) {
            return RS_EIO;
        }
    }
    RS_PIOLITE_REG(offset) = sm_mask;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_pause(rs_piolite_session_t *session, uint32_t sm_mask) {
    return rs_piolite_state_command(session, sm_mask, RS_PIOLITE_ABI_APB4_PAUSE,
                                    RS_PIOLITE_ABI_STATE_RUNNING);
}

static rs_status_t rs_piolite_unlocked_resume(rs_piolite_session_t *session, uint32_t sm_mask) {
    return rs_piolite_state_command(session, sm_mask, RS_PIOLITE_ABI_APB4_RESUME,
                                    RS_PIOLITE_ABI_STATE_PAUSED);
}

static rs_status_t rs_piolite_unlocked_disable(rs_piolite_session_t *session, uint32_t sm_mask) {
    rs_status_t status = rs_piolite_active(session);
    if (status != RS_OK) {
        return status;
    }
    if ((sm_mask == 0U) || (sm_mask > 3U)) {
        return RS_EIO;
    }
    for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
        const uint32_t state = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U;
        if (((sm_mask & (UINT32_C(1) << sm)) != 0U) &&
            ((state == RS_PIOLITE_ABI_STATE_CLOSING) || rs_piolite_sm_dma_active(sm))) {
            return RS_EIO;
        }
        if (((sm_mask & (UINT32_C(1) << sm)) != 0U) && (state == RS_PIOLITE_ABI_STATE_DISABLED) &&
            rs_piolite_sm_bound(sm)) {
            return RS_EIO;
        }
    }
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_DISABLE) = sm_mask;
    return RS_OK;
}

static rs_status_t rs_piolite_unlocked_wait_done(rs_piolite_session_t *session, uint32_t sm,
                                                 rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    uint32_t transport_mask;
    if (status != RS_OK) {
        return status;
    }
    if ((sm >= RS_PIOLITE_SM_COUNT) || (timeout == 0U) ||
        !rs_piolite_config_legal(&session->sm[sm])) {
        return RS_EINVAL;
    }
    transport_mask = rs_piolite_sm_dma_mask(sm);
    while (timeout-- != 0U) {
        const uint32_t state = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U;
        const uint32_t events = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_EVENTS);
        const uint32_t fault = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FAULT);
        const uint32_t transport = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
        const uint32_t shifts = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_COUNTS);
        bool dma_done = true;
        bool tails_ok = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS) == 0U;
        if (((session->sm[sm].tx_items != 0U) &&
             (session->sm[sm].tx_tail_policy == RS_PIOLITE_TAIL_ZERO) &&
             (((shifts >> 8U) & 0x3FU) != 0U)) ||
            ((session->sm[sm].rx_items != 0U) &&
             (session->sm[sm].rx_tail_policy == RS_PIOLITE_TAIL_ZERO) &&
             ((shifts & 0x3FU) != 0U))) {
            tails_ok = false;
        }
        if ((state == RS_PIOLITE_ABI_STATE_CLOSING) || (fault != 0U) ||
            ((events &
              ((1U << RS_PIOLITE_ABI_EVENTS_ABORT) | (1U << RS_PIOLITE_ABI_EVENTS_FAULT))) != 0U)) {
            return RS_EIO;
        }
        for (uint32_t direction = 0U; direction < 2U; ++direction) {
            if (session->bound[direction] && rs_piolite_direction_bound_sm(direction, sm)) {
                rs_dma_status_t dma_status;
                if (!session->dma_started[direction]) {
                    dma_done = false;
                } else {
                    if (rs_dma_get_status(session->dma[direction].channel, &dma_status) != RS_OK) {
                        return RS_EIO;
                    }
                    if (dma_status.error || dma_status.aborted) {
                        return RS_EIO;
                    }
                    if (!dma_status.done || dma_status.busy ||
                        (dma_status.bytes_done != session->expected_dma_bytes[direction])) {
                        dma_done = false;
                    }
                }
            }
        }
        if ((state == RS_PIOLITE_ABI_STATE_HALTED) && dma_done &&
            ((transport & transport_mask) == 0U)) {
            return tails_ok ? RS_OK : RS_EIO;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_piolite_unlocked_abort_reset(rs_piolite_session_t *session, uint32_t sm_mask,
                                                   rs_timeout_t timeout) {
    rs_status_t status = rs_piolite_active(session);
    uint32_t bound_sm[2] = {RS_PIOLITE_SM_COUNT, RS_PIOLITE_SM_COUNT};
    uint32_t transport_mask = 0U;
    if (status != RS_OK) {
        return status;
    }
    if ((sm_mask == 0U) || (sm_mask > 3U) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if (session->bound[direction]) {
            const uint32_t binding = rs_piolite_binding(direction);
            if ((binding & RS_PIOLITE_BIND_ENABLE) == 0U) {
                return RS_EIO;
            }
            bound_sm[direction] = binding & 1U;
            if ((sm_mask & (UINT32_C(1) << bound_sm[direction])) != 0U) {
                transport_mask |= UINT32_C(0x15) << direction;
            }
        }
    }
    RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_ABORT) = sm_mask;
#ifdef RS_PIOLITE_TEST_MMIO
    extern void rs_piolite_test_sm_abort(uint32_t abort_mask);
    rs_piolite_test_sm_abort(sm_mask);
#endif
    for (uint32_t direction = 0U; direction < 2U; ++direction) {
        if ((bound_sm[direction] < RS_PIOLITE_SM_COUNT) &&
            ((sm_mask & (UINT32_C(1) << bound_sm[direction])) != 0U)) {
            status = rs_dma_session_abort_wait(&session->dma[direction], timeout);
            if (status != RS_OK) {
                return status;
            }
        }
    }
    while (timeout-- != 0U) {
        const uint32_t transport = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
        if ((transport & (transport_mask & 0x3U)) == 0U) {
            RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_SM_RESET) = sm_mask;
#ifdef RS_PIOLITE_TEST_MMIO
            extern void rs_piolite_test_sm_reset(uint32_t reset_mask);
            rs_piolite_test_sm_reset(sm_mask);
#endif
            if ((RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS) & transport_mask) != 0U) {
                return RS_EIO;
            }
            for (uint32_t sm = 0U; sm < RS_PIOLITE_SM_COUNT; ++sm) {
                if (((sm_mask & (UINT32_C(1) << sm)) != 0U) &&
                    (((RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS) & 7U) !=
                      RS_PIOLITE_ABI_STATE_DISABLED) ||
                     (RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FAULT) != 0U))) {
                    return RS_EIO;
                }
            }
            for (uint32_t direction = 0U; direction < 2U; ++direction) {
                if ((bound_sm[direction] < RS_PIOLITE_SM_COUNT) &&
                    ((sm_mask & (UINT32_C(1) << bound_sm[direction])) != 0U)) {
                    status = rs_piolite_release_binding(session, direction);
                    if (status != RS_OK) {
                        return status;
                    }
                }
            }
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_piolite_unlocked_get_status(const rs_piolite_session_t *session, uint32_t sm,
                                                  rs_piolite_status_t *status) {
    rs_status_t result = rs_piolite_active(session);
    if (result != RS_OK) {
        return result;
    }
    if ((sm >= RS_PIOLITE_SM_COUNT) || (status == NULL)) {
        return RS_EINVAL;
    }
    status->status = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_STATUS);
    status->fault = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FAULT);
    status->fifo_levels = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_FIFO_LEVELS);
    status->transport_status = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_TRANSPORT_STATUS);
    status->owned_mask = RS_PIOLITE_REG(RS_PIOLITE_ABI_APB4_OWNED_MASK);
    status->events = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_EVENTS);
    status->pc = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_PC);
    status->shift_counts = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_SHIFT_COUNTS);
    status->tick_count = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TICK_COUNT);
    status->tx_stall_count = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_TX_STALL_COUNT);
    status->rx_stall_count = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_RX_STALL_COUNT);
    status->retired_count = RS_PIOLITE_SM_REG(sm, RS_PIOLITE_ABI_APB4_SM_RETIRED_COUNT);
    return RS_OK;
}

static rs_status_t rs_piolite_locked_result(uint32_t saved, rs_status_t status) {
    rs_piolite_unlock(saved);
    return status;
}

rs_status_t rs_piolite_probe(rs_piolite_info_t *info) {
    return rs_piolite_unlocked_probe(info);
}

rs_status_t rs_piolite_session_init(rs_piolite_session_t *session) {
    return rs_piolite_unlocked_session_init(session);
}

rs_status_t rs_piolite_program_config(const rs_piolite_program_t *program,
                                      const rs_piolite_allocation_t *allocation, uint32_t sm,
                                      rs_piolite_sm_config_t *config) {
    return rs_piolite_unlocked_program_config(program, allocation, sm, config);
}

rs_status_t rs_piolite_configure(rs_piolite_session_t *session, uint32_t sm,
                                 const rs_piolite_sm_config_t *config) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_configure(session, sm, config));
}

rs_status_t rs_piolite_program_load(rs_piolite_session_t *session,
                                    const rs_piolite_program_t *program, uint32_t requested_base,
                                    rs_piolite_allocation_t **allocation) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(
        saved, rs_piolite_unlocked_program_load(session, program, requested_base, allocation));
}

rs_status_t rs_piolite_program_unload(rs_piolite_session_t *session,
                                      rs_piolite_allocation_t *allocation) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_program_unload(session, allocation));
}

rs_status_t rs_piolite_claim(rs_piolite_session_t *session, rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_claim(session, timeout));
}

rs_status_t rs_piolite_release(rs_piolite_session_t *session, rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_release(session, timeout));
}

rs_status_t rs_piolite_session_release(rs_piolite_session_t *session) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_session_release(session));
}

rs_status_t rs_piolite_dma_bind(rs_piolite_session_t *session, uint32_t direction, uint32_t sm,
                                uint32_t channel, rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(
        saved, rs_piolite_unlocked_dma_bind(session, direction, sm, channel, timeout));
}

rs_status_t rs_piolite_dma_unbind(rs_piolite_session_t *session, uint32_t direction,
                                  rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved,
                                    rs_piolite_unlocked_dma_unbind(session, direction, timeout));
}

rs_status_t rs_piolite_dma_start(rs_piolite_session_t *session, uint32_t direction,
                                 const rs_dma_config_t *config) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved,
                                    rs_piolite_unlocked_dma_start(session, direction, config));
}

rs_status_t rs_piolite_dma_submit_tcd_chain(rs_piolite_session_t *session, uint32_t direction,
                                            rs_dma_tcd_t *first, uint32_t max_tcds,
                                            rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_dma_submit_tcd_chain(
                                               session, direction, first, max_tcds, timeout));
}

rs_status_t rs_piolite_write(rs_piolite_session_t *session, uint32_t sm, uint32_t value) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_write(session, sm, value));
}

rs_status_t rs_piolite_read(rs_piolite_session_t *session, uint32_t sm, uint32_t *value) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_read(session, sm, value));
}

rs_status_t rs_piolite_start(rs_piolite_session_t *session, uint32_t sm_mask) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_start(session, sm_mask));
}

rs_status_t rs_piolite_pause(rs_piolite_session_t *session, uint32_t sm_mask) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_pause(session, sm_mask));
}

rs_status_t rs_piolite_resume(rs_piolite_session_t *session, uint32_t sm_mask) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_resume(session, sm_mask));
}

rs_status_t rs_piolite_disable(rs_piolite_session_t *session, uint32_t sm_mask) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved, rs_piolite_unlocked_disable(session, sm_mask));
}

rs_status_t rs_piolite_wait_done(rs_piolite_session_t *session, uint32_t sm, rs_timeout_t timeout) {
    return rs_piolite_unlocked_wait_done(session, sm, timeout);
}

rs_status_t rs_piolite_abort_reset(rs_piolite_session_t *session, uint32_t sm_mask,
                                   rs_timeout_t timeout) {
    const uint32_t saved = rs_piolite_lock();
    return rs_piolite_locked_result(saved,
                                    rs_piolite_unlocked_abort_reset(session, sm_mask, timeout));
}

rs_status_t rs_piolite_get_status(const rs_piolite_session_t *session, uint32_t sm,
                                  rs_piolite_status_t *status) {
    return rs_piolite_unlocked_get_status(session, sm, status);
}

static rs_status_t rs_piolite_flag_command(rs_piolite_session_t *session, uint32_t flag_mask,
                                           uint32_t offset) {
    const uint32_t saved = rs_piolite_lock();
    rs_status_t status = rs_piolite_active(session);
    if ((status == RS_OK) && ((flag_mask == 0U) || (flag_mask > 0xFU) || !session->claimed)) {
        status = RS_EINVAL;
    }
    if (status == RS_OK) {
        RS_PIOLITE_REG(offset) = flag_mask;
    }
    return rs_piolite_locked_result(saved, status);
}

rs_status_t rs_piolite_flag_set(rs_piolite_session_t *session, uint32_t flag_mask) {
    return rs_piolite_flag_command(session, flag_mask, RS_PIOLITE_ABI_APB4_FLAG_SET);
}

rs_status_t rs_piolite_flag_clear(rs_piolite_session_t *session, uint32_t flag_mask) {
    return rs_piolite_flag_command(session, flag_mask, RS_PIOLITE_ABI_APB4_FLAG_CLEAR);
}
