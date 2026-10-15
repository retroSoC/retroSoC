#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/xpi_psram.h>

#define RS_XPI_PSRAM_SLOT             UINT8_C(1)
#define RS_XPI_PSRAM_COMMAND_SEQUENCE UINT8_C(10)
#define RS_XPI_PSRAM_ID_SEQUENCE      UINT8_C(11)

static rs_status_t rs_xpi_psram_delay(uint32_t microseconds, rs_timeout_t timeout) {
    uint64_t first, now;
    const uint64_t ticks =
        ((uint64_t)microseconds * RS_CLINT_TIMEBASE_HZ + UINT64_C(999999)) / UINT64_C(1000000);
    if (rs_clint_get_time(&first) != RS_OK) {
        return RS_EIO;
    }
    while (timeout-- != 0U) {
        if (rs_clint_get_time(&now) != RS_OK) {
            return RS_EIO;
        }
        if (now - first >= ticks) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_xpi_psram_command(uint8_t opcode, rs_xpi_pads_t pads, rs_timeout_t timeout) {
    const uint16_t lut[] = {rs_xpi_instruction(RS_XPI_INSTR_COMMAND, pads, opcode), 0U};
    const rs_xpi_transfer_t transfer = {.slot = RS_XPI_PSRAM_SLOT,
                                        .sequence = RS_XPI_PSRAM_COMMAND_SEQUENCE};
    rs_status_t status = rs_xpi_enable(false, timeout);
    if (status == RS_OK) {
        status = rs_xpi_lut_write(RS_XPI_PSRAM_COMMAND_SEQUENCE, lut, 2U, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_enable(true, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_transfer(&transfer, timeout);
    }
    return status;
}

rs_status_t rs_xpi_psram_initialize(uint32_t memory_clock_hz, rs_timeout_t timeout,
                                    rs_xpi_psram_t *device) {
    const uint16_t read_lut[] = {UINT16_C(0x18eb), UINT16_C(0x2818), UINT16_C(0x4006),
                                 UINT16_C(0x6800), 0U};
    const uint16_t write_lut[] = {UINT16_C(0x1838), UINT16_C(0x2818), UINT16_C(0x5800), 0U};
    const uint16_t id_lut[] = {UINT16_C(0x109f), UINT16_C(0x2018), UINT16_C(0x6000), 0U};
    rs_xpi_slot_config_t config;
    rs_xpi_transfer_t transfer = {
        .slot = RS_XPI_PSRAM_SLOT, .sequence = RS_XPI_PSRAM_ID_SEQUENCE, .byte_count = 3U};
    rs_status_t status;
    if (device == NULL) {
        return RS_EINVAL;
    }
    *device = (rs_xpi_psram_t){0};
    status = rs_xpi_psram_timing(memory_clock_hz, &config);
    if (status != RS_OK) {
        return status;
    }
    status = rs_xpi_probe();
    if (status != RS_OK) {
        return status;
    }
    /* Reject locks before issuing any potentially faulting configuration write. */
    if ((RS_XPI_REG(RS_XPI_REG_CONFIG_LOCK) &
         (RS_XPI_CONFIG_LOCK_GLOBAL | RS_XPI_CONFIG_LOCK_SLOT1 | RS_XPI_CONFIG_LOCK_LUT)) != 0U) {
        return RS_EIO;
    }
    status = rs_xpi_enable(false, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_xpi_slot_configure(RS_XPI_PSRAM_SLOT, &config, timeout);
    if (status == RS_OK) {
        status = rs_xpi_lut_write(8U, read_lut, 5U, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_lut_write(9U, write_lut, 4U, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_lut_write(RS_XPI_PSRAM_ID_SEQUENCE, id_lut, 4U, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_enable(true, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_psram_delay(150U, timeout);
    }
    /* Exit QPI is harmless when the device is already in SPI reset mode. */
    if (status == RS_OK) {
        status = rs_xpi_psram_command(UINT8_C(0xf5), RS_XPI_PADS_4, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_psram_command(UINT8_C(0x66), RS_XPI_PADS_1, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_psram_command(UINT8_C(0x99), RS_XPI_PADS_1, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_psram_delay(1U, timeout);
    }
    if (status == RS_OK) {
        transfer.rx_data = device->id;
        status = rs_xpi_transfer(&transfer, timeout);
    }
    if ((status == RS_OK) &&
        ((device->id[0] != UINT8_C(0x0d)) || (device->id[1] != UINT8_C(0x5d)) ||
         (device->id[2] != UINT8_C(0x26)))) {
        status = RS_ENOTSUP;
    }
    if (status == RS_OK) {
        status = rs_xpi_psram_command(UINT8_C(0x35), RS_XPI_PADS_1, timeout);
    }
    if (status == RS_OK) {
        status = rs_xpi_enable(false, timeout);
    }
    if (status == RS_OK) {
        config.memory_read_enable = true;
        config.memory_write_enable = true;
        status = rs_xpi_slot_configure(RS_XPI_PSRAM_SLOT, &config, timeout);
    }
    if (status != RS_OK) {
        /* Keep the first error snapshot. Never publish capacity after a failed
         * probe, and leave mapped NSS1 disabled while restoring NOR access. */
        rs_status_t cleanup = rs_xpi_abort(timeout);
        if (cleanup == RS_OK) {
            cleanup = rs_xpi_enable(false, timeout);
        }
        config.memory_read_enable = false;
        config.memory_write_enable = false;
        if (cleanup == RS_OK) {
            cleanup = rs_xpi_slot_configure(RS_XPI_PSRAM_SLOT, &config, timeout);
        }
        if (cleanup == RS_OK) {
            cleanup = rs_xpi_enable(true, timeout);
        }
        return (cleanup == RS_OK) ? status : cleanup;
    }
    status = rs_xpi_enable(true, timeout);
    if (status == RS_OK) {
        device->capacity_bytes = RS_XPI_PSRAM_BYTES;
        device->memory_clock_hz = memory_clock_hz;
        device->initialized = true;
    }
    return status;
}
