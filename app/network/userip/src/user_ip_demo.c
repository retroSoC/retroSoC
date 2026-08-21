#include <stdint.h>

#include <archinfo.h>
#include <archinfo_regs.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/user_ip.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/network/user_ip_demo.h>

#include "user_ip_regs.h"

#define RS_USER_IP_FIXED_SLOT         UINT8_C(0)
#define RS_USER_TIMER_DEFAULT_DIVIDER UINT32_C(2)
#define RS_USER_GPIO_DEMO_OUTPUTS     UINT32_C(0x0000FFFE)

static rs_status_t rs_user_ip_expect_identifier(uint8_t ip_id, uint32_t expected) {
    uint32_t identifier;
    rs_status_t status;

    status = rs_user_ip_probe(ip_id, &identifier);
    if (status != RS_OK) {
        return status;
    }
    return identifier == expected ? RS_OK : RS_EFORMAT;
}

static rs_status_t rs_user_ip_archinfo_demo(void) {
    archinfo_snapshot_t info;
    rs_status_t status;

    status = rs_user_ip_expect_identifier(RS_USER_IP_FIXED_SLOT, ARCHINFO_COMPONENT_ID_VALUE);
    if (status != RS_OK) {
        return status;
    }
    if (archinfo_read((uintptr_t)RS_SOC_APB4_USER_IP_BASE, &info) != ARCHINFO_STATUS_OK) {
        return RS_EIO;
    }

    printf("[FIXED IP] ARCHINFO ABI V2\n");
    printf("[ARCHINFO COMPONENT] %x\n", info.component_id);
    printf("[ARCHINFO SOC/REV] %x/%x\n", info.soc_id, info.soc_revision);
    printf("[ARCHINFO VERSION/CAP] %x/%x\n", info.ip_version, info.capability);
    return RS_OK;
}

static rs_status_t rs_user_ip_timer_demo(void) {
    uint32_t divider;
    uint32_t count;
    rs_status_t status;

    status = rs_user_ip_expect_identifier(RS_USER_TIMER_SLOT, (uint32_t)RS_USER_TIMER_SLOT);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_user_ip_write(RS_USER_TIMER_REG_DIV, RS_USER_TIMER_DEFAULT_DIVIDER) != RS_OK) ||
        (rs_user_ip_write(RS_USER_TIMER_REG_COUNT, UINT32_C(0)) != RS_OK) ||
        (rs_user_ip_read(RS_USER_TIMER_REG_DIV, &divider) != RS_OK)) {
        return RS_EIO;
    }

    printf("[USER IP %u] user timer\n", (uint32_t)RS_USER_TIMER_SLOT);
    printf("divider: %x\n", divider);
    for (uint32_t index = 0U; index < 6U; ++index) {
        if (rs_user_ip_read(RS_USER_TIMER_REG_COUNT, &count) != RS_OK) {
            return RS_EIO;
        }
        printf("[%u] count: %u\n", index, count);
    }
    return RS_OK;
}

static rs_status_t rs_user_ip_gpio_demo(void) {
    uint32_t data_input;
    uint32_t data_output;
    uint32_t readback;
    rs_status_t status;

    status = rs_user_ip_expect_identifier(RS_USER_GPIO_SLOT, (uint32_t)RS_USER_GPIO_SLOT);
    if (status != RS_OK) {
        return status;
    }
    if ((rs_user_ip_write(RS_USER_GPIO_REG_OE, RS_USER_GPIO_DEMO_OUTPUTS) != RS_OK) ||
        (rs_user_ip_write(RS_USER_GPIO_REG_DATA_OUT, UINT32_C(0)) != RS_OK)) {
        return RS_EIO;
    }

    printf("[USER IP %u] user GPIO\n", (uint32_t)RS_USER_GPIO_SLOT);
    data_output = UINT32_C(0);
    for (uint32_t index = 0U; index < 3U; ++index) {
        if (rs_timer_delay_ms(RS_TIMER_0, 1U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            return RS_ETIMEOUT;
        }
        data_output ^= RS_USER_GPIO_DEMO_OUTPUTS;
        if ((rs_user_ip_write(RS_USER_GPIO_REG_DATA_OUT, data_output) != RS_OK) ||
            (rs_user_ip_read(RS_USER_GPIO_REG_DATA_OUT, &readback) != RS_OK) ||
            (readback != data_output)) {
            return RS_EIO;
        }
        printf("[%u] data out: %x\n", index, readback);
    }

    for (uint32_t index = 0U; index < 6U; ++index) {
        if (rs_user_ip_read(RS_USER_GPIO_REG_DATA_IN, &data_input) != RS_OK) {
            return RS_EIO;
        }
        printf("[%u] data in: %x\n", index, data_input);
    }
    return RS_OK;
}

rs_status_t rs_user_ip_demo_run(uint8_t ip_id) {
    switch (ip_id) {
    case RS_USER_IP_FIXED_SLOT:
        return rs_user_ip_archinfo_demo();
    case RS_USER_TIMER_SLOT:
        return rs_user_ip_timer_demo();
    case RS_USER_GPIO_SLOT:
        return rs_user_ip_gpio_demo();
    default:
        return RS_ENOTSUP;
    }
}
