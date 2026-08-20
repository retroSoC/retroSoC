#ifndef RETROSOC_HAL_XPI_H
#define RETROSOC_HAL_XPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/xpi_regs.h>

#define RS_XPI_SLOT_WINDOW_SIZE   UINT32_C(0x04000000)
#define RS_XPI_BOOT_ALIAS_SIZE    UINT32_C(0x01000000)
#define RS_XPI_FIFO_WORD_CAPACITY UINT32_C(64)
#define RS_XPI_MAX_TRANSFER_BYTES UINT16_MAX

typedef enum {
    RS_XPI_PADS_1 = 0,
    RS_XPI_PADS_2 = 1,
    RS_XPI_PADS_4 = 2,
} rs_xpi_pads_t;

typedef enum {
    RS_XPI_INSTR_STOP = 0,
    RS_XPI_INSTR_COMMAND = 1,
    RS_XPI_INSTR_ADDRESS = 2,
    RS_XPI_INSTR_MODE = 3,
    RS_XPI_INSTR_DUMMY = 4,
    RS_XPI_INSTR_TRANSMIT = 5,
    RS_XPI_INSTR_RECEIVE = 6,
    RS_XPI_INSTR_JUMP_ON_CS = 7,
} rs_xpi_instruction_opcode_t;

typedef enum {
    RS_XPI_ERROR_NONE = 0,
    RS_XPI_ERROR_ILLEGAL = 1,
    RS_XPI_ERROR_DISABLED = 2,
    RS_XPI_ERROR_RANGE = 3,
    RS_XPI_ERROR_SEQUENCE = 4,
    RS_XPI_ERROR_TIMEOUT = 5,
    RS_XPI_ERROR_ABORTED = 6,
    RS_XPI_ERROR_FIFO = 7,
    RS_XPI_ERROR_DMA = 8,
} rs_xpi_error_code_t;

typedef enum {
    RS_XPI_DMA_TRANSMIT = 0,
    RS_XPI_DMA_RECEIVE = 1,
} rs_xpi_dma_direction_t;

typedef struct {
    bool enable;
    bool memory_read_enable;
    bool memory_write_enable;
    bool mode3;
    uint32_t device_size;
    uint8_t read_sequence;
    uint8_t write_sequence;
    uint8_t clock_divider;
    uint8_t cs_setup_cycles;
    uint8_t cs_hold_cycles;
    uint8_t cs_high_cycles;
    uint32_t timeout_cycles;
    uint32_t burst_boundary;
} rs_xpi_slot_config_t;

typedef struct {
    uint8_t slot;
    uint8_t sequence;
    uint32_t address;
    const uint8_t *tx_data;
    uint8_t *rx_data;
    uint16_t byte_count;
} rs_xpi_transfer_t;

typedef struct {
    uint8_t slot;
    uint8_t sequence;
    uint32_t mask;
    uint32_t match;
    uint32_t interval_cycles;
    uint32_t timeout_cycles;
} rs_xpi_poll_config_t;

typedef struct {
    bool valid;
    rs_xpi_error_code_t code;
    uint32_t address;
    uint8_t slot;
    uint8_t instruction;
} rs_xpi_error_t;

typedef struct {
    uint32_t axi_read_bytes;
    uint32_t axi_write_bytes;
    uint32_t phy_bytes;
    uint32_t commands;
    uint32_t stall_cycles;
} rs_xpi_performance_t;

uint16_t rs_xpi_instruction(rs_xpi_instruction_opcode_t opcode, rs_xpi_pads_t pads,
                            uint8_t operand);
rs_status_t rs_xpi_probe(void);
rs_status_t rs_xpi_enable(bool enable, rs_timeout_t timeout);
rs_status_t rs_xpi_slot_configure(uint8_t slot, const rs_xpi_slot_config_t *config,
                                  rs_timeout_t timeout);
rs_status_t rs_xpi_lut_write(uint8_t sequence, const uint16_t *instructions,
                             size_t instruction_count, rs_timeout_t timeout);
rs_status_t rs_xpi_transfer(const rs_xpi_transfer_t *transfer, rs_timeout_t timeout);
rs_status_t rs_xpi_transfer_dma(const rs_xpi_transfer_t *transfer, rs_xpi_dma_direction_t direction,
                                uint32_t channel, rs_timeout_t timeout);
rs_status_t rs_xpi_poll(const rs_xpi_poll_config_t *config, rs_timeout_t timeout);
rs_status_t rs_xpi_abort(rs_timeout_t timeout);
rs_status_t rs_xpi_irq_enable(uint32_t mask);
rs_status_t rs_xpi_irq_pending(uint32_t *pending);
rs_status_t rs_xpi_irq_clear(uint32_t mask);
rs_status_t rs_xpi_error_get(rs_xpi_error_t *error);
rs_status_t rs_xpi_error_clear(void);
rs_status_t rs_xpi_performance_enable(bool enable, bool clear);
rs_status_t rs_xpi_performance_get(rs_xpi_performance_t *performance);
rs_status_t rs_xpi_config_lock(uint32_t mask);

/* Programs sequence 15 as a single-pad data-only peripheral transfer. */
rs_status_t rs_xpi_peripheral_initialize(rs_timeout_t timeout);
rs_status_t rs_xpi_peripheral_write(const uint8_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_xpi_peripheral_write_dma(const void *data, size_t length, uint32_t channel,
                                        rs_timeout_t timeout);

#endif
