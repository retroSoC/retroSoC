#ifndef RETROSOC_HAL_PSRAM_H
#define RETROSOC_HAL_PSRAM_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_PSRAM_CHIP_COUNT              UINT32_C(4)
#define RS_PSRAM_CHIP_SIZE               UINT32_C(0x00800000)
#define RS_PSRAM_TOTAL_SIZE              UINT32_C(0x02000000)
#define RS_PSRAM_MAX_SCLK_HZ             UINT32_C(133000000)
#define RS_PSRAM_PAGE_CROSS_MAX_HZ       UINT32_C(84000000)

#define RS_PSRAM_INTERRUPT_INIT_DONE     UINT32_C(0x00000001)
#define RS_PSRAM_INTERRUPT_INDIRECT_DONE UINT32_C(0x00000002)
#define RS_PSRAM_INTERRUPT_ERROR         UINT32_C(0x00000004)
#define RS_PSRAM_INTERRUPT_TIMEOUT       UINT32_C(0x00000008)
#define RS_PSRAM_INTERRUPT_ALL           UINT32_C(0x0000000F)

typedef enum {
    RS_PSRAM_COMMAND_READ = 0,
    RS_PSRAM_COMMAND_FAST_READ = 1,
    RS_PSRAM_COMMAND_QUAD_READ = 2,
    RS_PSRAM_COMMAND_WRITE = 3,
    RS_PSRAM_COMMAND_QUAD_WRITE = 4,
    RS_PSRAM_COMMAND_ENTER_QPI = 5,
    RS_PSRAM_COMMAND_EXIT_QPI = 6,
    RS_PSRAM_COMMAND_RESET_ENABLE = 7,
    RS_PSRAM_COMMAND_RESET = 8,
    RS_PSRAM_COMMAND_TOGGLE_WRAP = 9,
    RS_PSRAM_COMMAND_READ_ID = 10,
} rs_psram_command_t;

typedef enum {
    RS_PSRAM_ERROR_NONE = 0,
    RS_PSRAM_ERROR_ILLEGAL = 1,
    RS_PSRAM_ERROR_UNAVAILABLE = 2,
    RS_PSRAM_ERROR_TIMEOUT = 3,
    RS_PSRAM_ERROR_ID = 4,
    RS_PSRAM_ERROR_ABORTED = 5,
    RS_PSRAM_ERROR_PHY = 6,
    RS_PSRAM_ERROR_PROTOCOL = 7,
} rs_psram_error_t;

typedef struct {
    uint16_t half_period_cycles;
    uint16_t cs_setup_cycles;
    uint16_t cs_high_cycles;
    uint16_t cs_hold_cycles;
    uint32_t powerup_cycles;
    uint32_t cs_max_low_cycles;
    uint32_t access_timeout_cycles;
    uint32_t actual_sclk_hz;
    bool above_84mhz;
} rs_psram_timing_t;

typedef struct {
    rs_psram_timing_t timing;
    uint8_t chip_enable;
    bool wrap32;
    bool auto_initialize;
    bool memory_enable;
} rs_psram_config_t;

typedef struct {
    uint8_t chip_present;
    uint8_t chip_ready;
    uint8_t chip_qpi;
    uint8_t chip_wrap32;
    uint8_t chip_error;
    rs_psram_error_t last_error;
    uint8_t last_error_chip;
    uint32_t last_error_address;
    bool init_busy;
    bool axi_busy;
    bool indirect_busy;
    bool phy_busy;
    bool quiesced;
    bool ready;
} rs_psram_status_t;

typedef struct {
    rs_psram_command_t command;
    uint8_t chip;
    uint8_t length;
    uint32_t address;
    uint64_t write_data;
} rs_psram_indirect_t;

typedef struct {
    uint32_t address;
    uint32_t expected;
    uint32_t actual;
} rs_psram_test_failure_t;

rs_status_t rs_psram_timing_from_hz(uint32_t source_clock_hz, uint32_t sclk_hz,
                                    rs_psram_timing_t *timing);
rs_status_t rs_psram_configure(const rs_psram_config_t *config);
rs_status_t rs_psram_initialize(rs_timeout_t timeout);
rs_status_t rs_psram_recover(uint8_t chip, rs_timeout_t timeout);
rs_status_t rs_psram_abort(void);
rs_status_t rs_psram_get_status(rs_psram_status_t *status);
rs_status_t rs_psram_read_id(uint8_t chip, uint64_t *identifier);
rs_status_t rs_psram_indirect(const rs_psram_indirect_t *command, uint64_t *read_data,
                              rs_timeout_t timeout);
rs_status_t rs_psram_set_wrap(uint8_t chip, bool wrap32, rs_timeout_t timeout);
rs_status_t rs_psram_interrupt_enable(uint32_t mask);
rs_status_t rs_psram_interrupt_clear(uint32_t mask);
rs_status_t rs_psram_interrupt_test(uint32_t mask);
rs_status_t rs_psram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                              rs_psram_test_failure_t *failure);

void ip_psram_boot(void);
uint32_t xorshift32(uint32_t *state);
void ip_psram_selftest(uint32_t address, uint32_t size);

#endif
