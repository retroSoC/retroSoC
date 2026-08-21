#ifndef RETROSOC_HAL_USER_IP_H
#define RETROSOC_HAL_USER_IP_H

#include <stdint.h>

#include <retrosoc/core/status.h>

rs_status_t rs_user_ip_get_selected(uint8_t *ip_id);
rs_status_t rs_user_ip_select(uint8_t ip_id);
rs_status_t rs_user_ip_probe(uint8_t ip_id, uint32_t *identifier);
rs_status_t rs_user_ip_read(uint32_t offset, uint32_t *value);
rs_status_t rs_user_ip_write(uint32_t offset, uint32_t value);

#endif
