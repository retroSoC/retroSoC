#include <retrosoc/hal/xpi_psram.h>

rs_status_t rs_xpi_psram_timing(uint32_t memory_clock_hz, rs_xpi_slot_config_t *config) {
    if ((config == NULL) ||
        ((memory_clock_hz != UINT32_C(24000000)) && (memory_clock_hz != UINT32_C(48000000)) &&
         (memory_clock_hz != UINT32_C(96000000)) && (memory_clock_hz != UINT32_C(120000000)))) {
        return RS_EINVAL;
    }
    config->enable = true;
    config->memory_read_enable = false;
    config->memory_write_enable = false;
    config->mode3 = false;
    config->device_size = RS_XPI_PSRAM_BYTES;
    config->read_sequence = UINT8_C(8);
    config->write_sequence = UINT8_C(9);
    config->clock_divider = UINT8_C(0);
    config->cs_setup_cycles = UINT8_C(1);
    config->cs_hold_cycles =
        (uint8_t)(((uint64_t)memory_clock_hz * UINT64_C(20) + UINT64_C(999999999)) /
                  UINT64_C(1000000000));
    config->cs_high_cycles =
        (uint8_t)(((uint64_t)memory_clock_hz * UINT64_C(50) + UINT64_C(999999999)) /
                  UINT64_C(1000000000));
    /* Includes core setup/hold/high and consumer stalls. Leave two MEM edges
     * of margin below the reference device's 8 us active-CS limit. */
    config->timeout_cycles = (memory_clock_hz / UINT32_C(125000)) - UINT32_C(2);
    config->burst_boundary = UINT32_C(1024);
    return RS_OK;
}

rs_status_t rs_xpi_psram_validate_dma(const rs_xpi_psram_t *device, uint32_t address,
                                      uint32_t bytes, uint8_t burst_beats) {
    uint32_t offset;
    uint32_t cursor;
    const uint32_t burst_bytes = (uint32_t)burst_beats * UINT32_C(4);
    if (device == NULL) {
        return RS_EINVAL;
    }
    if (!device->initialized || (device->capacity_bytes != RS_XPI_PSRAM_BYTES)) {
        return RS_ENOTSUP;
    }
    if ((address < RS_XPI_PSRAM_BASE) || (bytes == 0U) || ((bytes & 3U) != 0U) ||
        ((burst_beats != 1U) && (burst_beats != 2U) && (burst_beats != 4U)) ||
        ((address & ((uint32_t)burst_beats * 4U - 1U)) != 0U)) {
        return RS_EINVAL;
    }
    offset = address - RS_XPI_PSRAM_BASE;
    if ((offset >= device->capacity_bytes) || (bytes > device->capacity_bytes - offset)) {
        return RS_EINVAL;
    }
    /* The XPI slot rejects a serial-boundary crossing command, and the DMA
     * itself cannot cross a 4 KiB AXI page. Validate every emitted burst before
     * admitting the session; do not rely on the target to fail mid-frame. */
    for (cursor = 0U; cursor < bytes; cursor += burst_bytes) {
        uint32_t length = bytes - cursor;
        const uint32_t serial_offset = (offset + cursor) & UINT32_C(0x3ff);
        const uint32_t page_offset = (offset + cursor) & UINT32_C(0xfff);
        if (length > burst_bytes) {
            length = burst_bytes;
        }
        if ((length > UINT32_C(0x400) - serial_offset) ||
            (length > UINT32_C(0x1000) - page_offset)) {
            return RS_EINVAL;
        }
    }
    return RS_OK;
}
