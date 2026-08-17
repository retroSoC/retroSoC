#include <archinfo_integration_metadata.h>
#include <archinfo_regs.h>
#include <retrosoc/core/archinfo.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_archinfo_status(archinfo_status_t status) {
    rs_status_t result;

    switch (status) {
    case ARCHINFO_STATUS_OK:
        result = RS_OK;
        break;
    case ARCHINFO_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case ARCHINFO_STATUS_UNAVAILABLE:
        result = RS_ENOTSUP;
        break;
    case ARCHINFO_STATUS_INCOMPATIBLE:
    default:
        result = RS_EFORMAT;
        break;
    }

    return result;
}

rs_status_t rs_archinfo_read(rs_archinfo_t *info) {
    return rs_archinfo_status(archinfo_read((uintptr_t)RS_SOC_APB4_ARCHINFO_BASE, info));
}

rs_status_t rs_archinfo_validate_build(const rs_archinfo_t *info) {
    const archinfo_build_expectation_t expectation = {
        .check_build_id =
            (ARCHINFO_INTEGRATION_BUILD_STATUS & ARCHINFO_BUILD_SOURCE_KNOWN_MASK) != 0U,
        .check_config_id = true,
        .build_id = ARCHINFO_INTEGRATION_BUILD_ID,
        .config_id = ARCHINFO_INTEGRATION_CONFIG_ID,
    };

    return rs_archinfo_status(archinfo_validate(info, &expectation));
}

rs_status_t rs_archinfo_read_device_id(uint32_t device_id[4]) {
    return rs_archinfo_status(
        archinfo_read_device_id((uintptr_t)RS_SOC_APB4_ARCHINFO_BASE, device_id));
}

void ip_archinfo_test(int argc, char **argv) {
    rs_archinfo_t info;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_archinfo_read(&info);
    if (status != RS_OK) {
        printf("[ARCHINFO] read failed: %d\n", status);
        return;
    }

    printf("[APB IP] archinfo ABI V2\n");
    printf("[ARCHINFO COMPONENT] %x\n", info.component_id);
    printf("[ARCHINFO SOC/REV] %x/%x\n", info.soc_id, info.soc_revision);
    printf("[ARCHINFO BUILD] %x%x status=%x\n", (uint32_t)(info.build_id >> 32U),
           (uint32_t)info.build_id, info.build_status);
    printf("[ARCHINFO CONFIG] %x\n", info.config_id);
    printf("[ARCHINFO CLOCK/SRAM] %u/%u\n", info.reference_clock_hz, info.sram_bytes);
    printf("[ARCHINFO TOPOLOGY/FEATURES] %x/%x\n", info.topology, info.features0);
    printf("[ARCHINFO TECHNOLOGY] %x\n", info.technology);
    printf("[ARCHINFO VERSION/CAP] %x/%x\n", info.ip_version, info.capability);
}
