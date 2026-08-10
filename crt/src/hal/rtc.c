#include <retrosoc/hal/rtc.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_rtc_status(rtc_status_t status) {
    rs_status_t result;

    switch (status) {
    case RTC_STATUS_OK:
        result = RS_OK;
        break;
    case RTC_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case RTC_STATUS_TIMEOUT:
        result = RS_ETIMEOUT;
        break;
    case RTC_STATUS_NOT_INITIALIZED:
        result = RS_EFORMAT;
        break;
    case RTC_STATUS_IO_ERROR:
    default:
        result = RS_EIO;
        break;
    }
    return result;
}

rs_status_t rs_rtc_probe(void) {
    return rs_rtc_status(rtc_probe((uintptr_t)RS_SOC_APB_RTC_BASE));
}

rs_status_t rs_rtc_configure(const rs_rtc_config_t *config, rs_timeout_t timeout) {
    return rs_rtc_status(rtc_configure((uintptr_t)RS_SOC_APB_RTC_BASE, config, timeout));
}

rs_status_t rs_rtc_set_time(const rs_rtc_time_t *time, rs_timeout_t timeout) {
    return rs_rtc_status(rtc_set_time((uintptr_t)RS_SOC_APB_RTC_BASE, time, timeout));
}

rs_status_t rs_rtc_get_time(rs_rtc_time_t *time, rs_timeout_t timeout) {
    return rs_rtc_status(rtc_get_time((uintptr_t)RS_SOC_APB_RTC_BASE, time, timeout));
}

rs_status_t rs_rtc_configure_alarm(uint32_t channel, const rs_rtc_alarm_t *alarm,
                                   rs_timeout_t timeout) {
    return rs_rtc_status(
        rtc_configure_alarm((uintptr_t)RS_SOC_APB_RTC_BASE, channel, alarm, timeout));
}

rs_status_t rs_rtc_configure_periodic(const rs_rtc_periodic_t *periodic, rs_timeout_t timeout) {
    return rs_rtc_status(rtc_configure_periodic((uintptr_t)RS_SOC_APB_RTC_BASE, periodic, timeout));
}

uint32_t rs_rtc_get_events(void) {
    return rtc_get_events((uintptr_t)RS_SOC_APB_RTC_BASE);
}

rs_status_t rs_rtc_clear_events(uint32_t mask, rs_timeout_t timeout) {
    return rs_rtc_status(rtc_clear_events((uintptr_t)RS_SOC_APB_RTC_BASE, mask, timeout));
}

void rs_rtc_shell_test(int argc, char **argv) {
    const rs_rtc_config_t config = {
        .second_cycles = RS_RTC_CLOCK_HZ,
        .calibration_ppm = 0,
        .interrupt_enable = 0U,
        .wake_enable = 0U,
        .enable = true,
    };
    const rs_rtc_time_t initial_time = {
        .seconds = UINT64_C(1767225600),
        .subsecond = 0U,
    };
    rs_rtc_time_t snapshot;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_rtc_probe();
    if (status == RS_OK) {
        status = rs_rtc_configure(&config, RS_TIMEOUT_DEFAULT);
    }
    if (status == RS_OK) {
        status = rs_rtc_set_time(&initial_time, RS_TIMEOUT_DEFAULT);
    }
    if (status == RS_OK) {
        status = rs_rtc_get_time(&snapshot, RS_TIMEOUT_DEFAULT);
    }
    if (status != RS_OK) {
        printf("[RTC] V2 test failed: %d\n", status);
        return;
    }
    printf("[APB IP] RTC V2\n");
    printf("[RTC epoch/subsecond] %u/%u\n", (uint32_t)snapshot.seconds,
           (uint32_t)snapshot.subsecond);
}
