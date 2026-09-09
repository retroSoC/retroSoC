#include <retrosoc/hal/resource.h>

rs_status_t example_resource(rs_resource_t resource, rs_resource_status_t *status)
{
    return rs_resource_get_status(resource, status);
}
