#ifndef RETROSOC_SERVICE_SHELL_H
#define RETROSOC_SERVICE_SHELL_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_SHELL_MAX_ARGC           16U
#define RS_SHELL_MAX_COMMANDS       72U
#define RS_SHELL_MAX_COMMAND_LENGTH 100U
#define RS_SHELL_MAX_HISTORY        100U
#define RS_SHELL_MAX_PATH           128U
#define RS_SHELL_MAX_BUFFER         (512U * 1024U)

typedef void (*rs_shell_handler_t)(int argc, char **argv);

typedef struct {
    const char *name;
    const char *info;
    bool batch;
    rs_shell_handler_t handler;
} rs_shell_command_t;

rs_status_t rs_shell_register(const char *name, const char *info, bool batch,
                              rs_shell_handler_t handler);
void rs_shell_init(void);
void rs_shell_batch_run(void);
void rs_shell_launch(void);

#endif
