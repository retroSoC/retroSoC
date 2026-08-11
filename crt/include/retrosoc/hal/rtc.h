#ifndef RETROSOC_RTC_H
#define RETROSOC_RTC_H

#include <rtc.h>
#include <rtc_regs.h>

#include <retrosoc/core/status.h>

typedef rtc_config_t rs_rtc_config_t;
typedef rtc_time_t rs_rtc_time_t;
typedef rtc_alarm_t rs_rtc_alarm_t;
typedef rtc_periodic_t rs_rtc_periodic_t;
typedef rtc_calendar_t rs_rtc_calendar_t;

#ifndef RS_RTC_CLOCK_HZ
#define RS_RTC_CLOCK_HZ UINT32_C(18432000)
#endif

#define RS_RTC_EVENT_SECOND   RTC_EVENT_SECOND_MASK
#define RS_RTC_EVENT_ALARM0   RTC_EVENT_ALARM0_MASK
#define RS_RTC_EVENT_ALARM1   RTC_EVENT_ALARM1_MASK
#define RS_RTC_EVENT_PERIODIC RTC_EVENT_PERIODIC_MASK
#define RS_RTC_EVENT_OVERFLOW RTC_EVENT_OVERFLOW_MASK
#define RS_RTC_EVENT_ALL      RTC_EVENT_VALID_MASK

rs_status_t rs_rtc_probe(void);
rs_status_t rs_rtc_configure(const rs_rtc_config_t *config, rs_timeout_t timeout);
rs_status_t rs_rtc_set_time(const rs_rtc_time_t *time, rs_timeout_t timeout);
rs_status_t rs_rtc_get_time(rs_rtc_time_t *time, rs_timeout_t timeout);
rs_status_t rs_rtc_configure_alarm(uint32_t channel, const rs_rtc_alarm_t *alarm,
                                   rs_timeout_t timeout);
rs_status_t rs_rtc_configure_periodic(const rs_rtc_periodic_t *periodic, rs_timeout_t timeout);
uint32_t rs_rtc_get_events(void);
rs_status_t rs_rtc_clear_events(uint32_t mask, rs_timeout_t timeout);
void rs_rtc_shell_test(int argc, char **argv);

#endif
