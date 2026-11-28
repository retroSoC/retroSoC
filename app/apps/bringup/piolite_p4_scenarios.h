#ifndef RETROSOC_PIOLITE_P4_SCENARIOS_H
#define RETROSOC_PIOLITE_P4_SCENARIOS_H

#include <stdbool.h>
#include <stdint.h>

const char *rs_piolite_p4_scenario_name(void);
uint8_t rs_piolite_p4_run_selected(void);
void rs_p4_report_printf(const char *format, ...);
bool rs_p4_report_overflow(void);
void rs_p4_report_flush(void);

#endif
