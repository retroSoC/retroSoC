#ifndef RETROSOC_HAL_HP_MAILBOX_H
#define RETROSOC_HAL_HP_MAILBOX_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t code;
    uint32_t argument;
    uint32_t sequence;
} rs_hp_mailbox_message_t;

rs_status_t rs_hp_mailbox_probe(void);
rs_status_t rs_hp_mailbox_send_to_hp(const rs_hp_mailbox_message_t *message);
rs_status_t rs_hp_mailbox_receive_from_hp(rs_hp_mailbox_message_t *message);
rs_status_t rs_hp_mailbox_enable_lp_interrupt(bool enable);
rs_status_t rs_hp_mailbox_lp_interrupt_pending(bool *pending);
rs_status_t rs_hp_mailbox_clear_lp_interrupt(void);

#endif
