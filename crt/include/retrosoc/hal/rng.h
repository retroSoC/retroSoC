#ifndef RETROSOC_RNG_H
#define RETROSOC_RNG_H

#include <rng.h>
#include <rng_regs.h>

#include <retrosoc/core/status.h>

typedef rng_config_t rs_rng_config_t;
typedef rng_snapshot_t rs_rng_snapshot_t;

#define RS_RNG_INTERRUPT_DATA_READY   RNG_INTR_DATA_READY_MASK
#define RS_RNG_INTERRUPT_HEALTH_FAIL  RNG_INTR_HEALTH_FAIL_MASK
#define RS_RNG_INTERRUPT_SOURCE_FAULT RNG_INTR_SOURCE_FAULT_MASK
#define RS_RNG_INTERRUPT_ALL          RNG_INTR_ALL_MASK

rs_status_t rs_rng_init(const rs_rng_config_t *config);
rs_status_t rs_rng_get_status(rs_rng_snapshot_t *snapshot);
rs_status_t rs_rng_read_entropy(uint32_t *word, rs_timeout_t timeout);
rs_status_t rs_rng_read_diagnostic(uint32_t *word, rs_timeout_t timeout);
rs_status_t rs_rng_recover(void);
rs_status_t rs_rng_interrupt_enable(uint32_t mask);
rs_status_t rs_rng_interrupt_clear(uint32_t mask);
rs_status_t rs_rng_interrupt_test(uint32_t mask);
void rs_rng_shell_test(int argc, char **argv);

#endif
