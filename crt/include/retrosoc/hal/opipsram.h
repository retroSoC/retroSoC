#ifndef RETROSOC_HAL_OPIPSRAM_H
#define RETROSOC_HAL_OPIPSRAM_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/opipsram_regs.h>

#define RS_OPIPSRAM_MAX_DEVICE_SIZE    (RS_SOC_OPIPSRAM_END - RS_SOC_OPIPSRAM_BASE + UINT32_C(1))
/* The first Mini SoC integration is 72 MHz PHY / 2 = 36 MHz CK. */
#define RS_OPIPSRAM_MIN_CK_HZ          UINT32_C(36000000)
#define RS_OPIPSRAM_TARGET_MIN_CK_HZ   UINT32_C(50000000)
#define RS_OPIPSRAM_TARGET_MAX_CK_HZ   UINT32_C(100000000)
#define RS_OPIPSRAM_PHY_RATIO          UINT32_C(2)
#define RS_OPIPSRAM_MAX_DUMMY_CYCLES   UINT8_C(63)
#define RS_OPIPSRAM_MAX_LATENCY_CYCLES UINT8_C(31)
#define RS_OPIPSRAM_MAX_TAP            UINT8_C(31)
#define RS_OPIPSRAM_MAX_COARSE_TAP     UINT8_C(7)
#define RS_OPIPSRAM_MAX_TRAIN_TAPS     UINT8_C(32)
#define RS_OPIPSRAM_MAX_INDIRECT_BYTES UINT8_C(8)

typedef enum {
    RS_OPIPSRAM_PROFILE_OPI = UINT32_C(0),
    RS_OPIPSRAM_PROFILE_HYPERBUS = UINT32_C(1),
} rs_opipsram_profile_t;

typedef enum {
    RS_OPIPSRAM_COMMAND_WIDTH_8 = UINT8_C(8),
    RS_OPIPSRAM_COMMAND_WIDTH_16 = UINT8_C(16),
} rs_opipsram_command_width_t;

typedef enum {
    RS_OPIPSRAM_ADDRESS_WIDTH_24 = UINT8_C(3),
    RS_OPIPSRAM_ADDRESS_WIDTH_32 = UINT8_C(4),
} rs_opipsram_address_width_t;

typedef enum {
    RS_OPIPSRAM_DQS_NONE = UINT8_C(0),
    RS_OPIPSRAM_DQS_READ = UINT8_C(1),
    RS_OPIPSRAM_DQS_WRITE = UINT8_C(2),
    RS_OPIPSRAM_DQS_READ_WRITE = UINT8_C(3),
} rs_opipsram_dqs_policy_t;

typedef uint32_t rs_opipsram_error_t;

typedef struct {
    uint16_t divider;
    uint8_t phy_ratio;
    uint32_t source_clock_hz;
    uint32_t requested_ck_hz;
    uint32_t actual_phy_hz;
    uint32_t actual_ck_hz;
    uint16_t cs_setup_cycles;
    uint16_t cs_hold_cycles;
    uint16_t cs_high_cycles;
    uint32_t powerup_cycles;
    uint32_t timeout_cycles;
} rs_opipsram_timing_t;

typedef struct {
    uint16_t read_command;
    uint16_t write_command;
    uint16_t register_read_command;
    uint16_t register_write_command;
    rs_opipsram_command_width_t command_width;
    rs_opipsram_address_width_t address_width;
    uint8_t dummy_cycles;
    uint8_t latency_cycles;
    rs_opipsram_dqs_policy_t dqs_policy;
    uint8_t burst_boundary;
} rs_opipsram_opi_config_t;

typedef struct {
    uint8_t initial_latency;
    uint8_t additional_latency;
    uint8_t read_recovery_cycles;
    uint8_t write_recovery_cycles;
    bool rwds_additional_latency;
} rs_opipsram_hyperbus_config_t;

typedef struct {
    rs_opipsram_profile_t profile;
    uint32_t device_size;
    rs_opipsram_timing_t timing;
    rs_opipsram_opi_config_t opi;
    rs_opipsram_hyperbus_config_t hyperbus;
    bool enable;
    bool memory_enable;
    bool auto_initialize;
    bool line_buffer;
} rs_opipsram_config_t;

typedef struct {
    rs_opipsram_error_t last_error;
    uint32_t last_error_address;
    uint32_t profile_status;
    bool busy;
    bool initialized;
    bool ready;
    bool quiesced;
    bool trained;
    bool error;
    bool profile_locked;
    bool hyperbus;
} rs_opipsram_status_t;

typedef struct {
    bool write;
    bool register_space;
    uint8_t length;
    uint32_t address;
    uint64_t write_data;
} rs_opipsram_indirect_t;

typedef struct {
    uint8_t fine;
    uint8_t coarse;
} rs_opipsram_delay_tap_t;

typedef struct {
    bool valid;
    bool wrapped;
    uint8_t first;
    uint8_t last;
    uint8_t width;
    uint8_t center;
} rs_opipsram_training_window_t;

/*
 * The callback owns tap programming and verification.  The sweep only visits
 * each tap and derives a passing window; it does not claim hardware training.
 */
typedef bool (*rs_opipsram_train_probe_t)(uint8_t tap, void *context);

typedef struct {
    uint32_t address;
    uint32_t expected;
    uint32_t actual;
} rs_opipsram_test_failure_t;

rs_status_t rs_opipsram_timing_from_hz(uint32_t source_clock_hz, uint32_t ck_hz,
                                       rs_opipsram_timing_t *timing);
rs_status_t rs_opipsram_timing_validate(const rs_opipsram_timing_t *timing);
rs_status_t rs_opipsram_config_validate(const rs_opipsram_config_t *config);
/* Memory-space ranges use DEVICE_SIZE; register-space ranges remain profile-defined. */
rs_status_t rs_opipsram_indirect_validate(const rs_opipsram_indirect_t *command,
                                          uint32_t device_size);
rs_status_t rs_opipsram_configure(const rs_opipsram_config_t *config);
rs_status_t rs_opipsram_initialize(rs_timeout_t timeout);
rs_status_t rs_opipsram_abort(void);
rs_status_t rs_opipsram_soft_reset(rs_timeout_t timeout);
rs_status_t rs_opipsram_get_status(rs_opipsram_status_t *status);
rs_status_t rs_opipsram_indirect(const rs_opipsram_indirect_t *command, uint64_t *read_data,
                                 rs_timeout_t timeout);
rs_status_t rs_opipsram_indirect_read(uint32_t address, bool register_space, uint8_t length,
                                      uint64_t *read_data, rs_timeout_t timeout);
rs_status_t rs_opipsram_indirect_write(uint32_t address, bool register_space, uint8_t length,
                                       uint64_t write_data, rs_timeout_t timeout);
rs_status_t rs_opipsram_irq_enable(uint32_t mask);
rs_status_t rs_opipsram_irq_pending(uint32_t *pending);
rs_status_t rs_opipsram_irq_clear(uint32_t mask);
rs_status_t rs_opipsram_get_delay_tap(rs_opipsram_delay_tap_t *tap);
rs_status_t rs_opipsram_set_delay_tap(const rs_opipsram_delay_tap_t *tap);
rs_status_t rs_opipsram_training_window_from_mask(uint32_t passing_taps, uint8_t tap_count,
                                                  rs_opipsram_training_window_t *window);
/* Probe/program/verify every tap in the callback, then return its center window. */
rs_status_t rs_opipsram_training_sweep(rs_opipsram_train_probe_t probe, void *context,
                                       uint8_t tap_count, rs_opipsram_training_window_t *window);
rs_status_t rs_opipsram_selftest(uintptr_t address, uint32_t size, uint32_t word_limit,
                                 rs_opipsram_test_failure_t *failure);
rs_status_t rs_opipsram_dma_copy_validate(uint32_t channel, uintptr_t source, uintptr_t destination,
                                          uint32_t byte_count, uint8_t priority,
                                          uint8_t burst_beats, rs_dma_config_t *config);
rs_status_t rs_opipsram_dma_copy(uint32_t channel, uintptr_t source, uintptr_t destination,
                                 uint32_t byte_count, uint8_t priority, uint8_t burst_beats);

#endif
