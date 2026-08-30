#ifndef RETROSOC_HAL_EXTENSION_H
#define RETROSOC_HAL_EXTENSION_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_EXTENSION_IDENTIFICATION_EXT_L UINT32_C(0x4558544C)
#define RS_EXTENSION_IDENTIFICATION_EXT_H UINT32_C(0x45585448)

typedef enum {
    RS_EXTENSION_SLOT_L = 0,
    RS_EXTENSION_SLOT_H = 1,
} rs_extension_slot_t;

typedef enum {
    RS_EXTENSION_OWNER_LP = 0,
    RS_EXTENSION_OWNER_HP = 1,
} rs_extension_owner_t;

typedef struct {
    uint32_t identification;
    uint32_t version;
    uint8_t interrupt_count;
    bool data_master;
    bool stream;
    bool local_sram;
} rs_extension_capabilities_t;

typedef struct {
    rs_extension_owner_t owner;
    bool owner_locked;
    bool present;
    bool idle;
    bool quiesced;
    bool in_reset;
    bool fault;
} rs_extension_status_t;

typedef struct {
    uint32_t read_base;
    uint32_t read_limit;
    uint32_t write_base;
    uint32_t write_limit;
    uint32_t timeout_cycles;
} rs_extension_acl_t;

typedef struct {
    bool busy;
    bool done;
    bool fault;
} rs_extension_dma_status_t;

rs_status_t rs_extension_probe(rs_extension_slot_t slot, rs_extension_capabilities_t *capabilities);
rs_status_t rs_extension_get_status(rs_extension_slot_t slot, rs_extension_status_t *status);
rs_status_t rs_extension_set_owner(rs_extension_slot_t slot, rs_extension_owner_t owner, bool lock);
rs_status_t rs_extension_set_lifecycle(rs_extension_slot_t slot, bool quiesce, bool reset,
                                       bool clear_fault);
rs_status_t rs_extension_configure_acl(rs_extension_slot_t slot,
                                       const rs_extension_acl_t *configuration);
rs_status_t rs_extension_read(rs_extension_slot_t slot, uint32_t offset, uint32_t *value);
rs_status_t rs_extension_dma_start(uintptr_t source, uintptr_t destination, uint32_t byte_count);
rs_status_t rs_extension_dma_abort(void);
rs_status_t rs_extension_dma_get_status(rs_extension_dma_status_t *status);

#endif
