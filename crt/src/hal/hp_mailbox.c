#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/hp_mailbox.h>

#define RS_HP_MAILBOX_IP_VERSION_OFFSET     UINT32_C(0x000)
#define RS_HP_MAILBOX_CAPABILITY_OFFSET     UINT32_C(0x004)
#define RS_HP_MAILBOX_LP_COMMAND_OFFSET     UINT32_C(0x010)
#define RS_HP_MAILBOX_LP_ARG0_OFFSET        UINT32_C(0x014)
#define RS_HP_MAILBOX_LP_SEQUENCE_OFFSET    UINT32_C(0x018)
#define RS_HP_MAILBOX_LP_DOORBELL_OFFSET    UINT32_C(0x01C)
#define RS_HP_MAILBOX_HP_EVENT_OFFSET       UINT32_C(0x020)
#define RS_HP_MAILBOX_HP_ARG0_OFFSET        UINT32_C(0x024)
#define RS_HP_MAILBOX_HP_SEQUENCE_OFFSET    UINT32_C(0x028)
#define RS_HP_MAILBOX_LP_INTR_STATE_OFFSET  UINT32_C(0x030)
#define RS_HP_MAILBOX_LP_INTR_ENABLE_OFFSET UINT32_C(0x034)

#define RS_HP_MAILBOX_IP_VERSION_VALUE      UINT32_C(0x00010000)
#define RS_HP_MAILBOX_CAPABILITY_VALUE      UINT32_C(0x00000007)

static volatile uint32_t *rs_hp_mailbox_register(uint32_t offset) {
    return (volatile uint32_t *)(uintptr_t)(RS_SOC_APB4_HP_MAILBOX_BASE + offset);
}

rs_status_t rs_hp_mailbox_probe(void) {
    return ((*rs_hp_mailbox_register(RS_HP_MAILBOX_IP_VERSION_OFFSET) ==
             RS_HP_MAILBOX_IP_VERSION_VALUE) &&
            (*rs_hp_mailbox_register(RS_HP_MAILBOX_CAPABILITY_OFFSET) ==
             RS_HP_MAILBOX_CAPABILITY_VALUE))
               ? RS_OK
               : RS_ENOTSUP;
}

rs_status_t rs_hp_mailbox_send_to_hp(const rs_hp_mailbox_message_t *message) {
    if ((message == NULL) || (message->sequence == 0U)) {
        return RS_EINVAL;
    }
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_COMMAND_OFFSET) = message->code;
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_ARG0_OFFSET) = message->argument;
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_SEQUENCE_OFFSET) = message->sequence;
    __asm__ volatile("fence w, w" ::: "memory");
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_DOORBELL_OFFSET) = UINT32_C(1);
    return RS_OK;
}

rs_status_t rs_hp_mailbox_receive_from_hp(rs_hp_mailbox_message_t *message) {
    uint32_t sequence;

    if (message == NULL) {
        return RS_EINVAL;
    }
    sequence = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_SEQUENCE_OFFSET);
    __asm__ volatile("fence r, r" ::: "memory");
    message->code = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_EVENT_OFFSET);
    message->argument = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_ARG0_OFFSET);
    message->sequence = sequence;
    return RS_OK;
}

rs_status_t rs_hp_mailbox_enable_lp_interrupt(bool enable) {
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_INTR_ENABLE_OFFSET) =
        enable ? UINT32_C(1) : UINT32_C(0);
    return RS_OK;
}

rs_status_t rs_hp_mailbox_lp_interrupt_pending(bool *pending) {
    if (pending == NULL) {
        return RS_EINVAL;
    }
    *pending = (*rs_hp_mailbox_register(RS_HP_MAILBOX_LP_INTR_STATE_OFFSET) & UINT32_C(1)) != 0U;
    return RS_OK;
}

rs_status_t rs_hp_mailbox_clear_lp_interrupt(void) {
    *rs_hp_mailbox_register(RS_HP_MAILBOX_LP_INTR_STATE_OFFSET) = UINT32_C(1);
    return RS_OK;
}
