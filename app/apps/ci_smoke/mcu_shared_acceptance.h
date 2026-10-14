#ifndef RETROSOC_APP_MCU_SHARED_ACCEPTANCE_H
#define RETROSOC_APP_MCU_SHARED_ACCEPTANCE_H

#include <stdint.h>

/* Zero means every P6 acceptance case completed; other values identify failure. */
uint8_t rs_tiny_p6_acceptance(void);

#endif
