#include <limits.h>
#include <stddef.h>

#include <retrosoc/hal/opipsram.h>

#define RS_OPIPSRAM_NANOSECONDS_PER_SECOND UINT64_C(1000000000)
#define RS_OPIPSRAM_CS_SETUP_NS            UINT32_C(3)
#define RS_OPIPSRAM_CS_HOLD_NS             UINT32_C(20)
#define RS_OPIPSRAM_CS_HIGH_NS             UINT32_C(50)
#define RS_OPIPSRAM_POWERUP_NS             UINT32_C(150000)
#define RS_OPIPSRAM_TIMEOUT_DIVISOR        UINT32_C(100)

static bool rs_opipsram_ceil_cycles(uint32_t frequency_hz, uint32_t nanoseconds, uint32_t *cycles) {
    uint64_t numerator;
    uint64_t result;

    if ((frequency_hz == 0U) || (nanoseconds == 0U) || (cycles == NULL) ||
        ((uint64_t)frequency_hz >
         (UINT64_MAX - (RS_OPIPSRAM_NANOSECONDS_PER_SECOND - UINT64_C(1))) /
             (uint64_t)nanoseconds)) {
        return false;
    }
    numerator = ((uint64_t)frequency_hz * (uint64_t)nanoseconds) +
                (RS_OPIPSRAM_NANOSECONDS_PER_SECOND - UINT64_C(1));
    result = numerator / RS_OPIPSRAM_NANOSECONDS_PER_SECOND;
    if ((result == UINT64_C(0)) || (result > UINT32_MAX)) {
        return false;
    }
    *cycles = (uint32_t)result;
    return true;
}

static bool rs_opipsram_power_of_two(uint32_t value) {
    return (value != 0U) && ((value & (value - UINT32_C(1))) == 0U);
}

static bool rs_opipsram_burst_boundary_valid(uint8_t boundary) {
    return (boundary == UINT8_C(4)) || (boundary == UINT8_C(8)) || (boundary == UINT8_C(16)) ||
           (boundary == UINT8_C(32)) || (boundary == UINT8_C(64));
}

static bool rs_opipsram_aperture_range_valid(uintptr_t address, uint32_t byte_count) {
    uint64_t first;
    uint64_t last;

    if ((byte_count == 0U) || (address > (uintptr_t)UINT32_MAX)) {
        return false;
    }
    first = (uint64_t)address;
    last = first + (uint64_t)byte_count - UINT64_C(1);
    return (first >= (uint64_t)RS_SOC_OPIPSRAM_BASE) && (last <= (uint64_t)RS_SOC_OPIPSRAM_END);
}

rs_status_t rs_opipsram_indirect_validate(const rs_opipsram_indirect_t *command,
                                          uint32_t device_size) {
    uint64_t end_address;

    if ((command == NULL) || (command->length == 0U) ||
        (command->length > RS_OPIPSRAM_MAX_INDIRECT_BYTES)) {
        return RS_EINVAL;
    }
    end_address = (uint64_t)command->address + (uint64_t)command->length;
    if (end_address > (uint64_t)RS_OPIPSRAM_MAX_DEVICE_SIZE) {
        return RS_EINVAL;
    }
    if (!command->register_space &&
        ((device_size == 0U) || (device_size > RS_OPIPSRAM_MAX_DEVICE_SIZE) ||
         (end_address > (uint64_t)device_size))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

static uint8_t rs_opipsram_next_tap(uint8_t tap, uint8_t tap_count) {
    return (tap + UINT8_C(1) == tap_count) ? UINT8_C(0) : (uint8_t)(tap + UINT8_C(1));
}

rs_status_t rs_opipsram_timing_from_hz(uint32_t source_clock_hz, uint32_t ck_hz,
                                       rs_opipsram_timing_t *timing) {
    uint64_t denominator;
    uint64_t divider;
    uint64_t actual_phy_hz;
    uint64_t actual_ck_hz;
    uint32_t setup_cycles;
    uint32_t hold_cycles;
    uint32_t high_cycles;
    uint32_t powerup_cycles;
    uint32_t timeout_cycles;

    if ((source_clock_hz == 0U) || (ck_hz == 0U) || (timing == NULL) ||
        (ck_hz < RS_OPIPSRAM_MIN_CK_HZ) || (ck_hz > RS_OPIPSRAM_TARGET_MAX_CK_HZ)) {
        return RS_EINVAL;
    }

    denominator = (uint64_t)ck_hz * (uint64_t)RS_OPIPSRAM_PHY_RATIO;
    if ((denominator == UINT64_C(0)) ||
        ((uint64_t)source_clock_hz > UINT64_MAX - denominator + UINT64_C(1))) {
        return RS_EINVAL;
    }
    divider = ((uint64_t)source_clock_hz + denominator - UINT64_C(1)) / denominator;
    if ((divider == UINT64_C(0)) || (divider > UINT16_MAX)) {
        return RS_EINVAL;
    }
    actual_phy_hz = (uint64_t)source_clock_hz / divider;
    actual_ck_hz = actual_phy_hz / (uint64_t)RS_OPIPSRAM_PHY_RATIO;
    if ((actual_phy_hz == UINT64_C(0)) || (actual_ck_hz == UINT64_C(0)) ||
        ((actual_phy_hz % (uint64_t)RS_OPIPSRAM_PHY_RATIO) != UINT64_C(0)) ||
        (actual_ck_hz < RS_OPIPSRAM_MIN_CK_HZ) || (actual_ck_hz > RS_OPIPSRAM_TARGET_MAX_CK_HZ) ||
        (actual_phy_hz > UINT32_MAX)) {
        return RS_EINVAL;
    }

    if (!rs_opipsram_ceil_cycles(source_clock_hz, RS_OPIPSRAM_CS_SETUP_NS, &setup_cycles) ||
        !rs_opipsram_ceil_cycles(source_clock_hz, RS_OPIPSRAM_CS_HOLD_NS, &hold_cycles) ||
        !rs_opipsram_ceil_cycles(source_clock_hz, RS_OPIPSRAM_CS_HIGH_NS, &high_cycles) ||
        !rs_opipsram_ceil_cycles(source_clock_hz, RS_OPIPSRAM_POWERUP_NS, &powerup_cycles) ||
        (setup_cycles > UINT16_MAX) || (hold_cycles > UINT16_MAX) || (high_cycles > UINT16_MAX)) {
        return RS_EINVAL;
    }

    timeout_cycles = source_clock_hz / RS_OPIPSRAM_TIMEOUT_DIVISOR;
    if (timeout_cycles <= powerup_cycles) {
        if (powerup_cycles == UINT32_MAX) {
            return RS_EINVAL;
        }
        timeout_cycles = powerup_cycles + UINT32_C(1);
    }

    timing->divider = (uint16_t)divider;
    timing->phy_ratio = (uint8_t)RS_OPIPSRAM_PHY_RATIO;
    timing->source_clock_hz = source_clock_hz;
    timing->requested_ck_hz = ck_hz;
    timing->actual_phy_hz = (uint32_t)actual_phy_hz;
    timing->actual_ck_hz = (uint32_t)actual_ck_hz;
    timing->cs_setup_cycles = (uint16_t)setup_cycles;
    timing->cs_hold_cycles = (uint16_t)hold_cycles;
    timing->cs_high_cycles = (uint16_t)high_cycles;
    timing->powerup_cycles = powerup_cycles;
    timing->timeout_cycles = timeout_cycles;
    return RS_OK;
}

rs_status_t rs_opipsram_timing_validate(const rs_opipsram_timing_t *timing) {
    uint64_t expected_phy_hz;

    if ((timing == NULL) || (timing->divider == 0U) ||
        (timing->phy_ratio != (uint8_t)RS_OPIPSRAM_PHY_RATIO) || (timing->source_clock_hz == 0U) ||
        (timing->requested_ck_hz == 0U) || (timing->requested_ck_hz < RS_OPIPSRAM_MIN_CK_HZ) ||
        (timing->requested_ck_hz > RS_OPIPSRAM_TARGET_MAX_CK_HZ) || (timing->actual_ck_hz == 0U) ||
        (timing->actual_ck_hz < RS_OPIPSRAM_MIN_CK_HZ) ||
        (timing->actual_ck_hz > RS_OPIPSRAM_TARGET_MAX_CK_HZ) || (timing->actual_phy_hz == 0U) ||
        (timing->cs_setup_cycles == 0U) || (timing->cs_hold_cycles == 0U) ||
        (timing->cs_high_cycles == 0U) || (timing->powerup_cycles == 0U) ||
        (timing->timeout_cycles <= timing->powerup_cycles) ||
        (timing->cs_setup_cycles > UINT8_MAX) || (timing->cs_hold_cycles > UINT8_MAX) ||
        (timing->cs_high_cycles > UINT8_MAX)) {
        return RS_EINVAL;
    }
    expected_phy_hz = (uint64_t)timing->actual_ck_hz * (uint64_t)timing->phy_ratio;
    if ((expected_phy_hz != (uint64_t)timing->actual_phy_hz) ||
        ((uint64_t)timing->source_clock_hz / (uint64_t)timing->divider !=
         (uint64_t)timing->actual_phy_hz) ||
        (timing->actual_phy_hz > timing->source_clock_hz)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_opipsram_config_validate(const rs_opipsram_config_t *config) {
    if ((config == NULL) ||
        ((config->profile != RS_OPIPSRAM_PROFILE_OPI) &&
         (config->profile != RS_OPIPSRAM_PROFILE_HYPERBUS)) ||
        (config->device_size == 0U) || (config->device_size > RS_OPIPSRAM_MAX_DEVICE_SIZE) ||
        !rs_opipsram_power_of_two(config->device_size) ||
        (rs_opipsram_timing_validate(&config->timing) != RS_OK)) {
        return RS_EINVAL;
    }

    if (config->profile == RS_OPIPSRAM_PROFILE_OPI) {
        if (((config->opi.command_width != RS_OPIPSRAM_COMMAND_WIDTH_8) &&
             (config->opi.command_width != RS_OPIPSRAM_COMMAND_WIDTH_16)) ||
            ((config->opi.address_width != RS_OPIPSRAM_ADDRESS_WIDTH_24) &&
             (config->opi.address_width != RS_OPIPSRAM_ADDRESS_WIDTH_32)) ||
            (config->opi.dummy_cycles > RS_OPIPSRAM_MAX_DUMMY_CYCLES) ||
            (config->opi.latency_cycles > RS_OPIPSRAM_MAX_LATENCY_CYCLES) ||
            (config->opi.dqs_policy > RS_OPIPSRAM_DQS_READ_WRITE) ||
            !rs_opipsram_burst_boundary_valid(config->opi.burst_boundary)) {
            return RS_EINVAL;
        }
    } else if ((config->hyperbus.initial_latency == 0U) ||
               (config->hyperbus.initial_latency > RS_OPIPSRAM_MAX_LATENCY_CYCLES) ||
               (config->hyperbus.additional_latency > RS_OPIPSRAM_MAX_LATENCY_CYCLES) ||
               (config->hyperbus.read_recovery_cycles == 0U) ||
               (config->hyperbus.write_recovery_cycles == 0U) ||
               (config->hyperbus.write_recovery_cycles > UINT8_C(127))) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_opipsram_training_window_from_mask(uint32_t passing_taps, uint8_t tap_count,
                                                  rs_opipsram_training_window_t *window) {
    uint32_t valid_mask;
    uint8_t best_first = UINT8_C(0);
    uint8_t best_last = UINT8_C(0);
    uint8_t best_width = UINT8_C(0);
    uint8_t candidate;

    if ((tap_count == 0U) || (tap_count > RS_OPIPSRAM_MAX_TRAIN_TAPS) || (window == NULL)) {
        return RS_EINVAL;
    }
    if (tap_count == RS_OPIPSRAM_MAX_TRAIN_TAPS) {
        valid_mask = UINT32_MAX;
    } else {
        valid_mask = (UINT32_C(1) << tap_count) - UINT32_C(1);
    }
    passing_taps &= valid_mask;
    window->valid = false;
    window->wrapped = false;
    window->first = UINT8_C(0);
    window->last = UINT8_C(0);
    window->width = UINT8_C(0);
    window->center = UINT8_C(0);
    if (passing_taps == UINT32_C(0)) {
        return RS_OK;
    }
    if (passing_taps == valid_mask) {
        best_first = UINT8_C(0);
        best_last = (uint8_t)(tap_count - UINT8_C(1));
        best_width = tap_count;
    } else {
        for (candidate = UINT8_C(0); candidate < tap_count; candidate++) {
            uint8_t previous = (candidate == UINT8_C(0)) ? (uint8_t)(tap_count - UINT8_C(1))
                                                         : (uint8_t)(candidate - UINT8_C(1));
            uint8_t width = UINT8_C(0);
            uint8_t tap = candidate;

            if (((passing_taps & (UINT32_C(1) << candidate)) != UINT32_C(0)) &&
                ((passing_taps & (UINT32_C(1) << previous)) == UINT32_C(0))) {
                do {
                    width++;
                    tap = rs_opipsram_next_tap(tap, tap_count);
                } while ((width < tap_count) &&
                         ((passing_taps & (UINT32_C(1) << tap)) != UINT32_C(0)));
                if (width > best_width) {
                    best_first = candidate;
                    best_last = (tap == UINT8_C(0)) ? (uint8_t)(tap_count - UINT8_C(1))
                                                    : (uint8_t)(tap - UINT8_C(1));
                    best_width = width;
                }
            }
        }
    }
    window->valid = best_width != UINT8_C(0);
    window->first = best_first;
    window->last = best_last;
    window->width = best_width;
    window->wrapped = window->valid && (best_first > best_last);
    window->center = (uint8_t)((best_first + (best_width / UINT8_C(2))) % tap_count);
    return RS_OK;
}

rs_status_t rs_opipsram_training_sweep(rs_opipsram_train_probe_t probe, void *context,
                                       uint8_t tap_count, rs_opipsram_training_window_t *window) {
    uint32_t passing_taps = UINT32_C(0);
    uint8_t tap;

    if ((probe == NULL) || (window == NULL) || (tap_count == 0U) ||
        (tap_count > RS_OPIPSRAM_MAX_TRAIN_TAPS)) {
        return RS_EINVAL;
    }
    for (tap = UINT8_C(0); tap < tap_count; tap++) {
        if (probe(tap, context)) {
            passing_taps |= UINT32_C(1) << tap;
        }
    }
    return rs_opipsram_training_window_from_mask(passing_taps, tap_count, window);
}

rs_status_t rs_opipsram_dma_copy_validate(uint32_t channel, uintptr_t source, uintptr_t destination,
                                          uint32_t byte_count, uint8_t priority,
                                          uint8_t burst_beats, rs_dma_config_t *config) {
    bool source_in_aperture;
    bool destination_in_aperture;

    if ((config == NULL) || (byte_count == 0U) || ((byte_count % sizeof(uint32_t)) != 0U) ||
        ((source % sizeof(uint32_t)) != 0U) || ((destination % sizeof(uint32_t)) != 0U)) {
        return RS_EINVAL;
    }
    source_in_aperture = rs_opipsram_aperture_range_valid(source, byte_count);
    destination_in_aperture = rs_opipsram_aperture_range_valid(destination, byte_count);
    if (!source_in_aperture && !destination_in_aperture) {
        return RS_EINVAL;
    }

    config->kind = RS_DMA_KIND_MM_TO_MM;
    config->request = RS_DMA_REQUEST_SOFTWARE;
    config->source = source;
    config->destination = destination;
    config->byte_count = byte_count;
    config->width = RS_DMA_WIDTH_32;
    config->source_increment = true;
    config->destination_increment = true;
    config->priority = priority;
    config->burst_beats = burst_beats;
    return rs_dma_config_validate(channel, config);
}
