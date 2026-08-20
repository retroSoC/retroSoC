#ifndef RETROSOC_HAL_SPISD_H
#define RETROSOC_HAL_SPISD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/spisd_regs.h>

#define RS_SPISD_SECTOR_SIZE   UINT32_C(512)
#define RS_SPISD_INIT_CLOCK_HZ UINT32_C(400000)
#define RS_SPISD_DEFAULT_HZ    UINT32_C(18000000)
#define RS_SPISD_HIGH_SPEED_HZ UINT32_C(36000000)

typedef enum {
    RS_SPISD_RESPONSE_NONE = RS_SPISD_ABI_RESP_NONE,
    RS_SPISD_RESPONSE_R1 = RS_SPISD_ABI_RESP_R1,
    RS_SPISD_RESPONSE_R1B = RS_SPISD_ABI_RESP_R1B,
    RS_SPISD_RESPONSE_R2 = RS_SPISD_ABI_RESP_R2,
    RS_SPISD_RESPONSE_R3 = RS_SPISD_ABI_RESP_R3,
    RS_SPISD_RESPONSE_R7 = RS_SPISD_ABI_RESP_R7
} rs_spisd_response_type_t;

typedef enum { RS_SPISD_CARD_SDSC = 0, RS_SPISD_CARD_SDHC = 1 } rs_spisd_card_type_t;

typedef struct {
    uint8_t index;
    uint32_t argument;
    rs_spisd_response_type_t response;
    bool stuff_byte;
} rs_spisd_command_t;

typedef struct {
    uint8_t bytes[5];
} rs_spisd_response_t;

typedef struct {
    uint16_t half_period;
    uint32_t requested_hz;
    uint32_t actual_hz;
} rs_spisd_clock_t;

typedef struct {
    uint8_t csd[16];
    uint32_t ocr;
    uint32_t capacity_blocks;
    uint32_t actual_clock_hz;
    rs_spisd_card_type_t card_type;
    bool high_capacity;
    bool high_speed;
    bool initialized;
} rs_spisd_card_info_t;

static inline void rs_spisd_memory_barrier(void) {
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
#endif
}

rs_status_t rs_spisd_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability);
rs_status_t rs_spisd_clock_calculate(uint32_t source_clock_hz, uint32_t target_clock_hz,
                                     rs_spisd_clock_t *clock);
rs_status_t rs_spisd_card_address(rs_spisd_card_type_t card_type, uint32_t sector,
                                  uint32_t *argument);
rs_status_t rs_spisd_parse_csd(const uint8_t *csd, rs_spisd_card_info_t *info);
rs_status_t rs_spisd_descriptor_prepare(rs_spisd_descriptor_t *descriptor, uintptr_t buffer,
                                        size_t byte_count, uintptr_t next, bool end, bool irq);
rs_status_t rs_spisd_descriptor_validate(const rs_spisd_descriptor_t *descriptor);
rs_status_t rs_spisd_descriptor_publish(rs_spisd_descriptor_t *descriptor);
rs_status_t rs_spisd_clock_set(uint32_t source_clock_hz, uint32_t target_clock_hz,
                               uint32_t *actual_clock_hz);
rs_status_t rs_spisd_initialize(uint32_t source_clock_hz, rs_timeout_t timeout);
rs_status_t rs_spisd_high_speed_enable(uint32_t source_clock_hz, rs_timeout_t timeout);
rs_status_t rs_spisd_card_info_get(rs_spisd_card_info_t *info);
rs_status_t rs_spisd_command_execute(const rs_spisd_command_t *command,
                                     rs_spisd_response_t *response, rs_timeout_t timeout);
rs_status_t rs_spisd_abort(rs_timeout_t timeout);
rs_status_t rs_spisd_irq_enable(uint32_t mask);
rs_status_t rs_spisd_irq_clear(uint32_t mask);
uint32_t rs_spisd_irq_status(void);
rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address);
rs_status_t rs_spisd_sector_read(uint8_t *buffer, uint32_t sector, uint32_t count);
rs_status_t rs_spisd_sector_write(const uint8_t *buffer, uint32_t sector, uint32_t count);
rs_status_t rs_spisd_sector_sync(rs_timeout_t timeout);
void ip_spisd_test(void);
void ip_spisd_read(uint32_t address, uint32_t length);

#endif
