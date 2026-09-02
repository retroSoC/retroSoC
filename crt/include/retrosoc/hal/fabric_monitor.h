#ifndef RETROSOC_HAL_FABRIC_MONITOR_H
#define RETROSOC_HAL_FABRIC_MONITOR_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef enum {
    RS_FABRIC_MASTER_HP_ICACHE = 0,
    RS_FABRIC_MASTER_HP_DCACHE = 1,
    RS_FABRIC_MASTER_DMA = 2,
    RS_FABRIC_MASTER_IO_A = 3,
    RS_FABRIC_MASTER_IO_B = 4,
    RS_FABRIC_MASTER_LP = 5,
    RS_FABRIC_MASTER_RESERVED = 6,
    RS_FABRIC_MASTER_EXT_H = 7,
    RS_FABRIC_MASTER_COUNT = 8,
} rs_fabric_master_t;

typedef enum {
    RS_FABRIC_TARGET_SRAM = 0,
    RS_FABRIC_TARGET_SDRAM = 1,
    RS_FABRIC_TARGET_QPI = 2,
    RS_FABRIC_TARGET_OPI = 3,
    RS_FABRIC_TARGET_XPI = 4,
    RS_FABRIC_TARGET_ERROR = 5,
    RS_FABRIC_TARGET_COUNT = 6,
} rs_fabric_target_t;

typedef struct {
    uint8_t outstanding_reads;
    uint8_t outstanding_writes;
    bool idle;
    bool recovery;
    bool flush_busy;
} rs_fabric_monitor_status_t;

typedef struct {
    uint32_t read_requests;
    uint32_t write_requests;
    uint32_t read_beats;
    uint32_t write_beats;
    uint32_t wait_cycles;
    uint32_t max_wait_cycles;
    uint32_t starvation_promotions;
    uint8_t read_high_water;
    uint8_t write_high_water;
} rs_fabric_master_stats_t;

typedef struct {
    uint32_t read_requests;
    uint32_t write_requests;
    uint32_t read_beats;
    uint32_t write_beats;
    uint32_t wait_cycles;
    uint32_t timeout_count;
    uint8_t read_high_water;
    uint8_t write_high_water;
    bool isolated;
} rs_fabric_target_stats_t;

typedef struct {
    uint32_t address;
    uint32_t count;
    uint8_t master;
    uint8_t target;
    uint8_t reason;
    bool valid;
    bool write;
} rs_fabric_fault_t;

rs_status_t rs_fabric_monitor_configure(bool enable, bool freeze);
rs_status_t rs_fabric_monitor_clear(void);
rs_status_t rs_fabric_monitor_snapshot(void);
rs_status_t rs_fabric_monitor_get_status(rs_fabric_monitor_status_t *status);
rs_status_t rs_fabric_monitor_get_flush_count(uint32_t *count);
rs_status_t rs_fabric_monitor_read_fault(rs_fabric_fault_t *fault);
rs_status_t rs_fabric_monitor_read_master(rs_fabric_master_t master,
                                          rs_fabric_master_stats_t *stats);
rs_status_t rs_fabric_monitor_read_target(rs_fabric_target_t target,
                                          rs_fabric_target_stats_t *stats);

#endif
