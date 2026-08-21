#ifndef RETROSOC_HAL_SDIO_H
#define RETROSOC_HAL_SDIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/sdio_regs.h>

#define RS_SD_MEMORY_BLOCK_SIZE UINT32_C(512)
#define RS_SDIO_PIO_WORD_SIZE   UINT32_C(4)

/*
 * SDIO words are little-endian byte lanes: bits [7:0] (lane 0) contain the
 * first byte placed on the SD wire, and each byte is serialized MSB first.
 * The same convention is used by PIO, AXI stream data, and tail strobes.
 */

typedef enum {
    RS_SDIO_INSTANCE_0 = 0,
    RS_SDIO_INSTANCE_1 = 1,
    RS_SDIO_INSTANCE_COUNT = 2
} rs_sdio_instance_t;

typedef enum { RS_SDIO_BUS_WIDTH_1 = 0, RS_SDIO_BUS_WIDTH_4 = 1 } rs_sdio_bus_width_t;

typedef enum {
    RS_SDIO_RESPONSE_NONE = RS_SDIO_RESP_NONE,
    RS_SDIO_RESPONSE_R1 = RS_SDIO_RESP_R1,
    RS_SDIO_RESPONSE_R1B = RS_SDIO_RESP_R1B,
    RS_SDIO_RESPONSE_R2 = RS_SDIO_RESP_R2,
    RS_SDIO_RESPONSE_R3 = RS_SDIO_RESP_R3,
    RS_SDIO_RESPONSE_R4 = RS_SDIO_RESP_R4,
    RS_SDIO_RESPONSE_R5 = RS_SDIO_RESP_R5,
    RS_SDIO_RESPONSE_R6 = RS_SDIO_RESP_R6,
    RS_SDIO_RESPONSE_R7 = RS_SDIO_RESP_R7
} rs_sdio_response_type_t;

typedef enum { RS_SDIO_DATA_FROM_CARD = 0, RS_SDIO_DATA_TO_CARD = 1 } rs_sdio_data_direction_t;

typedef enum { RS_SD_MEMORY_SDSC = 0, RS_SD_MEMORY_SDHC = 1 } rs_sd_memory_card_type_t;

typedef struct {
    uint32_t words[5];
} rs_sdio_response_t;

typedef struct {
    uint8_t index;
    uint32_t argument;
    rs_sdio_response_type_t response;
    bool crc_check;
    bool index_check;
} rs_sdio_command_t;

typedef struct {
    uint16_t block_size;
    uint16_t block_count;
    rs_sdio_data_direction_t direction;
    bool dma;
    bool block_mode;
    bool fixed_address;
} rs_sdio_data_config_t;

typedef struct {
    uint16_t half_period;
    uint32_t requested_hz;
    uint32_t actual_hz;
} rs_sdio_clock_t;

typedef struct {
    uint32_t source_clock_hz;
    uint32_t target_clock_hz;
    rs_sdio_bus_width_t bus_width;
    uint32_t timeout_cmd;
    uint32_t timeout_data;
    uint32_t timeout_busy;
    bool enable_interrupts;
} rs_sdio_config_t;

typedef struct {
    uint32_t raw_status;
    uint32_t command_status;
    uint32_t data_status;
    uint32_t fifo_status;
    uint32_t dma_status;
    uint32_t error_status;
    uint32_t irq_status;
    uint32_t irq_enable;
    uint32_t clock_actual_hz;
    uint32_t current_descriptor;
    uint32_t bytes_done;
    uint32_t dma_error_address;
    uint32_t dma_error;
    uint32_t last_command;
    bool busy;
    bool present;
} rs_sdio_status_t;

typedef struct {
    uint32_t raw_status;
    uint32_t current_descriptor;
    uint32_t bytes_done;
    uint32_t error_address;
    uint32_t error_code;
    bool busy;
    bool done;
    bool error;
} rs_sdio_dma_status_t;

typedef struct {
    uint32_t cid[5];
    uint32_t csd[5];
    uint32_t ocr;
    uint16_t rca;
    uint32_t capacity_blocks;
    uint32_t block_length;
    rs_sd_memory_card_type_t card_type;
    rs_sdio_bus_width_t bus_width;
    uint32_t actual_clock_hz;
    bool high_capacity;
    bool high_speed;
    bool bus_width_fallback;
    bool speed_fallback;
} rs_sd_memory_info_t;

typedef struct {
    uint32_t ocr;
    uint16_t rca;
    uint8_t function_count;
    uint8_t cccr_version;
    uint8_t io_enable;
    uint8_t io_ready;
    uint8_t bus_interface_control;
    uint8_t function_code[8];
    uint16_t function_block_size[8];
    bool high_speed;
    bool high_speed_fallback;
    bool dat1_interrupt_enabled;
} rs_sdio_function_info_t;

typedef struct {
    uint8_t function;
    uint32_t address;
    bool write;
    bool raw;
    uint8_t data;
} rs_sdio_cmd52_t;

typedef struct {
    uint8_t function;
    uint32_t address;
    uint16_t count;
    bool write;
    bool block_mode;
    bool fixed_address;
} rs_sdio_cmd53_t;

static inline void rs_sdio_memory_barrier(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
#endif
}

rs_status_t rs_sdio_clock_calculate(uint32_t source_clock_hz, uint32_t target_clock_hz,
                                    rs_sdio_clock_t *clock);
rs_status_t rs_sdio_response_field(const rs_sdio_response_t *response, uint32_t high_bit,
                                   uint32_t low_bit, uint32_t *value);
rs_status_t rs_sd_memory_address(rs_sd_memory_card_type_t card_type, uint32_t block,
                                 uint32_t *argument);
rs_status_t rs_sd_memory_parse_csd(const rs_sdio_response_t *response, rs_sd_memory_info_t *info);
rs_status_t rs_sdio_cmd52_argument(const rs_sdio_cmd52_t *command, uint32_t *argument);
rs_status_t rs_sdio_cmd53_argument(const rs_sdio_cmd53_t *command, uint32_t *argument);
rs_status_t rs_sdio_validate_dma_buffer(const void *buffer, size_t byte_count);
rs_status_t rs_sdio_descriptor_prepare(rs_sdio_descriptor_t *descriptor, uintptr_t buffer,
                                       size_t byte_count, uintptr_t next, bool end, bool irq);
rs_status_t rs_sdio_descriptor_validate(const rs_sdio_descriptor_t *descriptor);
rs_status_t rs_sdio_descriptor_chain_validate(const rs_sdio_descriptor_t *descriptors,
                                              uint16_t count, uint32_t total_bytes);
rs_status_t rs_sdio_descriptor_publish(rs_sdio_descriptor_t *descriptor);
rs_status_t rs_sdio_descriptor_publish_chain(rs_sdio_descriptor_t *descriptors, uint16_t count);

rs_status_t rs_sdio_probe(rs_sdio_instance_t instance, uint32_t *ip_id, uint32_t *version,
                          uint32_t *capability);
rs_status_t rs_sdio_reset(rs_sdio_instance_t instance, rs_timeout_t timeout);
rs_status_t rs_sdio_configure(rs_sdio_instance_t instance, const rs_sdio_config_t *config);
rs_status_t rs_sdio_clock_set(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                              uint32_t target_clock_hz, rs_sdio_clock_t *clock);
rs_status_t rs_sdio_bus_width_set(rs_sdio_instance_t instance, rs_sdio_bus_width_t width);
rs_status_t rs_sdio_timeouts_set(rs_sdio_instance_t instance, uint32_t command_timeout,
                                 uint32_t data_timeout, uint32_t busy_timeout);
rs_status_t rs_sdio_enable(rs_sdio_instance_t instance, bool enable);
rs_status_t rs_sdio_status_get(rs_sdio_instance_t instance, rs_sdio_status_t *status);

rs_status_t rs_sdio_command_start(rs_sdio_instance_t instance, const rs_sdio_command_t *command);
rs_status_t rs_sdio_command_wait(rs_sdio_instance_t instance, rs_sdio_response_t *response,
                                 rs_timeout_t timeout);
rs_status_t rs_sdio_command_execute(rs_sdio_instance_t instance, const rs_sdio_command_t *command,
                                    rs_sdio_response_t *response, rs_timeout_t timeout);
rs_status_t rs_sdio_response_get(rs_sdio_instance_t instance, rs_sdio_response_t *response);

rs_status_t rs_sdio_data_configure(rs_sdio_instance_t instance,
                                   const rs_sdio_data_config_t *config);
rs_status_t rs_sdio_data_start(rs_sdio_instance_t instance);
rs_status_t rs_sdio_pio_write(rs_sdio_instance_t instance, const void *buffer, size_t byte_count,
                              rs_timeout_t timeout);
rs_status_t rs_sdio_pio_read(rs_sdio_instance_t instance, void *buffer, size_t byte_count,
                             rs_timeout_t timeout);
rs_status_t rs_sdio_data_wait(rs_sdio_instance_t instance, rs_timeout_t timeout);

rs_status_t rs_sdio_dma_setup(rs_sdio_instance_t instance, rs_sdio_descriptor_t *descriptors,
                              uint16_t count, uint32_t total_bytes);
/* DATA_START is the coordinated DMA and card-data launch operation. */
rs_status_t rs_sdio_dma_start(rs_sdio_instance_t instance);
rs_status_t rs_sdio_dma_abort(rs_sdio_instance_t instance);
rs_status_t rs_sdio_dma_status_get(rs_sdio_instance_t instance, rs_sdio_dma_status_t *status);
rs_status_t rs_sdio_dma_wait(rs_sdio_instance_t instance, rs_timeout_t timeout);

rs_status_t rs_sdio_irq_enable(rs_sdio_instance_t instance, uint32_t mask);
rs_status_t rs_sdio_irq_pending(rs_sdio_instance_t instance, uint32_t *mask);
rs_status_t rs_sdio_irq_clear(rs_sdio_instance_t instance, uint32_t mask);
rs_status_t rs_sdio_irq_test(rs_sdio_instance_t instance, uint32_t mask);
rs_status_t rs_sdio_error_clear(rs_sdio_instance_t instance, uint32_t mask);
rs_status_t rs_sdio_controller_selftest(rs_sdio_instance_t instance);

rs_status_t rs_sd_memory_initialize(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                                    rs_sd_memory_info_t *info, rs_timeout_t timeout);
rs_status_t rs_sd_memory_read_blocks(rs_sdio_instance_t instance, const rs_sd_memory_info_t *info,
                                     uint32_t block, uint32_t count, void *buffer,
                                     rs_timeout_t timeout);
rs_status_t rs_sd_memory_write_blocks(rs_sdio_instance_t instance, const rs_sd_memory_info_t *info,
                                      uint32_t block, uint32_t count, const void *buffer,
                                      rs_timeout_t timeout);

rs_status_t rs_sdio_function_initialize(rs_sdio_instance_t instance, uint32_t source_clock_hz,
                                        rs_sdio_function_info_t *info, rs_timeout_t timeout);
rs_status_t rs_sdio_function_enable(rs_sdio_instance_t instance, rs_sdio_function_info_t *info,
                                    uint8_t function, rs_timeout_t timeout);
rs_status_t rs_sdio_function_cmd52_read(rs_sdio_instance_t instance, uint8_t function,
                                        uint32_t address, uint8_t *data, rs_timeout_t timeout);
rs_status_t rs_sdio_function_cmd52_write(rs_sdio_instance_t instance, uint8_t function,
                                         uint32_t address, uint8_t data, rs_timeout_t timeout);
rs_status_t rs_sdio_function_cmd53_transfer(rs_sdio_instance_t instance, uint8_t function,
                                            uint32_t address, void *buffer, size_t byte_count,
                                            bool write, bool block_mode, bool fixed_address,
                                            uint16_t block_size, rs_timeout_t timeout);
rs_status_t rs_sdio_function_irq_enable(rs_sdio_instance_t instance, bool enable);
rs_status_t rs_sdio_function_irq_pending(rs_sdio_instance_t instance, bool *pending);
rs_status_t rs_sdio_function_irq_ack(rs_sdio_instance_t instance);

#endif
