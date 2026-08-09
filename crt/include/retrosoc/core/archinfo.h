#ifndef RETROSOC_ARCHINFO_H
#define RETROSOC_ARCHINFO_H

#include <stdint.h>

#include <archinfo.h>
#include <retrosoc/core/status.h>

typedef archinfo_snapshot_t rs_archinfo_t;

rs_status_t rs_archinfo_read(rs_archinfo_t *info);
rs_status_t rs_archinfo_validate_build(const rs_archinfo_t *info);
rs_status_t rs_archinfo_read_device_id(uint32_t device_id[4]);
void ip_archinfo_test(int argc, char **argv);

#endif
