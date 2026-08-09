#ifndef RETROSOC_HAL_I2C_H
#define RETROSOC_HAL_I2C_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_I2C_DMA_MAX_BYTES      16U

#define RS_I2C_ERROR_ADDR_NACK    (UINT32_C(1) << 0U)
#define RS_I2C_ERROR_DATA_NACK    (UINT32_C(1) << 1U)
#define RS_I2C_ERROR_ARB_LOST     (UINT32_C(1) << 2U)
#define RS_I2C_ERROR_STRETCH_TO   (UINT32_C(1) << 3U)
#define RS_I2C_ERROR_BUS_TO       (UINT32_C(1) << 4U)
#define RS_I2C_ERROR_COMMAND_TO   (UINT32_C(1) << 5U)
#define RS_I2C_ERROR_COMMAND      (UINT32_C(1) << 6U)
#define RS_I2C_ERROR_RX_OVERFLOW  (UINT32_C(1) << 7U)
#define RS_I2C_ERROR_CONFIG       (UINT32_C(1) << 8U)
#define RS_I2C_ERROR_ABORTED      (UINT32_C(1) << 9U)
#define RS_I2C_ERROR_RECOVERY     (UINT32_C(1) << 10U)
#define RS_I2C_ERROR_ALL          UINT32_C(0x7FF)

#define RS_I2C_INTR_DONE          (UINT32_C(1) << 0U)
#define RS_I2C_INTR_CMD_WATERMARK (UINT32_C(1) << 1U)
#define RS_I2C_INTR_RX_WATERMARK  (UINT32_C(1) << 2U)
#define RS_I2C_INTR_NACK          (UINT32_C(1) << 3U)
#define RS_I2C_INTR_ARB_LOST      (UINT32_C(1) << 4U)
#define RS_I2C_INTR_TIMEOUT       (UINT32_C(1) << 5U)
#define RS_I2C_INTR_ERROR         (UINT32_C(1) << 6U)
#define RS_I2C_INTR_RECOVERY_DONE (UINT32_C(1) << 7U)
#define RS_I2C_INTR_ALL           UINT32_C(0xFF)

typedef enum {
    RS_I2C_BUS_0 = 0,
    RS_I2C_BUS_1 = 1,
} rs_i2c_bus_t;

typedef enum {
    RS_I2C_REGISTER_ADDRESS_8_BIT = 1,
    RS_I2C_REGISTER_ADDRESS_16_BIT = 2,
} rs_i2c_register_address_width_t;

typedef struct {
    uint16_t scl_low_cycles;
    uint16_t scl_high_cycles;
    uint16_t start_hold_cycles;
    uint16_t start_setup_cycles;
    uint16_t data_hold_cycles;
    uint16_t data_setup_cycles;
    uint16_t stop_setup_cycles;
    uint16_t bus_free_cycles;
} rs_i2c_timing_t;

typedef struct {
    uint32_t source_clock_hz;
    uint32_t bus_hz;
    uint32_t stretch_timeout_us;
    uint32_t bus_idle_timeout_us;
    uint32_t command_timeout_us;
    uint8_t scl_filter_cycles;
    uint8_t sda_filter_cycles;
    uint8_t command_watermark;
    uint8_t rx_watermark;
} rs_i2c_config_t;

typedef struct {
    uint16_t address;
    bool ten_bit_address;
    const uint8_t *tx_data;
    size_t tx_length;
    uint8_t *rx_data;
    size_t rx_length;
} rs_i2c_transfer_t;

typedef struct {
    uint16_t address;
    bool ten_bit_address;
    uint16_t register_address;
    rs_i2c_register_address_width_t register_address_width;
} rs_i2c_register_access_t;

typedef struct {
    uint32_t flags;
    uint32_t command_level;
    uint32_t rx_level;
    uint32_t errors;
    uint32_t interrupt_state;
} rs_i2c_status_t;

typedef struct {
    uint32_t words[RS_I2C_DMA_MAX_BYTES];
} rs_i2c_dma_workspace_t;

rs_status_t rs_i2c_timing_calculate(uint32_t source_clock_hz, uint32_t bus_hz,
                                    rs_i2c_timing_t *timing);
rs_status_t rs_i2c_configure(rs_i2c_bus_t bus, const rs_i2c_config_t *config, rs_timeout_t timeout);
rs_status_t rs_i2c_init(rs_i2c_bus_t bus, uint32_t source_clock_hz, uint32_t bus_hz);
rs_status_t rs_i2c_transfer(rs_i2c_bus_t bus, const rs_i2c_transfer_t *transfer,
                            rs_timeout_t timeout);
rs_status_t rs_i2c_register_write(rs_i2c_bus_t bus, const rs_i2c_register_access_t *access,
                                  const uint8_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_i2c_register_read(rs_i2c_bus_t bus, const rs_i2c_register_access_t *access,
                                 uint8_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_i2c_abort(rs_i2c_bus_t bus, rs_timeout_t timeout);
rs_status_t rs_i2c_recover(rs_i2c_bus_t bus, rs_timeout_t timeout);
rs_status_t rs_i2c_get_status(rs_i2c_bus_t bus, rs_i2c_status_t *status);
rs_status_t rs_i2c_irq_enable(rs_i2c_bus_t bus, uint32_t mask);
rs_status_t rs_i2c_irq_ack(rs_i2c_bus_t bus, uint32_t mask);
rs_status_t rs_i2c_irq_test(rs_i2c_bus_t bus, uint32_t mask);
rs_status_t rs_i2c_write_dma(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address,
                             const uint8_t *data, size_t length, rs_i2c_dma_workspace_t *workspace,
                             rs_timeout_t timeout);
rs_status_t rs_i2c_read_dma(rs_i2c_bus_t bus, uint16_t address, bool ten_bit_address, uint8_t *data,
                            size_t length, rs_i2c_dma_workspace_t *workspace, rs_timeout_t timeout);

#endif
