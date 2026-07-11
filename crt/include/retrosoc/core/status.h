#ifndef RETROSOC_CORE_STATUS_H
#define RETROSOC_CORE_STATUS_H

#include <stdint.h>

typedef enum {
    RS_OK = 0,
    RS_EINVAL = -1,
    RS_ENOMEM = -2,
    RS_ENOSPC = -3,
    RS_ETIMEOUT = -4,
    RS_EIO = -5,
    RS_ENOTSUP = -6,
    RS_EFORMAT = -7,
} rs_status_t;

typedef uint32_t rs_timeout_t;

#define RS_TIMEOUT_DEFAULT ((rs_timeout_t)1000000U)

#endif
