#include <retrosoc/hal/crc.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_crc_status(crc_status_t status) {
    rs_status_t result;

    switch (status) {
    case CRC_STATUS_OK:
        result = RS_OK;
        break;
    case CRC_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case CRC_STATUS_ILLEGAL_STATE:
    case CRC_STATUS_HARDWARE_ERROR:
        result = RS_EIO;
        break;
    case CRC_STATUS_INCOMPATIBLE:
    default:
        result = RS_EFORMAT;
        break;
    }
    return result;
}

rs_status_t rs_crc_get_profile(rs_crc_profile_t profile, rs_crc_config_t *config) {
    return rs_crc_status(crc_get_profile(profile, config));
}

rs_status_t rs_crc_init(const rs_crc_config_t *config) {
    return rs_crc_status(crc_init((uintptr_t)RS_SOC_APB4_CRC_BASE, config));
}

rs_status_t rs_crc_start(void) {
    return rs_crc_status(crc_start((uintptr_t)RS_SOC_APB4_CRC_BASE));
}

rs_status_t rs_crc_update(const void *data, size_t length) {
    return rs_crc_status(crc_update((uintptr_t)RS_SOC_APB4_CRC_BASE, data, length));
}

rs_status_t rs_crc_finish(uint32_t *result) {
    return rs_crc_status(crc_finish((uintptr_t)RS_SOC_APB4_CRC_BASE, result));
}

rs_status_t rs_crc_abort(void) {
    return rs_crc_status(crc_abort((uintptr_t)RS_SOC_APB4_CRC_BASE));
}

rs_status_t rs_crc_compute(const rs_crc_config_t *config, const void *data, size_t length,
                           uint32_t *result) {
    return rs_crc_status(
        crc_compute((uintptr_t)RS_SOC_APB4_CRC_BASE, config, data, length, result));
}

rs_status_t rs_crc_get_status(rs_crc_snapshot_t *snapshot) {
    return rs_crc_status(crc_get_status((uintptr_t)RS_SOC_APB4_CRC_BASE, snapshot));
}

rs_status_t rs_crc_clear_errors(uint32_t mask) {
    return rs_crc_status(crc_clear_errors((uintptr_t)RS_SOC_APB4_CRC_BASE, mask));
}

void rs_crc_shell_test(int argc, char **argv) {
    static const uint8_t check_data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
    rs_crc_config_t config;
    uint32_t result;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_crc_get_profile(RS_CRC_PROFILE_CRC32_ISO_HDLC, &config);
    if (status == RS_OK) {
        status = rs_crc_compute(&config, check_data, sizeof(check_data), &result);
    }
    if (status != RS_OK) {
        printf("[CRC] V2 test failed: %d\n", status);
        return;
    }
    if (result != UINT32_C(0xCBF43926)) {
        printf("[CRC] V2 check mismatch: %x\n", result);
        return;
    }
    printf("[APB IP] CRC V2 CRC-32/ISO-HDLC=%x\n", result);
}
