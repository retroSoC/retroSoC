#ifndef RETROSOC_HAL_RESOURCE_H
#define RETROSOC_HAL_RESOURCE_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_RESOURCE_DMA = 0,
    RS_RESOURCE_USB2 = 1,
    RS_RESOURCE_SDIO0 = 2,
    RS_RESOURCE_SDIO1 = 3,
    RS_RESOURCE_SPISD = 4,
    RS_RESOURCE_EXT_H = 5,
    RS_RESOURCE_JPEG = 6,
    RS_RESOURCE_APU = 7,
    RS_RESOURCE_COUNT = 8,
} rs_resource_t;

typedef enum {
    RS_RESOURCE_OWNER_LP = 0,
    RS_RESOURCE_OWNER_HP = 1,
} rs_resource_owner_t;

typedef struct {
    rs_resource_owner_t owner;
    uint16_t handoff_count;
    bool owner_locked;
    bool blocked;
    bool idle;
    bool quiesced;
    bool in_reset;
    bool irq_pending;
    bool fault;
} rs_resource_status_t;

typedef struct {
    bool request;
    bool clean;
} rs_resource_cache_status_t;

rs_status_t rs_resource_get_status(rs_resource_t resource, rs_resource_status_t *status);
rs_status_t rs_resource_set_owner(rs_resource_t resource, rs_resource_owner_t owner, bool lock);
rs_status_t rs_resource_set_lifecycle(rs_resource_t resource, bool quiesce, bool reset);
rs_status_t rs_resource_clear_fault(rs_resource_t resource);
rs_status_t rs_resource_get_cache_status(rs_resource_cache_status_t *status);
rs_status_t rs_resource_acknowledge_cache_clean(void);

#endif
