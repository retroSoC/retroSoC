#include <retrosoc/core/archinfo.h>

rs_status_t example_archinfo(rs_archinfo_t *info)
{
    rs_status_t result = rs_archinfo_read(info);
    if (result != RS_OK) {
        return result;
    }
    return rs_archinfo_validate_build(info);
}
