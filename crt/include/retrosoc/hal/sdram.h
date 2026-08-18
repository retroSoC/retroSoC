#ifndef RETROSOC_HAL_SDRAM_H
#define RETROSOC_HAL_SDRAM_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_SDRAM_INTERRUPT_INIT_DONE UINT32_C(0x00000001)
#define RS_SDRAM_INTERRUPT_ERROR     UINT32_C(0x00000002)
#define RS_SDRAM_INTERRUPT_ALL       UINT32_C(0x00000003)

#define RS_SDRAM_CAS_2               UINT8_C(2)
#define RS_SDRAM_CAS_3               UINT8_C(3)
#define RS_SDRAM_BURST_2             UINT8_C(2)
#define RS_SDRAM_BURST_8             UINT8_C(8)

/* clang-format off */
typedef enum {
    RS_SDRAM_ERROR_NONE         = 0,
    RS_SDRAM_ERROR_AXI_DECODE   = 1,
    RS_SDRAM_ERROR_AXI_ILLEGAL  = 2,
    RS_SDRAM_ERROR_INIT         = 3,
    RS_SDRAM_ERROR_TIMING       = 4,
    RS_SDRAM_ERROR_COMMAND_BUSY = 5,
} rs_sdram_error_t;
/* clang-format on */

typedef struct {
    uint8_t trp_cycles;
    uint8_t trcd_cycles;
    uint8_t tras_cycles;
    uint8_t trc_cycles;
    uint8_t twr_cycles;
    uint8_t trfc_cycles;
    uint8_t trrd_cycles;
    uint8_t twtr_cycles;
    uint8_t trtp_cycles;
    uint8_t tmrd_cycles;
    uint8_t txsr_cycles;
    uint16_t trefi_cycles;
    uint16_t powerup_cycles;
    uint32_t actual_sdram_hz;
} rs_sdram_timing_t;

typedef struct {
    rs_sdram_timing_t timing;
    uint8_t clkdiv;
    uint8_t cas_latency;
    uint8_t burst_length;
    uint8_t refresh_credit_max;
    bool write_burst;
    bool open_page;
    bool auto_initialize;
    bool memory_enable;
} rs_sdram_config_t;

typedef struct {
    rs_sdram_error_t last_error;
    uint32_t last_error_address;
    bool init_busy;
    bool axi_busy;
    bool phy_busy;
    bool ready;
    bool error;
} rs_sdram_status_t;

typedef struct {
    uint32_t address;
    uint32_t expected;
    uint32_t actual;
} rs_sdram_test_failure_t;

rs_status_t rs_sdram_timing_from_hz(uint32_t source_clock_hz, uint8_t clkdiv,
                                    rs_sdram_timing_t *timing);
rs_status_t rs_sdram_configure(const rs_sdram_config_t *config);
rs_status_t rs_sdram_initialize(rs_timeout_t timeout);
rs_status_t rs_sdram_reinitialize(rs_timeout_t timeout);
rs_status_t rs_sdram_precharge_all(void);
rs_status_t rs_sdram_refresh(void);
rs_status_t rs_sdram_get_status(rs_sdram_status_t *status);
rs_status_t rs_sdram_interrupt_enable(uint32_t mask);
rs_status_t rs_sdram_interrupt_clear(uint32_t mask);
rs_status_t rs_sdram_interrupt_test(uint32_t mask);
rs_status_t rs_sdram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                              rs_sdram_test_failure_t *failure);

#endif
